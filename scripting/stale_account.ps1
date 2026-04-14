# =============================================================================
# Stale Account Detection Script
# Logs stale AD accounts to stale_accounts_log.txt and stale_accounts_<date>.csv
# This script audits login activity, not password hygiene.
#
# EXPECTED OU STRUCTURE:
#   This script assumes accounts are organised under named OUs directly
#   beneath the domain root, e.g.:
#
#     OU=Staff,DC=domain_name,DC=ac,DC=uk
#     OU=Students,DC=domain_name,DC=ac,DC=uk
#
#   Sub-OUs are included automatically via the default SearchScope (Subtree).
#   If your structure nests accounts deeper (e.g. OU=FT,OU=Staff,...) no
#   changes are needed — they will be picked up. If accounts live outside
#   these two OUs entirely, add the relevant DN to $TargetOUs below.
# =============================================================================

Import-Module ActiveDirectory

# -----------------------------
# Config
# -----------------------------

$InactivityThresholdDays = 90

# ---- $PSScriptRoot guard: safe in all execution contexts ----
# $PSScriptRoot is empty when dot-sourced or run from ISE.
# Fall back to $MyInvocation.MyCommand.Path in that case.
$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RootDir = Split-Path -Parent $ScriptDir

# ---- Paths ----
# Log file: single persistent file, appended on each run.
$LogFile = Join-Path $RootDir "stale_accounts_log.txt"

# CSV file: date-stamped per run so previous output is never overwritten.
# Each CSV is the per-run deliverable; the log is the ongoing audit trail.
$CsvDateStamp = Get-Date -Format "yyyy-MM-dd"
$CsvFile      = Join-Path $RootDir "stale_accounts_$CsvDateStamp.csv"

# Ensure log file exists
if (-not (Test-Path $LogFile)) {
    New-Item -Path $LogFile -ItemType File -Force | Out-Null
}

# OUs to scan
$TargetOUs = @(
    "OU=Staff,DC=add_company,DC=ac,DC=uk",
    "OU=Students,DC=add_company,DC=ac,DC=uk"
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

    # Stale = never logged in OR last logon is beyond the threshold.
    #
    # Note on LastLogonDate accuracy:
    #   LastLogonDate wraps LastLogonTimestamp, which replicates across DCs
    #   within a ~14-day window by design. At a 90-day threshold this margin
    #   is acceptable — edge cases within ~14 days of the cutoff may vary,
    #   but any account genuinely inactive for 90+ days will be caught reliably.
    Get-ADUser -Filter * `
        -SearchBase $SearchBase `
        -Properties Enabled, LastLogonDate, Description, DistinguishedName |
    Where-Object {
        ($null -eq $_.LastLogonDate) -or
        ($_.LastLogonDate -lt $thresholdDate)
    }
}

# -----------------------------
# Main Workflow
# -----------------------------

Write-Log "===== Stale Account Scan Started ====="

# Log the active threshold so the output is self-documenting.
# Anyone reviewing the log later can see exactly what window was applied
# without having to open the script.
$CutoffDate = (Get-Date).AddDays(-$InactivityThresholdDays).ToString("yyyy-MM-dd")
Write-Log "Threshold: $InactivityThresholdDays days | Cutoff date: $CutoffDate"
Write-Log "CSV output: $CsvFile"

# Use a generic List instead of += array concatenation.
# List.Add() is O(1); += rebuilds the entire array on every iteration.
$CsvRows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($ou in $TargetOUs) {

    Write-Log "Scanning OU: $ou"

    # Wrap Get-ADUser in try/catch per OU.
    try {
        # @() forces a single returned object into an array so .Count is reliable.
        # Without this, one result returns a bare ADUser object, not a 1-item array.
        $staleUsers = @(Get-StaleUsers -SearchBase $ou)
    }
    catch {
        Write-Log "ERROR scanning OU: $ou | $_"
        continue
    }

    if ($staleUsers.Count -eq 0) {
        Write-Log "No stale accounts found in $ou"
        continue
    }

    Write-Log "Found $($staleUsers.Count) stale account(s) in $ou"

    foreach ($user in $staleUsers) {

        # Boolean: directly reflects the AD Enabled attribute.
        # Stored as True/False so Excel and other tools can filter without
        $accountEnabled = $user.Enabled

        # NeverLoggedIn: boolean flag kept separate from the date column.
        # Mixing "Never Logged In" string into a date column breaks Excel sorting.
        # The date column stays null (blank cell) for never-logged-in accounts;
        # this boolean carries the signal cleanly for filtering.
        $neverLoggedIn  = ($null -eq $user.LastLogonDate)
        $lastLogonClean = if ($neverLoggedIn) { $null } else { $user.LastLogonDate }

        # Human-readable last logon for the log file only.
        $lastLogonDisplay = if ($neverLoggedIn) { "Never Logged In" } else { $user.LastLogonDate }

        $desc = if ($user.Description) { $user.Description } else { "No description" }

        Write-Log "STALE: $($user.SamAccountName) | Enabled: $accountEnabled | LastLogon: $lastLogonDisplay | Description: $desc"

        $CsvRows.Add([PSCustomObject]@{
            SamAccountName    = $user.SamAccountName
            Enabled           = $accountEnabled       # Boolean - filter-friendly in Excel
            NeverLoggedIn     = $neverLoggedIn        # Boolean - True if account has never logged in
            LastLogonDate     = $lastLogonClean       # Blank cell if never logged in; date otherwise
            Description       = $desc
            DistinguishedName = $user.DistinguishedName
            OU                = $ou
            ScanCutoffDate    = $CutoffDate           # Stamped per row; CSV is self-contained without the log
        })
    }
}

# Export CSV — date-stamped filename means this never overwrites a previous run.
# $TotalStale is only logged and printed when stale accounts actually exist,
# avoiding a redundant "0 stale accounts" line after the already-clear
if ($CsvRows.Count -gt 0) {
    $CsvRows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
    Write-Log "CSV exported: $($CsvRows.Count) total stale account(s) written to $CsvFile"
    Write-Host "Total stale accounts found: $($CsvRows.Count)"
} else {
    Write-Log "No stale accounts found across all OUs. CSV not created."
}

Write-Log "===== Stale Account Scan Complete ====="
Write-Host "Scan complete. Log saved to:  $LogFile"
Write-Host "CSV saved to:                 $CsvFile"
