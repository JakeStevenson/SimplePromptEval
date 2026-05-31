# PromptEval

PromptEval is a small, portable prompt evaluation runner with matching Bash and
PowerShell implementations. It runs scenario files, calls an LLM endpoint, and
prints a pass/fail result for each scenario.

The tool intentionally avoids heavy dependencies:

- Bash version: `bash` and `curl`
- PowerShell version: PowerShell 5.1+ or PowerShell 7+

## Try The Real Demo

The Groq support triage demo compares an original under-specified prompt with an
improved prompt against the same customer-support scenarios.

PowerShell:

```powershell
Copy-Item .env.ps1.example .env.ps1
# Edit .env.ps1 and set GROQ_API_KEY
. .\.env.ps1
.\demos\groq-support-triage\run-comparison.ps1
```

Bash:

```bash
cp .env.example .env
# Edit .env and set GROQ_API_KEY
source ./.env
./demos/groq-support-triage/run-comparison.sh
```

Expected shape:

```text
=== Original prompt ===
PASS groq-support-billing-refund - Billing refund escalation
FAIL groq-support-account-access - Account access recovery
FAIL groq-support-feature-request - Feature request logging
FAIL groq-support-technical-issue - Technical issue workflow block

=== Improved prompt ===
PASS groq-support-billing-refund - Billing refund escalation
PASS groq-support-account-access - Account access recovery
PASS groq-support-feature-request - Feature request logging
PASS groq-support-technical-issue - Technical issue workflow block
```

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
oauth_token_command=az account get-access-token --scope https://cognitiveservices.azure.com/.default --query accessToken -o tsv
```

Only use `oauth_token_command` with config files you trust. It runs the
configured command locally.

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

### Reusable Prompt Files

For realistic prompt evaluation, keep the prompt under test in its own file and
put test data in each scenario's `[INPUT]` section:

```text
[INPUT]
Customer ticket or task input goes here.
[/INPUT]

[EXPECTED]
Category: Billing
Severity: High
[/EXPECTED]
```

Prompt files can use these placeholders:

| Placeholder | Description |
| --- | --- |
| `{{input}}` | The scenario's `[INPUT]` section. |
| `{{id}}` | The scenario id. |
| `{{name}}` | The scenario name. |

Bash:

```bash
./prompt-eval.sh --config demos/groq-support-triage/groq.conf --scenarios demos/groq-support-triage/scenarios --prompt-file demos/groq-support-triage/prompts/improved.prompt
```

PowerShell:

```powershell
.\prompt-eval.ps1 -Config demos\groq-support-triage\groq.conf -Scenarios demos\groq-support-triage\scenarios -PromptFile demos\groq-support-triage\prompts\improved.prompt
```

When `--prompt-file` / `-PromptFile` is provided, the rendered prompt file is
used instead of any `[PROMPT]` section in the scenario file.

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

The offline test suites cover:

- A fully passing scenario directory, which exits `0`.
- A fully failing scenario directory, which exits `1`.
- A mixed directory, which reports both `PASS` and `FAIL` and exits `1`.
- Prompt-file rendering with scenario `[INPUT]`.

### Groq Integration Test

Groq exposes an OpenAI-compatible chat completions endpoint, so it can use the
same `openai-compatible` provider:

```text
endpoint=https://api.groq.com/openai/v1/chat/completions
model=llama-3.1-8b-instant
api_key_env=GROQ_API_KEY
```

Set your key in the environment, then run either integration test:

```powershell
$env:GROQ_API_KEY = "..."
.\tests\run-groq-tests.ps1
```

```bash
export GROQ_API_KEY="..."
./tests/run-groq-tests.sh
```

If `GROQ_API_KEY` is not set, the integration test prints `SKIP` and exits `0`.

## Security

Do not commit real API keys or bearer tokens. Local `.env` files are ignored by
Git; use the checked-in example files as templates. See [SECURITY.md](SECURITY.md)
for notes on secrets, OAuth commands, and the dependency-free Bash JSON parser.
