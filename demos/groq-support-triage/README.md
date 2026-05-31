# Groq Support Triage Demo

This demo evaluates one support-triage prompt against four realistic customer
support tickets. It demonstrates the value of prompt evaluation by comparing an
under-specified original prompt with an improved prompt.

Expected result:

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

