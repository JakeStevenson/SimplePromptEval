# PromptEval

PromptEval is a small, portable prompt evaluation runner with matching Bash and
PowerShell implementations. It runs scenario files, calls an LLM endpoint, and
prints a pass/fail result for each scenario.

The tool intentionally avoids heavy dependencies:

- Bash version: `bash` and `curl`
- PowerShell version: PowerShell 5.1+ or PowerShell 7+

## Quick Start

Bash:

```bash
./prompt-eval.sh --config examples/prompt-eval.conf --scenarios examples/scenarios
```

PowerShell:

```powershell
.\prompt-eval.ps1 -Config examples\prompt-eval.conf -Scenarios examples\scenarios
```

The example config uses `provider=mock`, so it runs without network access or
credentials. Switch to `provider=openai-compatible` when you are ready to call a
real LLM endpoint.

## Configuration

Create a config file using `key=value` lines:

```text
provider=openai-compatible
endpoint=https://api.openai.com/v1/chat/completions
model=gpt-4.1-mini
auth_type=api_key
api_key_env=PROMPTEVAL_API_KEY
score_mode=llm
judge_model=gpt-4.1-mini
pass_threshold=3
timeout_seconds=60
```

Supported settings:

| Key | Default | Description |
| --- | --- | --- |
| `provider` | `openai-compatible` | Use `openai-compatible` for real HTTP calls or `mock` for local dry runs. |
| `endpoint` | `https://api.openai.com/v1/chat/completions` | Chat-completions-compatible endpoint. |
| `model` | `gpt-4.1-mini` | Model used to answer each scenario prompt. |
| `score_mode` | `llm` | `llm` for judge scoring, or `contains` for simple substring checks. |
| `judge_model` | value of `model` | Model used for LLM judging. |
| `pass_threshold` | `3` | Minimum judge score needed to pass. Scenario files can override this. |
| `timeout_seconds` | `60` | HTTP timeout. |
| `auth_type` | `api_key` | `api_key`, `bearer`, `oauth_command`, or `none`. |
| `api_key_env` | `PROMPTEVAL_API_KEY` | Environment variable containing an API key. |
| `bearer_token_env` | `PROMPTEVAL_BEARER_TOKEN` | Environment variable containing a bearer token. |
| `oauth_token_command` | empty | Command that prints an OAuth access token. |

### Authentication

For API-key endpoints:

```bash
export PROMPTEVAL_API_KEY="..."
```

```powershell
$env:PROMPTEVAL_API_KEY = "..."
```

For OAuth, either provide an existing token:

```text
auth_type=bearer
bearer_token_env=PROMPTEVAL_OAUTH_TOKEN
```

Or provide a command that prints a token:

```text
auth_type=oauth_command
oauth_token_command=az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
```

## Scenario Files

Scenario files use the `.scenario` extension and a simple section format:

```text
id=concise-summary
name=Concise summary
score_mode=llm
pass_threshold=3

[PROMPT]
Summarize the release notes in three bullets.
[/PROMPT]

[EXPECTED]
- Uses exactly three bullets.
- Mentions the security fix.
- Does not invent dates.
[/EXPECTED]
```

For `score_mode=contains`, each non-empty line in `[EXPECTED]` must appear in
the model output.

## Output

Each run prints one line per scenario:

```text
PASS concise-summary - Concise summary
FAIL exact-phrase - Exact phrase
```

The process exits with code `0` when all scenarios pass, and `1` when one or
more fail.

## Tests

The test fixtures use `provider=mock`, which echoes the prompt instead of
calling a real model. This makes pass/fail behavior deterministic.

PowerShell:

```powershell
.\tests\run-tests.ps1
```

Bash:

```bash
./tests/run-tests.sh
```

The test suites cover:

- A fully passing scenario directory, which exits `0`.
- A fully failing scenario directory, which exits `1`.
- A mixed directory, which reports both `PASS` and `FAIL` and exits `1`.
