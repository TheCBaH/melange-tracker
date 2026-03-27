# melange-tracker

Tracks upstream [rescript-lang/rescript](https://github.com/rescript-lang/rescript) commits for potential cherry-picks into [melange](https://github.com/melange-re/melange).

## Background

Melange is a fork of an earlier version of the ReScript compiler, focused on OCaml ecosystem integration via Dune. The projects share significant code in the JS code generation backend (`jscomp/core/`) but have diverged over 5+ years of independent development.

Bug fixes and improvements made upstream in rescript often apply to melange, but require manual adaptation due to:
- Renamed modules (`ext/` -> `melstd/`)
- Different build systems (dune vs bsb/ninja)
- Different attribute namespaces (`@mel.*` vs `@bs.*`)
- Structural changes to shared data types

## Structure

```
.devcontainer/   — Dev container for the project
tracker/         — Cherry-pick tracking tool + database
  tracker.sh     — CLI for scanning, triaging, and tracking commits
  db/            — JSON database (one file per tracked commit)
docs/            — Design documents and analysis
melange/         — Git submodule (melange repo with upstream remote)
```

## Quick Start

```bash
# Scan upstream for new commits (requires upstream remote in melange/)
tracker/tracker.sh scan

# See high-priority candidates
tracker/tracker.sh report

# Check overall status
tracker/tracker.sh status

# Triage a commit
tracker/tracker.sh triage <hash> relevant "reason"
tracker/tracker.sh triage <hash> irrelevant "reason"

# Plan adaptation and advance through stages
tracker/tracker.sh plan <hash> "adaptation description"
tracker/tracker.sh advance <hash>
```

## Setup

The melange submodule needs the upstream remote configured:

```bash
cd melange
git remote add upstream https://github.com/rescript-lang/rescript.git
git fetch upstream
```

This is done automatically by the devcontainer post-create command.
