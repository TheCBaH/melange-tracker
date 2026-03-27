# Cherry-Pick Tracker

Tracks upstream rescript-lang/rescript commits for potential cherry-picks into melange.

## Workflow Stages

Each upstream commit progresses through these stages:

```
discovered → triaged → planned → in_progress → testing → merged
                ↘ irrelevant (terminal)
                ↘ wont_pick (terminal — relevant but not worth the effort)
```

- **discovered**: Automatically found by the scanner
- **triaged**: Human or AI reviewed; marked relevant or irrelevant
- **planned**: Adaptation plan written (what files to change, dependencies)
- **in_progress**: Cherry-pick branch created, work underway
- **testing**: PR opened, CI running
- **merged**: PR merged into melange
- **irrelevant**: Commit doesn't apply to melange (rescript-specific feature, tooling, etc.)
- **wont_pick**: Relevant but cost/benefit doesn't justify porting

## Usage

```bash
# Scan upstream for new commits
./tracker.sh scan

# Show all commits in a given status
./tracker.sh list [status]

# Triage a commit
./tracker.sh triage <hash> <relevant|irrelevant|wont_pick> [reason]

# Add a plan for a commit
./tracker.sh plan <hash> "description of adaptation needed"

# Advance a commit to next stage
./tracker.sh advance <hash> [stage]

# Show summary statistics
./tracker.sh status

# Generate a report of actionable items
./tracker.sh report
```

## Database

The database is stored in `db/` as individual JSON files per commit (keyed by
short hash). This makes diffs reviewable and merge-conflict-free.

## Scanner Heuristics

The scanner automatically classifies commits using these rules:

**Likely relevant** (auto-triage as candidate):
- Touches `jscomp/core/` or `compiler/core/` (JS codegen backend)
- Touches `jscomp/runtime/` or `compiler/runtime/` (runtime primitives)
- Commit message contains "fix" (case-insensitive)
- Touches `.ml` files in shared modules

**Likely irrelevant** (auto-triage as irrelevant):
- Only touches `bsb/`, `rewatch/`, `rescript-editor-analysis/`
- Only bumps npm/JS dependencies
- Only touches `.res`/`.resi` files (ReScript syntax specific)
- Commit message matches "Set version", "Bump", "CI", "changelog"

**Needs human review**:
- Everything else
