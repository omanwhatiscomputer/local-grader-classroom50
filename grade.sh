#!/usr/bin/env bash
# Autograder: swaps each student's files into the template, runs the tests
# from the scoring file, and writes one CSV row of scores per student.

# ============================ CONFIG ============================
# Relative paths are resolved from the folder this script lives in.
TEMPLATE_DIR="css-cv-template"
SUBMISSIONS_DIR="Submissions/am-class-css-cv_submissions_2026_09_23_T_22_55_16"
SCORING_FILE="scoring.json"
OUTPUT_CSV="grades.csv"

# Paths relative to TEMPLATE_DIR (and to each student's repo)
TEMPLATE_FILES_TO_REPLACE=(
  "index.html"
  "contact.html"
  "css/style.css"
)

# Tests to skip (setup is done once up front)
SKIP_TESTS=("setup")
# ================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEMPLATE_DIR="$(cd "$TEMPLATE_DIR" && pwd)" || { echo "Template dir not found"; exit 1; }
SUBMISSIONS_DIR="$(cd "$SUBMISSIONS_DIR" && pwd)" || { echo "Submissions dir not found"; exit 1; }
[[ -f "$SCORING_FILE" ]] || { echo "Scoring file not found: $SCORING_FILE"; exit 1; }
OUTPUT_CSV="$(pwd)/$OUTPUT_CSV"
LOG_DIR="$(pwd)/grading_logs"
mkdir -p "$LOG_DIR"

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

# Every file to replace must exist in the template
for f in "${TEMPLATE_FILES_TO_REPLACE[@]}"; do
  [[ -f "$TEMPLATE_DIR/$f" ]] || { echo "ERROR: TEMPLATE_FILES_TO_REPLACE entry not found in template: $f"; exit 1; }
done

# Refuse to start if the template still has a student's files in it (e.g. from a killed run),
# otherwise they would be backed up as the "original" template files
if git -C "$TEMPLATE_DIR" rev-parse --git-dir >/dev/null 2>&1 \
   && ! git -C "$TEMPLATE_DIR" diff --quiet HEAD -- "${TEMPLATE_FILES_TO_REPLACE[@]}"; then
  echo "ERROR: these template files differ from git HEAD (leftover from an earlier run?):"
  git -C "$TEMPLATE_DIR" diff --name-only HEAD -- "${TEMPLATE_FILES_TO_REPLACE[@]}" | sed 's/^/  - /'
  echo "Restore them with: git -C \"$TEMPLATE_DIR\" checkout -- ${TEMPLATE_FILES_TO_REPLACE[*]}"
  exit 1
fi

MAX_SCORE=0
for p in "${TEST_POINTS[@]}"; do MAX_SCORE=$((MAX_SCORE + p)); done

echo "Tests:"
for i in "${!TEST_NAMES[@]}"; do echo "  - ${TEST_NAMES[$i]} (${TEST_POINTS[$i]} pts): ${TEST_CMDS[$i]}"; done
echo "Max score: $MAX_SCORE"
echo

# ---- Back up template files; restore them on exit no matter what ----
BACKUP_DIR="$(mktemp -d)"
for f in "${TEMPLATE_FILES_TO_REPLACE[@]}"; do
  if [[ -e "$TEMPLATE_DIR/$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$TEMPLATE_DIR/$f" "$BACKUP_DIR/$f"
  fi
done

restore_template() {
  for f in "${TEMPLATE_FILES_TO_REPLACE[@]}"; do
    if [[ -e "$BACKUP_DIR/$f" ]]; then
      cp "$BACKUP_DIR/$f" "$TEMPLATE_DIR/$f"
    else
      rm -f "$TEMPLATE_DIR/$f"
    fi
  done
}
trap 'restore_template; rm -rf "$BACKUP_DIR"' EXIT
# On Ctrl-C/kill, also stop the running test (timeout runs it in its own process group)
TEST_PID=""
trap '[[ -n "$TEST_PID" ]] && kill -TERM -- -"$TEST_PID" 2>/dev/null; exit 130' INT TERM

# ---- Install node packages once ----
echo "Installing node packages in $TEMPLATE_DIR ..."
(cd "$TEMPLATE_DIR" && npm install --no-audit --no-fund) || { echo "npm install failed"; exit 1; }
echo

# ---- CSV header ----
csv_escape() { local s="${1//\"/\"\"}"; printf '"%s"' "$s"; }
{
  printf 'username'
  for n in "${TEST_NAMES[@]}"; do printf ',%s' "$(csv_escape "$n")"; done
  printf ',total,max_score,notes\n'
} > "$OUTPUT_CSV"

# ---- Grade each student ----
for repo in "$SUBMISSIONS_DIR/$REPO_PREFIX"*/; do
  [[ -d "$repo" ]] || { echo "ERROR: no student repos matching $REPO_PREFIX* in $SUBMISSIONS_DIR"; exit 1; }
  repo="${repo%/}"
  repo_name="$(basename "$repo")"
  username="${repo_name#"$REPO_PREFIX"}"
  echo "=== Grading $username ==="

  restore_template

  # Check for missing files -> zero
  missing=()
  for f in "${TEMPLATE_FILES_TO_REPLACE[@]}"; do
    [[ -f "$repo/$f" ]] || missing+=("$f")
  done

  scores=(); total=0; notes=""
  if (( ${#missing[@]} > 0 )); then
    notes="missing files: ${missing[*]}"
    echo "  $notes -> score 0"
    for _ in "${TEST_NAMES[@]}"; do scores+=(0); done
  else
    for f in "${TEMPLATE_FILES_TO_REPLACE[@]}"; do
      mkdir -p "$TEMPLATE_DIR/$(dirname "$f")"
      cp "$repo/$f" "$TEMPLATE_DIR/$f"
    done

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
  fi

  echo "  Total: $total/$MAX_SCORE"
  {
    printf '%s' "$(csv_escape "$username")"
    for s in "${scores[@]}"; do printf ',%s' "$s"; done
    printf ',%s,%s,%s\n' "$total" "$MAX_SCORE" "$(csv_escape "$notes")"
  } >> "$OUTPUT_CSV"
done

echo
echo "Done. Grades written to $OUTPUT_CSV (per-student test logs in $LOG_DIR)"
