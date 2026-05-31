param(
    [string]$Config = "prompt-eval.conf",
    [string]$Scenarios = "scenarios",
    [string]$PromptFile = "",
    [switch]$VerboseOutput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Read-KeyValueFile {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config or scenario file not found: $Path"
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key) { $values[$key] = $value }
    }
    return $values
}

function Get-ConfigValue {
    param(
        [hashtable]$Values,
        [string]$Key,
        [string]$Default
    )

    if ($Values.ContainsKey($Key) -and $Values[$Key]) { return $Values[$Key] }
    return $Default
}

function Get-Section {
    param(
        [string]$Path,
        [string]$Name
    )

    $inside = $false
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -eq "[$Name]") {
            $inside = $true
            continue
        }
        if ($line -eq "[/$Name]") {
            break
        }
        if ($inside) {
            $lines.Add($line)
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Expand-PromptTemplate {
    param(
        [string]$Template,
        [string]$InputText,
        [string]$ScenarioId,
        [string]$ScenarioName
    )

    return $Template.
        Replace("{{input}}", $InputText).
        Replace("{{id}}", $ScenarioId).
        Replace("{{name}}", $ScenarioName)
}

function Get-AuthHeader {
    param([hashtable]$Settings)

    switch ($Settings.AuthType) {
        "none" { return @{} }
        "api_key" {
            $token = [Environment]::GetEnvironmentVariable($Settings.ApiKeyEnv)
            if (-not $token) { throw "Missing API key env var: $($Settings.ApiKeyEnv)" }
            return @{ Authorization = "Bearer $token" }
        }
        "bearer" {
            $token = [Environment]::GetEnvironmentVariable($Settings.BearerTokenEnv)
            if (-not $token) { throw "Missing bearer token env var: $($Settings.BearerTokenEnv)" }
            return @{ Authorization = "Bearer $token" }
        }
        "oauth_command" {
            if (-not $Settings.OAuthTokenCommand) { throw "Missing oauth_token_command" }
            $token = Invoke-Expression $Settings.OAuthTokenCommand
            $token = ($token | Out-String).Trim()
            if (-not $token) { throw "OAuth token command returned no token" }
            return @{ Authorization = "Bearer $token" }
        }
        default { throw "Unsupported auth_type: $($Settings.AuthType)" }
    }
}

function Invoke-Llm {
    param(
        [hashtable]$Settings,
        [string]$Model,
        [string]$Prompt
    )

    if ($Settings.Provider -eq "mock") {
        return $Prompt
    }

    $headers = Get-AuthHeader -Settings $Settings
    $headers["Content-Type"] = "application/json"

    $body = @{
        model = $Model
        temperature = 0
        messages = @(
            @{
                role = "user"
                content = $Prompt
            }
        )
    } | ConvertTo-Json -Depth 8

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $Settings.Endpoint `
        -Headers $headers `
        -Body $body `
        -TimeoutSec $Settings.TimeoutSeconds

    return [string]$response.choices[0].message.content
}

function Test-ContainsScore {
    param(
        [string]$Output,
        [string]$Expected
    )

    $missing = 0
    foreach ($line in ($Expected -split '\r?\n')) {
        $needle = $line.Trim()
        if (-not $needle) { continue }
        if ($Output -notlike "*$needle*") {
            $missing++
            if ($VerboseOutput) { [Console]::Error.WriteLine("  missing: $needle") }
        }
    }
    return ($missing -eq 0)
}

function Test-LlmScore {
    param(
        [hashtable]$Settings,
        [string]$Prompt,
        [string]$Output,
        [string]$Expected,
        [int]$Threshold
    )

    if ($Settings.Provider -eq "mock") {
        return Test-ContainsScore -Output $Output -Expected $Expected
    }

    $judgePrompt = @"
Score whether the model output satisfies the expected outcomes.
Return exactly two lines:
SCORE: <integer from 0 to 5>
PASS: <yes or no>

Input prompt:
$Prompt

Model output:
$Output

Expected outcomes:
$Expected

Passing threshold: $Threshold
"@

    $judgeResponse = Invoke-Llm -Settings $Settings -Model $Settings.JudgeModel -Prompt $judgePrompt
    if ($VerboseOutput) { [Console]::Error.WriteLine($judgeResponse) }
    if ($judgeResponse -match '(?m)^SCORE:\s*([0-5])') {
        return ([int]$Matches[1] -ge $Threshold)
    }
    return $false
}

function Invoke-Scenario {
    param(
        [hashtable]$Settings,
        [string]$Path,
        [string]$PromptTemplate
    )

    $scenarioValues = Read-KeyValueFile -Path $Path
    $id = Get-ConfigValue -Values $scenarioValues -Key "id" -Default ([IO.Path]::GetFileNameWithoutExtension($Path))
    $name = Get-ConfigValue -Values $scenarioValues -Key "name" -Default $id
    $scoreMode = Get-ConfigValue -Values $scenarioValues -Key "score_mode" -Default $Settings.ScoreMode
    $threshold = [int](Get-ConfigValue -Values $scenarioValues -Key "pass_threshold" -Default ([string]$Settings.PassThreshold))
    $scenarioPrompt = Get-Section -Path $Path -Name "PROMPT"
    $inputText = Get-Section -Path $Path -Name "INPUT"
    $expected = Get-Section -Path $Path -Name "EXPECTED"
    if ($PromptTemplate) {
        $prompt = Expand-PromptTemplate -Template $PromptTemplate -InputText $inputText -ScenarioId $id -ScenarioName $name
    }
    else {
        $prompt = $scenarioPrompt
    }

    try {
        $output = Invoke-Llm -Settings $Settings -Model $Settings.Model -Prompt $prompt
    }
    catch {
        [Console]::WriteLine("FAIL $id - $name (LLM call failed: $($_.Exception.Message))")
        return $false
    }

    if ($VerboseOutput) {
        [Console]::Error.WriteLine("Output for ${id}:")
        [Console]::Error.WriteLine($output)
    }

    $passed = switch ($scoreMode) {
        "contains" { Test-ContainsScore -Output $output -Expected $expected }
        "llm" { Test-LlmScore -Settings $Settings -Prompt $prompt -Output $output -Expected $expected -Threshold $threshold }
        default { throw "Unknown score_mode: $scoreMode" }
    }

    if ($passed) {
        [Console]::WriteLine("PASS $id - $name")
    }
    else {
        [Console]::WriteLine("FAIL $id - $name")
    }
    return $passed
}

$configValues = Read-KeyValueFile -Path $Config
$settings = @{
    Provider = Get-ConfigValue -Values $configValues -Key "provider" -Default "openai-compatible"
    Endpoint = Get-ConfigValue -Values $configValues -Key "endpoint" -Default "https://api.openai.com/v1/chat/completions"
    Model = Get-ConfigValue -Values $configValues -Key "model" -Default "gpt-4.1-mini"
    ScoreMode = Get-ConfigValue -Values $configValues -Key "score_mode" -Default "llm"
    JudgeModel = Get-ConfigValue -Values $configValues -Key "judge_model" -Default ""
    PassThreshold = [int](Get-ConfigValue -Values $configValues -Key "pass_threshold" -Default "3")
    AuthType = Get-ConfigValue -Values $configValues -Key "auth_type" -Default "api_key"
    ApiKeyEnv = Get-ConfigValue -Values $configValues -Key "api_key_env" -Default "PROMPTEVAL_API_KEY"
    BearerTokenEnv = Get-ConfigValue -Values $configValues -Key "bearer_token_env" -Default "PROMPTEVAL_BEARER_TOKEN"
    OAuthTokenCommand = Get-ConfigValue -Values $configValues -Key "oauth_token_command" -Default ""
    TimeoutSeconds = [int](Get-ConfigValue -Values $configValues -Key "timeout_seconds" -Default "60")
}
if (-not $settings.JudgeModel) { $settings.JudgeModel = $settings.Model }

$promptTemplate = ""
if ($PromptFile) {
    if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
        throw "Prompt file not found: $PromptFile"
    }
    $promptTemplate = Get-Content -LiteralPath $PromptFile -Raw
}

if (Test-Path -LiteralPath $Scenarios -PathType Container) {
    $scenarioFiles = @(Get-ChildItem -LiteralPath $Scenarios -Filter "*.scenario" -File | Sort-Object FullName)
}
elseif (Test-Path -LiteralPath $Scenarios -PathType Leaf) {
    $scenarioFiles = @(Get-Item -LiteralPath $Scenarios)
}
else {
    throw "Scenario path not found: $Scenarios"
}

if (-not $scenarioFiles -or $scenarioFiles.Count -eq 0) {
    throw "No .scenario files found in $Scenarios"
}

$failed = 0
foreach ($scenario in $scenarioFiles) {
    $ok = Invoke-Scenario -Settings $settings -Path $scenario.FullName -PromptTemplate $promptTemplate
    if (-not $ok) { $failed++ }
}

if ($failed -gt 0) {
    exit 1
}
