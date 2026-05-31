param(
    [string]$PromptEval = (Join-Path $PSScriptRoot "..\..\prompt-eval.ps1")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if (-not [Environment]::GetEnvironmentVariable("GROQ_API_KEY")) {
    [Console]::WriteLine("SKIP Groq support comparison - GROQ_API_KEY is not set")
    exit 0
}

$config = Join-Path $PSScriptRoot "groq.conf"
$scenarios = Join-Path $PSScriptRoot "scenarios"
$originalPrompt = Join-Path $PSScriptRoot "prompts\original.prompt"
$improvedPrompt = Join-Path $PSScriptRoot "prompts\improved.prompt"

[Console]::WriteLine("=== Original prompt ===")
& powershell -NoProfile -ExecutionPolicy Bypass -File $PromptEval -Config $config -Scenarios $scenarios -PromptFile $originalPrompt
$originalExitCode = $LASTEXITCODE

[Console]::WriteLine("")
[Console]::WriteLine("=== Improved prompt ===")
& powershell -NoProfile -ExecutionPolicy Bypass -File $PromptEval -Config $config -Scenarios $scenarios -PromptFile $improvedPrompt
$improvedExitCode = $LASTEXITCODE

[Console]::WriteLine("")
[Console]::WriteLine("Original prompt exit code: $originalExitCode")
[Console]::WriteLine("Improved prompt exit code: $improvedExitCode")

if ($improvedExitCode -ne 0) {
    exit $improvedExitCode
}

