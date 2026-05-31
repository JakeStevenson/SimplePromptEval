#!/usr/bin/env bash
set -u

CONFIG_FILE="prompt-eval.conf"
SCENARIO_PATH="scenarios"
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage: prompt-eval.sh [--config FILE] [--scenarios PATH] [--verbose]

Runs .scenario prompt evaluation files and prints pass/fail results.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --scenarios) SCENARIO_PATH="${2:-}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

read_value() {
  local file="$1"
  local key="$2"
  local value
  value="$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$file" 2>/dev/null | tail -n 1 | sed 's/^[^=]*=//')"
  trim "$value"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

extract_section() {
  local file="$1"
  local name="$2"
  awk -v start="[$name]" -v stop="[/$name]" '
    $0 == start { in_section=1; next }
    $0 == stop { in_section=0; exit }
    in_section { print }
  ' "$file"
}

load_config() {
  PROVIDER="$(read_value "$CONFIG_FILE" provider)"
  ENDPOINT="$(read_value "$CONFIG_FILE" endpoint)"
  MODEL="$(read_value "$CONFIG_FILE" model)"
  SCORE_MODE="$(read_value "$CONFIG_FILE" score_mode)"
  JUDGE_MODEL="$(read_value "$CONFIG_FILE" judge_model)"
  PASS_THRESHOLD="$(read_value "$CONFIG_FILE" pass_threshold)"
  AUTH_TYPE="$(read_value "$CONFIG_FILE" auth_type)"
  API_KEY_ENV="$(read_value "$CONFIG_FILE" api_key_env)"
  BEARER_TOKEN_ENV="$(read_value "$CONFIG_FILE" bearer_token_env)"
  OAUTH_TOKEN_COMMAND="$(read_value "$CONFIG_FILE" oauth_token_command)"
  TIMEOUT_SECONDS="$(read_value "$CONFIG_FILE" timeout_seconds)"

  PROVIDER="${PROVIDER:-openai-compatible}"
  ENDPOINT="${ENDPOINT:-https://api.openai.com/v1/chat/completions}"
  MODEL="${MODEL:-gpt-4.1-mini}"
  SCORE_MODE="${SCORE_MODE:-llm}"
  JUDGE_MODEL="${JUDGE_MODEL:-$MODEL}"
  PASS_THRESHOLD="${PASS_THRESHOLD:-3}"
  AUTH_TYPE="${AUTH_TYPE:-api_key}"
  API_KEY_ENV="${API_KEY_ENV:-PROMPTEVAL_API_KEY}"
  BEARER_TOKEN_ENV="${BEARER_TOKEN_ENV:-PROMPTEVAL_BEARER_TOKEN}"
  TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
}

auth_header() {
  case "$AUTH_TYPE" in
    none) return 0 ;;
    api_key)
      local token="${!API_KEY_ENV:-}"
      [ -n "$token" ] || { echo "Missing API key env var: $API_KEY_ENV" >&2; return 1; }
      printf 'Authorization: Bearer %s' "$token"
      ;;
    bearer)
      local token="${!BEARER_TOKEN_ENV:-}"
      [ -n "$token" ] || { echo "Missing bearer token env var: $BEARER_TOKEN_ENV" >&2; return 1; }
      printf 'Authorization: Bearer %s' "$token"
      ;;
    oauth_command)
      [ -n "$OAUTH_TOKEN_COMMAND" ] || { echo "Missing oauth_token_command" >&2; return 1; }
      local token
      token="$(sh -c "$OAUTH_TOKEN_COMMAND")"
      token="$(trim "$token")"
      [ -n "$token" ] || { echo "OAuth token command returned no token" >&2; return 1; }
      printf 'Authorization: Bearer %s' "$token"
      ;;
    *) echo "Unsupported auth_type: $AUTH_TYPE" >&2; return 1 ;;
  esac
}

call_llm() {
  local model="$1"
  local user_prompt="$2"

  if [ "$PROVIDER" = "mock" ]; then
    printf '%s\n' "$user_prompt"
    return 0
  fi

  local escaped_prompt escaped_model payload header
  escaped_prompt="$(json_escape "$user_prompt")"
  escaped_model="$(json_escape "$model")"
  payload="{\"model\":\"$escaped_model\",\"messages\":[{\"role\":\"user\",\"content\":\"$escaped_prompt\"}],\"temperature\":0}"

  header="$(auth_header)" || return 1
  if [ -n "$header" ]; then
    curl -fsS --max-time "$TIMEOUT_SECONDS" \
      -H "Content-Type: application/json" \
      -H "$header" \
      -d "$payload" \
      "$ENDPOINT" |
      sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      sed 's/\\n/\
/g; s/\\"/"/g; s/\\\\/\\/g'
  else
    curl -fsS --max-time "$TIMEOUT_SECONDS" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$ENDPOINT" |
      sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      sed 's/\\n/\
/g; s/\\"/"/g; s/\\\\/\\/g'
  fi
}

score_contains() {
  local output="$1"
  local expected="$2"
  local missing=0
  while IFS= read -r line; do
    line="$(trim "$line")"
    [ -z "$line" ] && continue
    case "$output" in
      *"$line"*) ;;
      *) missing=$((missing + 1)); [ "$VERBOSE" -eq 1 ] && echo "  missing: $line" >&2 ;;
    esac
  done <<EOF_EXPECTED
$expected
EOF_EXPECTED
  [ "$missing" -eq 0 ]
}

score_with_llm() {
  local prompt="$1"
  local output="$2"
  local expected="$3"
  local threshold="$4"
  local judge_prompt judge_response score

  if [ "$PROVIDER" = "mock" ]; then
    score_contains "$output" "$expected"
    return $?
  fi

  judge_prompt="Score whether the model output satisfies the expected outcomes.
Return exactly two lines:
SCORE: <integer from 0 to 5>
PASS: <yes or no>

Input prompt:
$prompt

Model output:
$output

Expected outcomes:
$expected

Passing threshold: $threshold"

  judge_response="$(call_llm "$JUDGE_MODEL" "$judge_prompt")" || return 1
  [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$judge_response" >&2
  score="$(printf '%s\n' "$judge_response" | sed -n 's/^SCORE:[[:space:]]*\([0-5]\).*/\1/p' | head -n 1)"
  [ -n "$score" ] && [ "$score" -ge "$threshold" ]
}

run_scenario() {
  local file="$1"
  local id name scenario_score_mode threshold prompt expected output

  id="$(read_value "$file" id)"
  name="$(read_value "$file" name)"
  scenario_score_mode="$(read_value "$file" score_mode)"
  threshold="$(read_value "$file" pass_threshold)"
  prompt="$(extract_section "$file" PROMPT)"
  expected="$(extract_section "$file" EXPECTED)"

  id="${id:-$(basename "$file" .scenario)}"
  name="${name:-$id}"
  scenario_score_mode="${scenario_score_mode:-$SCORE_MODE}"
  threshold="${threshold:-$PASS_THRESHOLD}"

  output="$(call_llm "$MODEL" "$prompt")" || {
    echo "FAIL $id - $name (LLM call failed)"
    return 1
  }

  if [ "$VERBOSE" -eq 1 ]; then
    echo "Output for $id:" >&2
    printf '%s\n' "$output" >&2
  fi

  case "$scenario_score_mode" in
    contains) score_contains "$output" "$expected" ;;
    llm) score_with_llm "$prompt" "$output" "$expected" "$threshold" ;;
    *) echo "FAIL $id - $name (unknown score_mode: $scenario_score_mode)"; return 1 ;;
  esac

  if [ "$?" -eq 0 ]; then
    echo "PASS $id - $name"
    return 0
  fi

  echo "FAIL $id - $name"
  return 1
}

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 2
fi

load_config

if [ -d "$SCENARIO_PATH" ]; then
  SCENARIOS=()
  while IFS= read -r scenario_file; do
    SCENARIOS+=("$scenario_file")
  done <<EOF_SCENARIOS
$(find "$SCENARIO_PATH" -type f -name '*.scenario' | sort)
EOF_SCENARIOS
elif [ -f "$SCENARIO_PATH" ]; then
  SCENARIOS=("$SCENARIO_PATH")
else
  echo "Scenario path not found: $SCENARIO_PATH" >&2
  exit 2
fi

if [ "${#SCENARIOS[@]}" -eq 0 ]; then
  echo "No .scenario files found in $SCENARIO_PATH" >&2
  exit 2
fi

FAILED=0
for scenario in "${SCENARIOS[@]}"; do
  run_scenario "$scenario" || FAILED=$((FAILED + 1))
done

[ "$FAILED" -eq 0 ] || exit 1
