# System Design

## Overview

The cherry-pick tracker is an OCaml CLI tool with a single YAML database that manages the lifecycle of upstream rescript commits as cherry-pick candidates for melange. It uses cmdliner for the CLI interface and yamlt (with ppx_deriving_jsont) for type-safe YAML serialization.

## Data Model

The database only stores metadata not present in git commits. Git information (subject, author, date, files changed) is fetched on demand from the melange submodule.

### OCaml Types

```ocaml
type candidate_stage =
  | Planned
  | In_progress
  | Pull_request of { pr_id : int }
  | Merged of { melange_hash : string }

type status =
  | Queued
  | Deferred of { reason : string }
  | Undecided of { notes : string }
  | Irrelevant of { reason : string }
  | Wont_pick of { reason : string }
  | Candidate of {
      stage : candidate_stage;
      depends_on : string list;
      notes : string;
    }

type entry = {
  hash : string;
  status : status;
}

type db = {
  upstream_remote : string;
  upstream_branch : string;
  last_scan : string option;
  entries : entry list;
}
```

All types use `[@@deriving jsont]` with `ppx_deriving_jsont`, which generates Jsont codecs that yamlt interprets for YAML serialization. Variant types use discriminated unions with a `kind` or `stage` type key.

### YAML Schema

```yaml
upstream_remote: upstream
upstream_branch: master
last_scan: "2026-03-28"
entries:
  - hash: e92879ea2
    status:
      kind: Queued

  - hash: d47de1d1a
    status:
      kind: Deferred
      reason: "Wait for melange 5.0 release"

  - hash: fa073e8ec
    status:
      kind: Candidate
      stage:
        stage: Pull_request
        pr_id: 42
      depends_on: []
      notes: "Clean cherry-pick, minor path fixup"

  - hash: 05c10e304
    status:
      kind: Candidate
      stage:
        stage: Merged
        melange_hash: abc123def
      depends_on:
        - fa073e8ec
      notes: "Required emoji polyvar fix from fa073e8ec first"

  - hash: 74b4273b4
    status:
      kind: Irrelevant
      reason: "ReScript-specific JSX transform"
```

## Workflow Stages

```
Queued → Deferred (needs future analysis)
       → Undecided (analyzed, not yet decided)
       → Irrelevant (terminal)
       → Wont_pick (terminal)
       → Candidate:
           Planned → In_progress → Pull_request { pr_id } → Merged { melange_hash }
```

| Status | Description |
|--------|-------------|
| `Queued` | Unanalyzed, in the triage queue |
| `Deferred` | Needs future analysis, with reason |
| `Undecided` | Analyzed but status not yet decided |
| `Irrelevant` | Not applicable to melange (terminal) |
| `Wont_pick` | Relevant but not worth porting (terminal) |
| `Candidate/Planned` | Adaptation plan written |
| `Candidate/In_progress` | Cherry-pick work underway |
| `Candidate/Pull_request` | PR open against melange, with PR id |
| `Candidate/Merged` | Landed in melange, with melange commit hash |

## Dependencies

Candidates can declare `depends_on` — a list of upstream commit hashes that must be cherry-picked together or in order. The `verify` command performs a recursive dependency check:

- Merged dependencies: OK
- PR dependencies: warning (not yet merged)
- In-progress/Planned dependencies: error (not ready)
- Circular dependencies: error
- Missing dependencies: error

## Auto-Classification Heuristics

The scanner classifies commits into categories based on commit message and files changed:

### `irrelevant` (auto-triaged)
- Commit message matches: bump, version, changelog, ci:, chore:, release
- Only touches rescript-specific paths (`rewatch/`, `tools/`, `runtime/`, `cli/`, `npm/`, `scripts/`)
- Only touches `.res`/`.resi` files with no `.ml` files

### `high_priority`
- Touches ML files in shared code paths (`jscomp/core/`, `compiler/core/`, etc.)
- AND commit message contains fix/crash/bug/regression/incorrect/wrong/broken

### `candidate`
- Touches ML files in shared code paths
- Not a bug fix (feature, improvement, refactoring)

### `needs_review`
- Everything else

## Relevant Code Paths

These upstream paths map to melange equivalents:

| Upstream (old) | Upstream (new) | Melange |
|---------------|----------------|---------|
| `jscomp/core/` | `compiler/core/` | `jscomp/core/` |
| `jscomp/runtime/` | `compiler/runtime/` | `jscomp/runtime/` |
| `jscomp/ext/` | `compiler/ext/` | `jscomp/melstd/` |
| `jscomp/common/` | `compiler/common/` | `jscomp/common/` |
| `jscomp/ml/` | `compiler/ml/` | `vendor/melange-compiler-libs/` |
| `jscomp/stdlib/` | `compiler/stdlib/` | `jscomp/stdlib/` |
| `jscomp/others/` | `compiler/others/` | `jscomp/others/` |

Note: rescript renamed `jscomp/` to `compiler/` in PR #7086 (2024). The scanner checks both paths.

## Architecture

```
tracker/bin/main.ml     — cmdliner CLI, wires subcommands to Commands module
tracker/lib/types.ml    — Core types with [@@deriving jsont]
tracker/lib/db.ml       — YAML load/save via yamlt, entry lookup/update
tracker/lib/git.ml      — Shell out to git for live commit info
tracker/lib/scanner.ml  — Upstream scan + auto-classification
tracker/lib/commands.ml — Command implementations
```

### Design Decisions

**Single YAML file**: Simpler than per-commit JSON files. Human-readable and hand-editable. yamlt handles serialization with type safety.

**No git info in DB**: Subject, author, date, files are fetched live from git. The database only stores the hash (as identifier) and human-added metadata (status, dependencies, notes, PR/merge info).

**ppx_deriving_jsont**: Automatically derives Jsont codecs for variant types. The same codec works for both JSON and YAML via yamlt.

**Dependency tracking**: The `depends_on` field on candidates enables `verify` to check that cherry-picks are applied in the correct order.
