param(
    [string]$PromptEval = (Join-Path $PSScriptRoot "..\prompt-eval.ps1")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $PSScriptRoot "mock.conf"

function Invoke-Case {
    param(
        [string]$Name,
        [string]$ScenarioPath,
        [int]$ExpectedExitCode,
        [string[]]$ExpectedOutput
    )

    $fullScenarioPath = Join-Path $PSScriptRoot $ScenarioPath
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $PromptEval -Config $config -Scenarios $fullScenarioPath 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -ne $ExpectedExitCode) {
        throw "$Name expected exit code $ExpectedExitCode but got $exitCode. Output: $text"
    }

    foreach ($expected in $ExpectedOutput) {
        if ($text -notlike "*$expected*") {
            throw "$Name output did not contain '$expected'. Output: $text"
        }
    }

    [Console]::WriteLine("PASS $Name")
}

Invoke-Case `
    -Name "all-pass suite exits zero" `
    -ScenarioPath "scenarios\pass" `
    -ExpectedExitCode 0 `
    -ExpectedOutput @("PASS test-pass - Contains scoring passes when expected text is present")

Invoke-Case `
    -Name "all-fail suite exits one" `
    -ScenarioPath "scenarios\fail" `
    -ExpectedExitCode 1 `
    -ExpectedOutput @("FAIL test-fail - Contains scoring fails when expected text is missing")

Invoke-Case `
    -Name "mixed suite reports both and exits one" `
    -ScenarioPath "scenarios\mixed" `
    -ExpectedExitCode 1 `
    -ExpectedOutput @(
        "PASS test-mixed-pass - Mixed suite passing scenario",
        "FAIL test-mixed-fail - Mixed suite failing scenario"
    )

