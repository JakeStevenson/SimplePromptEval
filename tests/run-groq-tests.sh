#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_EVAL="${1:-$ROOT_DIR/prompt-eval.sh}"

if [ -z "${GROQ_API_KEY:-}" ]; then
  echo "SKIP Groq integration test - GROQ_API_KEY is not set"
  exit 0
fi

"$PROMPT_EVAL" \
  --config "$SCRIPT_DIR/groq.conf" \
  --scenarios "$SCRIPT_DIR/scenarios/groq"

