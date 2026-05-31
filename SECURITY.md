# Security Notes

PromptEval is a local command-line tool. Treat config files, scenario files, and
prompt files as trusted local inputs.

## Secrets

Do not commit real API keys, bearer tokens, or OAuth refresh tokens.

This repository ignores local environment files:

- `.env`
- `.env.ps1`
- `.env.*`

Use the example files as templates:

- `.env.example`
- `.env.ps1.example`

If a real key is accidentally pasted into chat, logs, commits, screenshots, or
shared files, rotate it before sharing the project.

## OAuth Commands

`auth_type=oauth_command` runs the configured command locally to obtain a bearer
token. Only use this option with config files you trust.

Examples:

```text
auth_type=oauth_command
oauth_token_command=az account get-access-token --scope https://cognitiveservices.azure.com/.default --query accessToken -o tsv
```

## Bash JSON Parsing

The Bash runner intentionally avoids dependencies such as `jq`. It parses the
common OpenAI-compatible chat completion response shape with shell tools. For
complex responses or production automation, prefer the PowerShell runner or add
a real JSON parser to the Bash path.

