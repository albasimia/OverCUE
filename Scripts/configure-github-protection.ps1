param(
    [string]$Repository = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required. Install it and run 'gh auth login'."
}

gh auth status | Out-Null
if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = (gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
}

$requiredChecks = @(
    "GitHub Actions / actionlint",
    "macOS / Swift 6",
    "Windows / .NET 10"
)

$payload = @{
    required_status_checks = @{
        strict = $true
        contexts = $requiredChecks
    }
    enforce_admins = $false
    required_pull_request_reviews = @{
        dismiss_stale_reviews = $false
        require_code_owner_reviews = $false
        required_approving_review_count = 0
        require_last_push_approval = $false
    }
    restrictions = $null
    required_linear_history = $true
    allow_force_pushes = $false
    allow_deletions = $false
    required_conversation_resolution = $true
} | ConvertTo-Json -Depth 8

foreach ($branch in @("develop", "main")) {
    gh api "repos/$Repository/branches/$branch" | Out-Null
    $temporaryFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText(
            $temporaryFile,
            $payload,
            [System.Text.UTF8Encoding]::new($false)
        )
        gh api `
            --method PUT `
            "repos/$Repository/branches/$branch/protection" `
            --input $temporaryFile | Out-Null
        Write-Host "Configured protection for $Repository/$branch"
    }
    finally {
        Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
    }
}
