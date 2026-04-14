# =============================================================================
# Stale Account Detection Script
# Logs stale AD accounts to stale_accounts_log.txt in the script directory.
# =============================================================================

Import-Module ActiveDirectory

# -----------------------------
# Config
# -----------------------------

# Number of days of inactivity before an account is considered stale
$InactivityThresholdDays = 90

# Log file saved in the same folder as this script
$LogFile = Join-Path -Path $PSScriptRoot -ChildPath "stale_accounts_log.txt"

# OUs to scan (optional)
$TargetOUs = @(
    "OU=Staff,DC=add_company/domain_name,DC=ac,DC=uk",
    "OU=Students,DC=add_company/domain_name,DC=ac,DC=uk"
)

# -----------------------------
# Helper Functions
# -----------------------------

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp - $Message"
}

function Get-StaleUsers {
    param([Parameter(Mandatory)][string]$SearchBase)

    $thresholdDate = (Get-Date).AddDays(-$InactivityThresholdDays)

    Get-ADUser -Filter * `
        -SearchBase $SearchBase `
        -Properties Enabled, LastLogonDate, PasswordLastSet |
    Where-Object {
        ($_.LastLogonDate -eq $null) -or
        ($_.LastLogonDate -lt $thresholdDate) -or
        ($_.PasswordLastSet -lt $thresholdDate)
    }
}

# -----------------------------
# Main Workflow
# -----------------------------

Write-Log "===== Stale Account Scan Started ====="

foreach ($ou in $TargetOUs) {
    Write-Log "Scanning OU: $ou"

    $staleUsers = Get-StaleUsers -SearchBase $ou

    if ($staleUsers.Count -eq 0) {
        Write-Log "No stale accounts found in $ou"
        continue
    }

    foreach ($user in $staleUsers) {
        $status = if ($user.Enabled) { "ENABLED" } else { "DISABLED" }
        $lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate } else { "Never Logged In" }

        Write-Log "STALE: $($user.SamAccountName) | $status | LastLogon: $lastLogon | PasswordLastSet: $($user.PasswordLastSet)"
    }
}

Write-Log "===== Stale Account Scan Complete ====="
Write-Host "Scan complete. Log saved to: $LogFile"

