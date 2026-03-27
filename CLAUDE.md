# CLAUDE.md

## Project Overview

melange-tracker is a tool for tracking upstream [rescript-lang/rescript](https://github.com/rescript-lang/rescript) commits as cherry-pick candidates for [melange](https://github.com/melange-re/melange). Melange is a fork of an earlier ReScript compiler version, and bug fixes made upstream often apply with manual adaptation.

## Structure

```
.devcontainer/   — Dev container config (OCaml toolchain + auto upstream fetch)
.github/         — CI workflows (devcontainer build)
tracker/         — Cherry-pick tracking CLI + JSON database
  tracker.sh     — Main script: scan, triage, plan, advance, report
  db/            — One JSON file per tracked upstream commit
docs/            — Design docs, fork analysis, candidate rankings
melange/         — Git submodule (melange-re/melange)
```

## Key Commands

```sh
# Scan upstream for new commits (requires upstream remote in melange/)
tracker/tracker.sh scan [since-date]

# Show high-priority candidates
tracker/tracker.sh report

# Triage a commit
tracker/tracker.sh triage <hash> relevant|irrelevant|wont_pick [reason]

# Add adaptation plan
tracker/tracker.sh plan <hash> "description"

# Advance through stages: discovered → triaged → planned → in_progress → testing → merged
tracker/tracker.sh advance <hash>

# Summary stats
tracker/tracker.sh status
```

## Setup (in devcontainer or locally)

The melange submodule needs the upstream rescript remote:

```sh
git submodule update --init --recursive --depth 1
cd melange
git remote add upstream https://github.com/rescript-lang/rescript.git
git fetch upstream
```

The devcontainer `postCreateCommand` does this automatically.

## Environment Variables

- `MELANGE_DIR` — Path to melange checkout (default: `../melange` relative to tracker/)
- `UPSTREAM_REMOTE` — Git remote name for rescript (default: `upstream`)
- `UPSTREAM_BRANCH` — Upstream branch to scan (default: `master`)

## Design Documents

- `docs/design.md` — Workflow stages, auto-classification heuristics, DB schema
- `docs/analysis.md` — Fork divergence analysis (fork point, code overlap areas)
- `docs/candidates.md` — Ranked cherry-pick candidates with status

## Workflow Stages

```
discovered → triaged → planned → in_progress → testing → merged
                ↘ irrelevant (terminal)
                ↘ wont_pick (terminal)
```

## Key Details

- Database: one JSON file per commit in `tracker/db/`, keyed by short hash
- Auto-classification: bug fixes in `jscomp/core/` or `compiler/core/` are `high_priority`
- The tracker shell script requires `python3` for JSON manipulation
- Rescript renamed `jscomp/` → `compiler/` in 2024; the scanner checks both paths
