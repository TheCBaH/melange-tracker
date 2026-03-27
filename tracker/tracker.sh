#!/usr/bin/env bash
# Cherry-pick tracker for melange ← rescript upstream
# Tracks, triages, and manages upstream commits for potential cherry-picks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MELANGE_DIR="${MELANGE_DIR:-$REPO_ROOT/melange}"
DB_DIR="$SCRIPT_DIR/db"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
# Paths in upstream that are relevant to melange (both old and new layout)
RELEVANT_PATHS=(
  "jscomp/core/" "compiler/core/"
  "jscomp/runtime/" "compiler/runtime/"
  "jscomp/common/" "compiler/common/"
  "jscomp/ext/" "compiler/ext/"
  "jscomp/ml/" "compiler/ml/"
  "jscomp/stdlib/" "compiler/stdlib/"
  "jscomp/others/" "compiler/others/"
)

mkdir -p "$DB_DIR"

# --- helpers ---

json_get() {
  local file="$1" key="$2"
  python3 -c "import json,sys; d=json.load(open('$file')); print(d.get('$key',''))" 2>/dev/null
}

json_set() {
  local file="$1" key="$2" value="$3"
  if [ -f "$file" ]; then
    python3 -c "
import json,sys
with open('$file') as f: d=json.load(f)
d['$key']='$value'
with open('$file','w') as f: json.dump(d,f,indent=2,sort_keys=True)
"
  fi
}

commit_db_file() {
  local hash="$1"
  echo "$DB_DIR/${hash}.json"
}

commit_exists_in_db() {
  local hash="$1"
  [ -f "$(commit_db_file "$hash")" ]
}

create_commit_entry() {
  local hash="$1" subject="$2" author="$3" date="$4" files_changed="$5" auto_category="$6"
  local db_file
  db_file="$(commit_db_file "$hash")"
  python3 - "$db_file" "$hash" "$author" "$date" "$auto_category" <<'PYEOF'
import json, datetime, sys
db_file, hash_val, author, date_val, auto_cat = sys.argv[1:6]
subject = sys.stdin.readline().strip() if False else ""
# Read subject and files from env to avoid argument length limits
import os
entry = {
    "hash": hash_val,
    "subject": os.environ.get("_CP_SUBJECT", ""),
    "author": author,
    "date": date_val,
    "files_changed": os.environ.get("_CP_FILES", "").split(),
    "auto_category": auto_cat,
    "status": "discovered",
    "reason": "",
    "plan": "",
    "pr_url": "",
    "melange_branch": "",
    "discovered_at": datetime.datetime.now().isoformat(),
    "updated_at": datetime.datetime.now().isoformat(),
    "notes": []
}
with open(db_file, 'w') as f:
    json.dump(entry, f, indent=2, sort_keys=True)
PYEOF
}

auto_classify() {
  local subject="$1" files="$2"
  # Check irrelevant patterns first
  if echo "$subject" | grep -qiE '^(bump |set version|prepare for .* release|ci:|GA\(deps\))'; then
    echo "irrelevant"
    return
  fi
  if echo "$files" | grep -qE '(rewatch/|bsb/|rescript-editor-analysis/|analysis/)' && \
     ! echo "$files" | grep -qE '(jscomp/|compiler/(core|runtime|common|ext|ml|stdlib|others))'; then
    echo "irrelevant"
    return
  fi
  if echo "$files" | grep -qE '\.(res|resi)$' && \
     ! echo "$files" | grep -qE '\.ml[i]?$'; then
    echo "irrelevant"
    return
  fi
  # Check relevant patterns
  if echo "$files" | grep -qE '(jscomp|compiler)/(core|runtime|common|ext|ml|stdlib|others)/.*\.ml'; then
    if echo "$subject" | grep -qiE '(fix|crash|bug|regression|incorrect|wrong|broken)'; then
      echo "high_priority"
      return
    fi
    echo "candidate"
    return
  fi
  echo "needs_review"
}

# --- commands ---

cmd_scan() {
  local since="${1:-2024-01-01}"
  echo "Fetching upstream..."
  git -C "$MELANGE_DIR" fetch "$UPSTREAM_REMOTE" --quiet 2>/dev/null || true

  echo "Scanning commits since $since..."
  local new_count=0
  local skip_count=0

  while IFS='|' read -r hash subject author date; do
    hash="$(echo "$hash" | xargs)"
    if commit_exists_in_db "$hash"; then
      skip_count=$((skip_count + 1))
      continue
    fi
    # Get files changed
    local files
    files="$(git -C "$MELANGE_DIR" diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null | tr '\n' ' ')"
    local category
    category="$(auto_classify "$subject" "$files")"

    _CP_SUBJECT="$subject" _CP_FILES="$files" \
      create_commit_entry "$hash" "$subject" "$author" "$date" "$files" "$category"

    # Auto-triage irrelevant commits
    if [ "$category" = "irrelevant" ]; then
      local db_file
      db_file="$(commit_db_file "$hash")"
      json_set "$db_file" "status" "irrelevant"
      json_set "$db_file" "reason" "Auto-classified as irrelevant by scanner"
    fi

    new_count=$((new_count + 1))
    printf "  [%s] %s — %s\n" "$category" "$hash" "$subject"
  done < <(git -C "$MELANGE_DIR" log "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" --no-merges --since="$since" \
    --format="%h|%s|%an|%ai" -- "${RELEVANT_PATHS[@]}" 2>/dev/null)

  echo ""
  echo "Scan complete: $new_count new commits found, $skip_count already tracked."
}

cmd_list() {
  local filter_status="${1:-all}"
  local count=0

  printf "%-12s %-12s %-15s %s\n" "HASH" "STATUS" "CATEGORY" "SUBJECT"
  printf "%-12s %-12s %-15s %s\n" "----" "------" "--------" "-------"

  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local hash subject status category
    hash="$(json_get "$f" hash)"
    subject="$(json_get "$f" subject)"
    status="$(json_get "$f" status)"
    category="$(json_get "$f" auto_category)"

    if [ "$filter_status" != "all" ] && [ "$status" != "$filter_status" ]; then
      continue
    fi

    printf "%-12s %-12s %-15s %s\n" "$hash" "$status" "$category" "${subject:0:60}"
    count=$((count + 1))
  done
  echo ""
  echo "Total: $count commits"
}

cmd_triage() {
  local hash="$1"
  local decision="$2" # relevant, irrelevant, wont_pick
  local reason="${3:-}"
  local db_file
  db_file="$(commit_db_file "$hash")"

  if [ ! -f "$db_file" ]; then
    echo "Error: commit $hash not found in database. Run 'scan' first."
    exit 1
  fi

  case "$decision" in
    relevant)
      json_set "$db_file" "status" "triaged"
      ;;
    irrelevant)
      json_set "$db_file" "status" "irrelevant"
      ;;
    wont_pick)
      json_set "$db_file" "status" "wont_pick"
      ;;
    *)
      echo "Error: decision must be 'relevant', 'irrelevant', or 'wont_pick'"
      exit 1
      ;;
  esac

  json_set "$db_file" "reason" "$reason"
  json_set "$db_file" "updated_at" "$(date -Iseconds)"
  echo "Triaged $hash as $decision"
}

cmd_plan() {
  local hash="$1"
  local plan_text="$2"
  local db_file
  db_file="$(commit_db_file "$hash")"

  if [ ! -f "$db_file" ]; then
    echo "Error: commit $hash not found in database."
    exit 1
  fi

  json_set "$db_file" "status" "planned"
  json_set "$db_file" "plan" "$plan_text"
  json_set "$db_file" "updated_at" "$(date -Iseconds)"
  echo "Plan added for $hash"
}

cmd_advance() {
  local hash="$1"
  local target_status="${2:-}"
  local db_file
  db_file="$(commit_db_file "$hash")"

  if [ ! -f "$db_file" ]; then
    echo "Error: commit $hash not found in database."
    exit 1
  fi

  local current_status
  current_status="$(json_get "$db_file" status)"

  if [ -z "$target_status" ]; then
    case "$current_status" in
      discovered) target_status="triaged" ;;
      triaged) target_status="planned" ;;
      planned) target_status="in_progress" ;;
      in_progress) target_status="testing" ;;
      testing) target_status="merged" ;;
      *)
        echo "Error: cannot auto-advance from status '$current_status'"
        exit 1
        ;;
    esac
  fi

  json_set "$db_file" "status" "$target_status"
  json_set "$db_file" "updated_at" "$(date -Iseconds)"
  echo "Advanced $hash: $current_status → $target_status"
}

cmd_show() {
  local hash="$1"
  local db_file
  db_file="$(commit_db_file "$hash")"

  if [ ! -f "$db_file" ]; then
    echo "Error: commit $hash not found in database."
    exit 1
  fi

  python3 -c "
import json
with open('$db_file') as f: d=json.load(f)
for k,v in sorted(d.items()):
    if isinstance(v, list):
        print(f'{k}: {json.dumps(v)}')
    else:
        print(f'{k}: {v}')
"
}

cmd_status() {
  echo "Cherry-Pick Tracker Status"
  echo "=========================="
  echo ""

  local total=0
  declare -A counts
  for status in discovered triaged planned in_progress testing merged irrelevant wont_pick; do
    counts[$status]=0
  done

  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local status
    status="$(json_get "$f" status)"
    counts[$status]=$(( ${counts[$status]:-0} + 1 ))
    total=$((total + 1))
  done

  printf "  %-15s %s\n" "discovered" "${counts[discovered]}"
  printf "  %-15s %s\n" "triaged" "${counts[triaged]}"
  printf "  %-15s %s\n" "planned" "${counts[planned]}"
  printf "  %-15s %s\n" "in_progress" "${counts[in_progress]}"
  printf "  %-15s %s\n" "testing" "${counts[testing]}"
  printf "  %-15s %s\n" "merged" "${counts[merged]}"
  echo "  ---"
  printf "  %-15s %s\n" "irrelevant" "${counts[irrelevant]}"
  printf "  %-15s %s\n" "wont_pick" "${counts[wont_pick]}"
  echo ""
  echo "Total tracked: $total"

  local actionable=$(( ${counts[discovered]} + ${counts[triaged]} + ${counts[planned]} ))
  echo "Actionable (needs attention): $actionable"
}

cmd_report() {
  echo "=== Actionable Cherry-Pick Candidates ==="
  echo ""

  echo "--- High Priority (bug fixes in shared code) ---"
  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local status category hash subject
    status="$(json_get "$f" status)"
    category="$(json_get "$f" auto_category)"
    if [ "$category" = "high_priority" ] && [ "$status" = "discovered" ]; then
      hash="$(json_get "$f" hash)"
      subject="$(json_get "$f" subject)"
      echo "  $hash $subject"
    fi
  done
  echo ""

  echo "--- Candidates (relevant changes) ---"
  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local status category hash subject
    status="$(json_get "$f" status)"
    category="$(json_get "$f" auto_category)"
    if [ "$category" = "candidate" ] && [ "$status" = "discovered" ]; then
      hash="$(json_get "$f" hash)"
      subject="$(json_get "$f" subject)"
      echo "  $hash $subject"
    fi
  done
  echo ""

  echo "--- Needs Human Review ---"
  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local status category hash subject
    status="$(json_get "$f" status)"
    category="$(json_get "$f" auto_category)"
    if [ "$category" = "needs_review" ] && [ "$status" = "discovered" ]; then
      hash="$(json_get "$f" hash)"
      subject="$(json_get "$f" subject)"
      echo "  $hash $subject"
    fi
  done

  echo ""
  echo "--- In Progress ---"
  for f in "$DB_DIR"/*.json; do
    [ -f "$f" ] || continue
    local status hash subject plan
    status="$(json_get "$f" status)"
    if [ "$status" = "planned" ] || [ "$status" = "in_progress" ] || [ "$status" = "testing" ]; then
      hash="$(json_get "$f" hash)"
      subject="$(json_get "$f" subject)"
      plan="$(json_get "$f" plan)"
      echo "  [$status] $hash $subject"
      [ -n "$plan" ] && echo "    Plan: $plan"
    fi
  done
}

# --- main ---

case "${1:-help}" in
  scan)    cmd_scan "${2:-2024-01-01}" ;;
  list)    cmd_list "${2:-all}" ;;
  triage)  cmd_triage "$2" "$3" "${4:-}" ;;
  plan)    cmd_plan "$2" "$3" ;;
  advance) cmd_advance "$2" "${3:-}" ;;
  show)    cmd_show "$2" ;;
  status)  cmd_status ;;
  report)  cmd_report ;;
  help|*)
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  scan [since-date]              Scan upstream for new commits (default: 2024-01-01)"
    echo "  list [status]                  List commits (filter by status)"
    echo "  triage <hash> <decision> [why] Mark as relevant/irrelevant/wont_pick"
    echo "  plan <hash> 'plan text'        Add adaptation plan for a commit"
    echo "  advance <hash> [status]        Move commit to next stage"
    echo "  show <hash>                    Show full details for a commit"
    echo "  status                         Show summary statistics"
    echo "  report                         Generate actionable report"
    ;;
esac
