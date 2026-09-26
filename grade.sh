#!/usr/bin/env bash
# Autograder: for each student, replaces the template's contents with the student's
# repo, runs the tests from the scoring file, and writes one CSV row of scores per student.

# ============================ CONFIG ============================
# Relative paths are resolved from the folder this script lives in.
TEMPLATE_DIR="../js-DOM-template-c50"
SUBMISSIONS_DIR="../Submissions/pm-class-js-dom_submissions_2026_09_26_T_02_51_16"
SCORING_FILE="scoring.json"
OUTPUT_CSV="grades.csv"

# AM or PM: picks am-roster.csv or pm-roster.csv from ROSTER_DIR
CLASS_TIME="PM"
ROSTER_DIR="roster"

# Kept from the template for every student; the student's copies of these are ignored
KEEP_IN_TEMPLATE=(
  "node_modules"
  ".tests"
  ".git"
  "README.md"
  ".gitignore"
  "package.json"
  "package-lock.json"
)

# Tests to skip (setup is done once up front)
SKIP_TESTS=("setup")
# ================================================================

set -uo pipefail
shopt -s dotglob nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEMPLATE_DIR="$(cd "$TEMPLATE_DIR" && pwd)" || { echo "ERROR: template dir not found"; exit 1; }
SUBMISSIONS_DIR="$(cd "$SUBMISSIONS_DIR" && pwd)" || { echo "ERROR: submissions dir not found"; exit 1; }
[[ -f "$SCORING_FILE" ]] || { echo "ERROR: scoring file not found: $SCORING_FILE"; exit 1; }
OUTPUT_CSV="$(pwd)/$OUTPUT_CSV"
LOG_DIR="$(pwd)/grading_logs"

# The template gets emptied for every student, so make sure it really is the template
[[ -d "$TEMPLATE_DIR/.tests" && -f "$TEMPLATE_DIR/package.json" ]] \
  || { echo "ERROR: $TEMPLATE_DIR doesn't look like the template (no .tests/ or package.json)"; exit 1; }
case "$SCRIPT_DIR/" in "$TEMPLATE_DIR"/*) echo "ERROR: this script must not live inside the template dir"; exit 1;; esac
case "$SUBMISSIONS_DIR/" in "$TEMPLATE_DIR"/*) echo "ERROR: submissions dir must not be inside the template dir"; exit 1;; esac

case "${CLASS_TIME^^}" in
  AM) ROSTER_FILE="$ROSTER_DIR/am-roster.csv" ;;
  PM) ROSTER_FILE="$ROSTER_DIR/pm-roster.csv" ;;
  *) echo "ERROR: CLASS_TIME must be AM or PM (got \"$CLASS_TIME\")"; exit 1 ;;
esac
[[ -f "$ROSTER_FILE" ]] || { echo "ERROR: roster file not found: $ROSTER_FILE"; exit 1; }

# Repo folders are named "<assignment>-<username>"; the assignment prefix comes
# from the submissions folder name, e.g. "am-class-css-cv_submissions_..." -> "am-class-css-cv-"
SUBMISSIONS_BASENAME="$(basename "$SUBMISSIONS_DIR")"
[[ "$SUBMISSIONS_BASENAME" == *_submissions* ]] || { echo "ERROR: can't find the assignment name in submissions folder name: $SUBMISSIONS_BASENAME"; exit 1; }
REPO_PREFIX="${SUBMISSIONS_BASENAME%%_submissions*}-"

# ---- Parse tests from the scoring file: name<TAB>run<TAB>timeout<TAB>points ----
PARSED_TESTS="$(node -e '
  const cfg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(cfg.tests)) throw new Error("no \"tests\" array");
  for (const t of cfg.tests) {
    const points = t.points ?? 0, timeout = t.timeout ?? 600;
    if (!t.name || !t.run) throw new Error("test missing name/run: " + JSON.stringify(t));
    if (!Number.isInteger(points) || !Number.isInteger(timeout)) throw new Error("points/timeout must be integers in test \"" + t.name + "\"");
    console.log([t.name, t.run, timeout, points].join("\t"));
  }
' "$SCORING_FILE")" || { echo "ERROR: failed to parse $SCORING_FILE"; exit 1; }

TEST_NAMES=(); TEST_CMDS=(); TEST_TIMEOUTS=(); TEST_POINTS=()
while IFS=$'\t' read -r name run tmo pts; do
  [[ -n "$name" ]] || continue
  skip=0
  for s in "${SKIP_TESTS[@]}"; do [[ "$name" == "$s" ]] && skip=1; done
  (( skip )) && continue
  TEST_NAMES+=("$name"); TEST_CMDS+=("$run"); TEST_TIMEOUTS+=("$tmo"); TEST_POINTS+=("$pts")
done <<< "$PARSED_TESTS"
(( ${#TEST_NAMES[@]} > 0 )) || { echo "ERROR: no tests to run in $SCORING_FILE"; exit 1; }

# Every file referenced in a test command must exist in the template
bad_paths=()
for i in "${!TEST_CMDS[@]}"; do
  read -ra args <<< "${TEST_CMDS[$i]}"
  for arg in "${args[@]}"; do
    [[ "$arg" == */* || "$arg" == *.js ]] || continue
    [[ -e "$TEMPLATE_DIR/$arg" ]] || bad_paths+=("  - test \"${TEST_NAMES[$i]}\": $arg")
  done
done
if (( ${#bad_paths[@]} > 0 )); then
  echo "ERROR: these files referenced in $SCORING_FILE do not exist in $TEMPLATE_DIR:"
  printf '%s\n' "${bad_paths[@]}"
  echo "Fix the paths in $SCORING_FILE and re-run."
  exit 1
fi

# ---- Load roster: lowercase username -> "First Last" (teachers excluded) ----
PARSED_ROSTER="$(node -e '
  const text = require("fs").readFileSync(process.argv[1], "utf8").replace(/^﻿/, "");
  // minimal CSV parser (handles quoted fields)
  const rows = []; let row = [], field = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === "\"") { if (text[i + 1] === "\"") { field += c; i++; } else q = false; } else field += c; }
    else if (c === "\"") q = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(field); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const header = rows.shift().map(h => h.trim());
  const col = n => { const i = header.indexOf(n); if (i < 0) throw new Error("roster has no \"" + n + "\" column"); return i; };
  const [u, f, l, r] = ["username", "first_name", "last_name", "role"].map(col);
  for (const x of rows) {
    if (!x[u] || (x[r] || "").trim().toLowerCase() === "teacher") continue;
    console.log([x[u].trim(), [x[f], x[l]].map(s => (s || "").trim()).filter(Boolean).join(" ")].join("\t"));
  }
' "$ROSTER_FILE")" || { echo "ERROR: failed to parse $ROSTER_FILE"; exit 1; }

declare -A ROSTER_NAME=() ROSTER_DISPLAY=()
ROSTER_ORDER=()
while IFS=$'\t' read -r uname fullname; do
  [[ -n "$uname" ]] || continue
  key="${uname,,}"
  [[ -v ROSTER_NAME[$key] ]] && continue
  ROSTER_NAME[$key]="$fullname"; ROSTER_DISPLAY[$key]="$uname"; ROSTER_ORDER+=("$key")
done <<< "$PARSED_ROSTER"

REPOS=("$SUBMISSIONS_DIR/$REPO_PREFIX"*/)
(( ${#REPOS[@]} > 0 )) || { echo "ERROR: no student repos matching $REPO_PREFIX* in $SUBMISSIONS_DIR"; exit 1; }

# Refuse to start if the template has leftovers from an earlier (killed) run,
# otherwise they would be backed up as the "original" template files
if git -C "$TEMPLATE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  excludes=(); for k in "${KEEP_IN_TEMPLATE[@]}"; do excludes+=(":(exclude)$k"); done
  dirty="$(git -C "$TEMPLATE_DIR" status --porcelain -- . "${excludes[@]}")"
  if [[ -n "$dirty" ]]; then
    echo "ERROR: the template has changes compared to git (leftover from an earlier run?):"
    echo "$dirty" | sed 's/^/  /'
    echo "Restore it with: git -C \"$TEMPLATE_DIR\" checkout -- . && git -C \"$TEMPLATE_DIR\" clean -fd"
    echo "(check what clean would delete first with: git -C \"$TEMPLATE_DIR\" clean -nd)"
    exit 1
  fi
fi

MAX_SCORE=0
for p in "${TEST_POINTS[@]}"; do MAX_SCORE=$((MAX_SCORE + p)); done

echo "Class time: ${CLASS_TIME^^} (roster: $ROSTER_FILE, ${#ROSTER_ORDER[@]} students)"
echo "Submissions: ${#REPOS[@]}"
echo "Tests:"
for i in "${!TEST_NAMES[@]}"; do echo "  - ${TEST_NAMES[$i]} (${TEST_POINTS[$i]} pts): ${TEST_CMDS[$i]}"; done
echo "Max score: $MAX_SCORE"
echo

is_kept() {
  local k
  for k in "${KEEP_IN_TEMPLATE[@]}"; do [[ "$1" == "$k" ]] && return 0; done
  return 1
}

# Delete everything in the template except KEEP_IN_TEMPLATE
clear_template() {
  local entry
  for entry in "$TEMPLATE_DIR"/*; do
    is_kept "$(basename "$entry")" || rm -rf -- "$entry"
  done
}

# Copy everything from dir $1 into dir $2 except KEEP_IN_TEMPLATE
copy_entries() {
  local entry
  for entry in "$1"/*; do
    is_kept "$(basename "$entry")" || cp -R -- "$entry" "$2/" || return 1
  done
}

# ---- Back up template contents; restore them on exit no matter what ----
BACKUP_DIR="$(mktemp -d)"
copy_entries "$TEMPLATE_DIR" "$BACKUP_DIR" || { echo "ERROR: failed to back up the template"; rm -rf "$BACKUP_DIR"; exit 1; }

restore_template() {
  clear_template
  copy_entries "$BACKUP_DIR" "$TEMPLATE_DIR"
}
trap 'restore_template; rm -rf "$BACKUP_DIR"' EXIT
# On Ctrl-C/kill, also stop the running test (timeout runs it in its own process group)
TEST_PID=""
trap '[[ -n "$TEST_PID" ]] && kill -TERM -- -"$TEST_PID" 2>/dev/null; exit 130' INT TERM

# ---- Install node packages once ----
echo "Installing node packages in $TEMPLATE_DIR ..."
(cd "$TEMPLATE_DIR" && npm install --no-audit --no-fund) || { echo "npm install failed"; exit 1; }
echo

mkdir -p "$LOG_DIR"

# ---- CSV ----
csv_escape() { local s="${1//\"/\"\"}"; printf '"%s"' "$s"; }
{
  printf 'username,name'
  for n in "${TEST_NAMES[@]}"; do printf ',%s' "$(csv_escape "$n")"; done
  printf ',total,max_score,notes\n'
} > "$OUTPUT_CSV"

# write_row username name total notes score...
write_row() {
  local username="$1" name="$2" total="$3" notes="$4"; shift 4
  {
    printf '%s,%s' "$(csv_escape "$username")" "$(csv_escape "$name")"
    for s in "$@"; do printf ',%s' "$s"; done
    printf ',%s,%s,%s\n' "$total" "$MAX_SCORE" "$(csv_escape "$notes")"
  } >> "$OUTPUT_CSV"
}

# ---- Grade each submission ----
declare -A SUBMITTED=()
for repo in "${REPOS[@]}"; do
  repo="${repo%/}"
  repo_name="$(basename "$repo")"
  username="${repo_name#"$REPO_PREFIX"}"
  key="${username,,}"
  SUBMITTED[$key]=1
  notes=""
  if [[ -v ROSTER_NAME[$key] ]]; then
    name="${ROSTER_NAME[$key]}"
  else
    name=""; notes="not in roster"
  fi
  echo "=== Grading $username${name:+ ($name)} ==="

  clear_template
  copy_entries "$repo" "$TEMPLATE_DIR"

  scores=(); total=0
  student_log="$LOG_DIR/$username.log"
  : > "$student_log"
  for i in "${!TEST_NAMES[@]}"; do
    echo "----- ${TEST_NAMES[$i]}: ${TEST_CMDS[$i]} -----" >> "$student_log"
    (cd "$TEMPLATE_DIR" && exec timeout -k 10 "${TEST_TIMEOUTS[$i]}" bash -c "${TEST_CMDS[$i]}") >> "$student_log" 2>&1 &
    TEST_PID=$!
    if wait "$TEST_PID"; then
      pts="${TEST_POINTS[$i]}"; result="PASS"
    else
      pts=0; result="FAIL"
    fi
    TEST_PID=""
    scores+=("$pts"); total=$((total + pts))
    printf '  %-20s %s (%s/%s)\n' "${TEST_NAMES[$i]}" "$result" "$pts" "${TEST_POINTS[$i]}"
  done

  echo "  Total: $total/$MAX_SCORE"
  write_row "$username" "$name" "$total" "$notes" "${scores[@]}"
done

# ---- Roster students without a submission get 0 ----
zeros=(); for _ in "${TEST_NAMES[@]}"; do zeros+=(0); done
for key in "${ROSTER_ORDER[@]}"; do
  [[ -v SUBMITTED[$key] ]] && continue
  echo "=== ${ROSTER_DISPLAY[$key]} (${ROSTER_NAME[$key]}): no submission -> 0 ==="
  write_row "${ROSTER_DISPLAY[$key]}" "${ROSTER_NAME[$key]}" 0 "no submission" "${zeros[@]}"
done

echo
echo "Done. Grades written to $OUTPUT_CSV (per-student test logs in $LOG_DIR)"
