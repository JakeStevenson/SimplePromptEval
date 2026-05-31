#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT_EVAL="${1:-$ROOT_DIR/prompt-eval.sh}"

if [ -z "${GROQ_API_KEY:-}" ]; then
  echo "SKIP Groq support comparison - GROQ_API_KEY is not set"
  exit 0
fi

echo "=== Original prompt ==="
set +e
"$PROMPT_EVAL" \
  --config "$SCRIPT_DIR/groq.conf" \
  --scenarios "$SCRIPT_DIR/scenarios" \
  --prompt-file "$SCRIPT_DIR/prompts/original.prompt"
original_exit="$?"
set -e

echo
echo "=== Improved prompt ==="
set +e
"$PROMPT_EVAL" \
  --config "$SCRIPT_DIR/groq.conf" \
  --scenarios "$SCRIPT_DIR/scenarios" \
  --prompt-file "$SCRIPT_DIR/prompts/improved.prompt"
improved_exit="$?"
set -e

echo
echo "Original prompt exit code: $original_exit"
echo "Improved prompt exit code: $improved_exit"

if [ "$improved_exit" -ne 0 ]; then
  exit "$improved_exit"
fi

