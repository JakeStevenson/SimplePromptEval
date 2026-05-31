#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_EVAL="${1:-$ROOT_DIR/prompt-eval.sh}"
CONFIG="$SCRIPT_DIR/mock.conf"

run_case() {
  local name="$1"
  local scenario_path="$2"
  local expected_exit="$3"
  shift 3

  local output exit_code
  set +e
  output="$("$PROMPT_EVAL" --config "$CONFIG" --scenarios "$SCRIPT_DIR/$scenario_path" 2>&1)"
  exit_code="$?"
  set -e

  if [ "$exit_code" -ne "$expected_exit" ]; then
    echo "FAIL $name - expected exit code $expected_exit but got $exit_code" >&2
    echo "$output" >&2
    exit 1
  fi

  local expected
  for expected in "$@"; do
    case "$output" in
      *"$expected"*) ;;
      *)
        echo "FAIL $name - output did not contain: $expected" >&2
        echo "$output" >&2
        exit 1
        ;;
    esac
  done

  echo "PASS $name"
}

run_case \
  "all-pass suite exits zero" \
  "scenarios/pass" \
  0 \
  "PASS test-pass - Contains scoring passes when expected text is present"

run_case \
  "all-fail suite exits one" \
  "scenarios/fail" \
  1 \
  "FAIL test-fail - Contains scoring fails when expected text is missing"

run_case \
  "mixed suite reports both and exits one" \
  "scenarios/mixed" \
  1 \
  "PASS test-mixed-pass - Mixed suite passing scenario" \
  "FAIL test-mixed-fail - Mixed suite failing scenario"

