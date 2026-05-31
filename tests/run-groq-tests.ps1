param(
    [string]$PromptEval = (Join-Path $PSScriptRoot "..\prompt-eval.ps1")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if (-not [Environment]::GetEnvironmentVariable("GROQ_API_KEY")) {
    [Console]::WriteLine("SKIP Groq integration test - GROQ_API_KEY is not set")
    exit 0
}

$config = Join-Path $PSScriptRoot "groq.conf"
$scenarios = Join-Path $PSScriptRoot "scenarios\groq"

& powershell -NoProfile -ExecutionPolicy Bypass -File $PromptEval -Config $config -Scenarios $scenarios
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

