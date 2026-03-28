# CLAUDE.md

## Project Overview

melange-tracker is a tool for tracking upstream [rescript-lang/rescript](https://github.com/rescript-lang/rescript) commits as cherry-pick candidates for [melange](https://github.com/melange-re/melange). Melange is a fork of an earlier ReScript compiler version, and bug fixes made upstream often apply with manual adaptation.

## Structure

```
.devcontainer/   — Dev container config (OCaml toolchain + auto upstream fetch)
.github/         — CI workflows (devcontainer build)
tracker/         — Cherry-pick tracking CLI (OCaml + cmdliner)
  bin/main.ml    — CLI entry point with cmdliner subcommands
  lib/types.ml   — Core types with ppx_deriving_jsont for YAML serialization
  lib/db.ml      — Load/save single YAML database via yamlt
  lib/git.ml     — Shell out to git for commit info
  lib/scanner.ml — Scan upstream commits with auto-classification
  lib/commands.ml — All CLI command implementations
  db.yaml        — Single YAML database file
docs/            — Design docs, fork analysis, candidate rankings
modules/         — Git submodules (yamlt, yamlrw, bytesrw-eio)
melange/         — Git submodule (melange-re/melange)
```

## Build & Common Targets

```sh
make                    # Build everything (dune build)
make clean              # Clean build artifacts
make format             # Format code (dune fmt)
make tracker-status     # Show tracker summary stats
make tracker-queue      # List unanalyzed commits
make tracker-report     # Show actionable candidates by stage
make tracker-verify     # Verify merge-ready candidates and dependencies
make tracker-scan       # Scan upstream for new commits
make melange-setup      # Init submodule + add upstream remote
make melange-build      # Build melange (dune build in melange/)
make melange-test       # Run melange tests (dune runtest in melange/)
make opam-install-test  # Install opam deps including test deps
```

## Tracker CLI

The tracker is an OCaml executable using cmdliner. Run directly via dune:

```sh
opam exec -- dune exec tracker/bin/main.exe -- <command> [args]
```

### Commands

```sh
tracker scan [--since DATE]        # Scan upstream for new commits, add as Queued
tracker status                     # Summary stats by status category
tracker list [--status STATUS]     # List entries, optionally filtered
tracker show HASH                  # Show entry + git commit details (fetched live)
tracker queue                      # List all Queued entries (triage queue)
tracker triage HASH STATUS [REASON] # Set status (irrelevant|wont_pick|deferred|undecided|candidate)
tracker plan HASH NOTES            # Set candidate to Planned stage with notes
tracker advance HASH               # Advance candidate stage (planned → in_progress)
tracker depend HASH DEP_HASH...    # Add dependency links
tracker pr HASH PR_ID              # Record PR for a candidate
tracker merge HASH MELANGE_HASH    # Record merge with melange commit hash
tracker report                     # Show actionable candidates grouped by stage
tracker verify                     # Verify merge-ready candidates + dependency chain
```

## Setup (in devcontainer or locally)

The melange submodule needs the upstream rescript remote:

```sh
make melange-setup
```

Or manually:

```sh
git submodule update --init --recursive --depth 1
cd melange
git remote add upstream https://github.com/rescript-lang/rescript.git
git fetch upstream
```

The devcontainer `postCreateCommand` does this automatically.

## Melange Build Verification

To verify that melange builds and tests pass (mirrors CI at
[TheCBaH/melange devcontainer-build.yml](https://github.com/TheCBaH/melange/blob/devel/.github/workflows/devcontainer-build.yml)):

```sh
make melange-setup       # init submodule + upstream remote
make opam-install-test   # install deps including test deps
make melange-build       # dune build in melange/
make melange-test        # dune runtest in melange/
```

## Environment Variables

- `MELANGE_DIR` — Path to melange checkout (default: `../melange` relative to tracker/)
- `TRACKER_DIR` — Path to directory containing `db.yaml` (default: `.`)

## Data Model

The tracker stores only metadata not present in git commits. Git info (subject, author, date, files) is fetched live.

### Database fields

- `upstream_remote` — git remote name (default: `upstream`)
- `upstream_branch` — branch to scan (default: `master`)
- `last_scan_commit` — hash of the last scanned upstream commit; scan uses `git log <last_scan_commit>..<remote>/<branch>` to fetch only new commits
- `entries` — list of tracked commits

### Status types (OCaml variants):

```
Queued                              — unanalyzed, in the triage queue
Deferred { reason }                 — needs future analysis
Undecided { notes }                 — analyzed, status not yet decided
Irrelevant { reason }               — terminal: not applicable
Wont_pick { reason }                — terminal: decided against
Candidate { stage; depends_on; notes } — subject for integration
```

### Candidate stages:

```
Planned → In_progress → Pull_request { pr_id } → Merged { melange_hash }
```

### Dependencies

Candidates can declare `depends_on` — a list of commit hashes that must be picked together. The `verify` command checks dependency chains for correctness.

## Design Documents

- `docs/design.md` — Workflow stages, data model, YAML schema
- `docs/analysis.md` — Fork divergence analysis (fork point, code overlap areas)
- `docs/candidates.md` — Ranked cherry-pick candidates with status

## Key Details

- Database: single `tracker/db.yaml` file, serialized via yamlt (YAML codec using Jsont type descriptions)
- Types derived with `ppx_deriving_jsont` for automatic YAML round-tripping
- Auto-classification: bug fixes in `jscomp/core/` or `compiler/core/` are high priority
- Rescript renamed `jscomp/` → `compiler/` in 2024; the scanner checks both paths
- Dependencies: yamlt, yamlrw, jsont, bytesrw (in modules/), cmdliner, ppx_deriving_jsont (opam)
