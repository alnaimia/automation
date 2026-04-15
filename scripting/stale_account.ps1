Import-Module ActiveDirectory

# -----------------------------
# Config & Paths
# -----------------------------
$InactivityThresholdDays = 90

# Derive paths for portability
$LogDir      = Join-Path $PSScriptRoot "..\..\log_files"
$DateStamp   = Get-Date -Format "yyyy-MM-dd"
$LogFile     = Join-Path $LogDir "stale_accounts_$DateStamp.log"
$CsvFile     = Join-Path $LogDir "stale_accounts_$DateStamp.csv"

# Ensure the log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Initialize CSV with headers if it doesn't exist for today
if (-not (Test-Path $CsvFile)) {
    "SamAccountName,Enabled,NeverLoggedIn,LastLogonDate,Description,DistinguishedName,OU,ScanCutoffDate" | Out-File -FilePath $CsvFile -Encoding UTF8
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
$CutoffDate = (Get-Date).AddDays(-$InactivityThresholdDays).ToString("yyyy-MM-dd")
Write-Log "Threshold: $InactivityThresholdDays days | Cutoff date: $CutoffDate"

$CsvRows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($ou in $TargetOUs) {
    Write-Log "Scanning OU: $ou"

    try {
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
        $accountEnabled   = $user.Enabled
        $neverLoggedIn    = ($null -eq $user.LastLogonDate)
        $lastLogonClean   = if ($neverLoggedIn) { "" } else { $user.LastLogonDate }
        $lastLogonDisplay = if ($neverLoggedIn) { "Never Logged In" } else { $user.LastLogonDate }
        $desc             = if ($user.Description) { $user.Description } else { "No description" }

        Write-Log "STALE: $($user.SamAccountName) | Enabled: $accountEnabled | LastLogon: $lastLogonDisplay"

        $CsvRows.Add([PSCustomObject]@{
            SamAccountName    = $user.SamAccountName
            Enabled           = $accountEnabled
            NeverLoggedIn     = $neverLoggedIn
            LastLogonDate     = $lastLogonClean
            Description       = $desc
            DistinguishedName = $user.DistinguishedName
            OU                = $ou
            ScanCutoffDate    = $CutoffDate
        })
    }
}

if ($CsvRows.Count -gt 0) {
    # Using Append here so if you run the script multiple times a day, 
    # it adds to the CSV rather than overwriting the headers.
    $CsvRows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8 -Append
    Write-Log "CSV updated: $($CsvRows.Count) total stale account(s) written to $CsvFile"
} else {
    Write-Log "No stale accounts found across all OUs."
}

Write-Log "===== Stale Account Scan Complete ====="
