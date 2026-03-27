# System Design

## Overview

The cherry-pick tracker is a CLI tool + JSON database that manages the lifecycle of upstream rescript commits as cherry-pick candidates for melange.

## Workflow Stages

Each upstream commit progresses through these stages:

```
discovered --> triaged --> planned --> in_progress --> testing --> merged
                 \-> irrelevant (terminal)
                 \-> wont_pick (terminal)
```

| Stage | Description |
|-------|-------------|
| `discovered` | Automatically found by the scanner |
| `triaged` | Reviewed; marked as relevant |
| `planned` | Adaptation plan written |
| `in_progress` | Cherry-pick branch created, work underway |
| `testing` | PR opened, CI running |
| `merged` | PR merged into melange |
| `irrelevant` | Not applicable to melange (terminal) |
| `wont_pick` | Relevant but cost/benefit doesn't justify porting (terminal) |

## Auto-Classification Heuristics

The scanner classifies commits into categories based on commit message and files changed:

### `irrelevant` (auto-triaged)
- Commit message matches: `^(bump |set version|prepare for .* release|ci:|GA\(deps\))`
- Only touches rescript-specific paths (`rewatch/`, `bsb/`, `rescript-editor-analysis/`)
- Only touches `.res`/`.resi` files with no `.ml` files

### `high_priority`
- Touches ML files in shared code paths (`jscomp/core/`, `compiler/core/`, etc.)
- AND commit message contains fix/crash/bug/regression/incorrect/wrong/broken

### `candidate`
- Touches ML files in shared code paths
- Not a bug fix (feature, improvement, refactoring)

### `needs_review`
- Everything else

## Database Schema

Each commit is stored as `db/<short-hash>.json`:

```json
{
  "hash": "05c10e304",
  "subject": "Fix code generation for emojis in polyvars and labels (#7853)",
  "author": "Christoph Knittel",
  "date": "2025-09-07 19:31:45 +0200",
  "files_changed": ["compiler/core/js_dump_string.ml", ...],
  "auto_category": "high_priority",
  "status": "planned",
  "reason": "UTF-8 emoji bug confirmed present in melange js_dump_string.ml:81-85",
  "plan": "1) Add Utf8.classify to melstd. 2) Rewrite escape loop...",
  "pr_url": "",
  "melange_branch": "",
  "discovered_at": "2026-03-26T14:34:14.239826",
  "updated_at": "2026-03-26T14:36:16+00:00",
  "notes": []
}
```

### Design decisions

**One file per commit**: Makes diffs reviewable and avoids merge conflicts when multiple people triage in parallel.

**Short hash as key**: Matches git's default display. Collision risk is negligible for the ~300 commits in scope.

**Environment variables for overrides**: `MELANGE_DIR`, `UPSTREAM_REMOTE`, `UPSTREAM_BRANCH` allow running against different setups without modifying the script.

**Python for JSON**: Bash has no native JSON support. Python3 is available in the devcontainer and handles escaping correctly.

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
