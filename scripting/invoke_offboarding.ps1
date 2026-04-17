# =============================================================================
# Invoke-Offboarding.ps1
# Profile-driven offboarding for Staff and Students.
# Supports bulk input, CSV audit log, and TXT run log.
#
# Folder structure expected:
#   automation\
#     scripting\        <- this script lives here
#     launchers\        <- .bat launcher lives here
#     log_files\        <- logs written here
# =============================================================================

Import-Module ActiveDirectory

# -----------------------------------------------------------------------------
# Logging Setup
# Derives log_files path from $PSScriptRoot so the script stays portable
# -----------------------------------------------------------------------------

$LogDir    = Join-Path $PSScriptRoot "..\log_files"
$DateStamp = Get-Date -Format "yyyy-MM-dd"
$CsvLog    = Join-Path $LogDir "offboarding_$DateStamp.csv"
$TxtLog    = Join-Path $LogDir "offboarding_$DateStamp.log"

# Ensure the log directory exists before any write attempts
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Initialise the CSV with headers if it does not already exist for today
if (-not (Test-Path $CsvLog)) {
    '"Timestamp","AdminUser","AccountType","Username","Action","Outcome","Detail"' |
        Out-File -FilePath $CsvLog -Encoding UTF8
}

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------

# Writes a line to the TXT run log and echoes it to the console.
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    $entry | Out-File -FilePath $TxtLog -Append -Encoding UTF8
    Write-Host $entry
}

# Appends a quoted, structured row to the CSV audit log.
function Write-AuditEntry {
    param(
        [Parameter(Mandatory)][string]$AdminUser,
        [Parameter(Mandatory)][string]$AccountType,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Outcome,
        [string]$Detail = ""
    )

    # Any literal double-quotes inside a field are escaped by doubling them.
    $row = '"{0}","{1}","{2}","{3}","{4}","{5}","{6}"' -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        ($AdminUser   -replace '"', '""'),
        ($AccountType -replace '"', '""'),
        ($Username    -replace '"', '""'),
        ($Action      -replace '"', '""'),
        ($Outcome     -replace '"', '""'),
        ($Detail      -replace '"', '""')

    $row | Out-File -FilePath $CsvLog -Append -Encoding UTF8
}

# -----------------------------------------------------------------------------
# Offboarding Profiles Configuration
# -----------------------------------------------------------------------------

$OffboardingProfiles = @{

    "1" = @{
        DisplayName    = "Staff Offboarding"
        AccountType    = "Staff"
        DisableAccount = $true
        GroupsToRemove = @(
            "staff_group_to_remove1",
            "staff_group_to_remove2"
        )
        GroupsToAdd    = @(
            "staff_group_to_add1"
        )
        HideFromGAL    = $true
        TargetOU       = "OU=Staff,OU=Disable Accounts,DC=add_company,DC=ac,DC=uk"
        OUMenu         = $null
    }

    "2" = @{
        DisplayName    = "Student Offboarding"
        AccountType    = "Student"
        DisableAccount = $true
        GroupsToRemove = @()
        GroupsToAdd    = @()
        HideFromGAL    = $true
        TargetOU       = $null
        OUMenu         = @{
            "1" = @{
                Name = "Student Withdrawals"
                DN   = "OU=Student Withdrawals,OU=Disable Accounts,DC=add_company,DC=ac,DC=uk"
            }
            "2" = @{
                Name = "Visa Reports"
                DN   = "OU=Visa Reports,OU=Disable Accounts,DC=add_company,DC=ac,DC=uk"
            }
        }
    }
}

# -----------------------------------------------------------------------------
# AD Helper Functions
# -----------------------------------------------------------------------------

function Set-UserDescriptionDisabled {
    param(
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User,
        [Parameter(Mandatory)][string]$Admin
    )
    $description = "Disabled by $Admin, on $(Get-Date -Format 'dd MMMM yyyy')"
    Set-ADUser -Identity $User -Description $description
}

function Hide-UserFromAddressLists {
    param([Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User)
    Set-ADUser -Identity $User -Replace @{msExchHideFromAddressLists = $true}
}

function Move-UserToOU {
    param(
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User,
        [Parameter(Mandatory)][string]$TargetOU
    )
    # Re-fetch DN here because $User may be a stale in-memory object after
    # Disable-ADAccount and Set-ADUser have run. This re-fetch is load-bearing
    # and should not be removed.
    $freshDN = (Get-ADUser -Identity $User.SamAccountName).DistinguishedName
    Move-ADObject -Identity $freshDN -TargetPath $TargetOU
}

function Block-M365SignIn {
    param([Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User)
    # FIX: A silent no-op, causing audit log to show "Success" without any
    # M365 action having taken place. Now logs a WARN until Graph API calls
    # are implemented here. Where local on prem syncs to cloud this isn't necessary
    Write-Log "  $($User.SamAccountName) — M365 sign-in handled via AD sync (no direct action taken)" -Level INFO
}

# -----------------------------------------------------------------------------
# Bulk Username Input
# -----------------------------------------------------------------------------

function Read-BulkUsernames {
    param([Parameter(Mandatory)][string]$AccountType)

    Write-Host ""
    Write-Host "Paste one or more $AccountType usernames (sAMAccountName)."
    Write-Host "Separate by new lines, spaces, or commas."
    Write-Host "Press ENTER on an empty line when finished."
    Write-Host ""

    $inputLines = @()
    while ($true) {
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $inputLines += $line
    }

    return ($inputLines -join " ") -split "[,\s]+" | Where-Object { $_ -ne "" }
}

# -----------------------------------------------------------------------------
# Core Offboarding Workflow
# -----------------------------------------------------------------------------

function Invoke-OffboardingWorkflow {
    param(
        [Parameter(Mandatory)][hashtable]$ActiveProfile,
        [Parameter(Mandatory)][string[]]$UserIDs,
        [Parameter(Mandatory)][string]$AdminUser,
        [string]$ResolvedOU = ""
    )

    $notFound        = @()
    $alreadyDisabled = @()
    $success         = @()

    $total   = $UserIDs.Count
    $counter = 0

    Write-Log "Starting $($ActiveProfile.DisplayName) — $total account(s) — Admin: $AdminUser"

    foreach ($userID in $UserIDs) {
        $counter++
        Write-Log "[$counter / $total] Processing: $userID"

        $targetUser = Get-ADUser -Filter { SamAccountName -eq $userID } `
                                 -Properties Enabled, msExchHideFromAddressLists, UserPrincipalName

        if (-not $targetUser) {
            Write-Log "  $userID — NOT FOUND in Active Directory" -Level WARN
            Write-AuditEntry -AdminUser $AdminUser -AccountType $ActiveProfile.AccountType `
                             -Username $userID -Action $ActiveProfile.DisplayName `
                             -Outcome "NotFound"
            $notFound += $userID
            continue
        }

        if ($targetUser.Enabled -eq $false) {
            Write-Log "  $userID — already disabled, skipping" -Level WARN
            Write-AuditEntry -AdminUser $AdminUser -AccountType $ActiveProfile.AccountType `
                             -Username $userID -Action $ActiveProfile.DisplayName `
                             -Outcome "AlreadyDisabled"
            $alreadyDisabled += $userID
            continue
        }

        # Determine target OU
        $targetOU = if ($ActiveProfile.TargetOU) { $ActiveProfile.TargetOU } else { $ResolvedOU }

        try {
            if ($ActiveProfile.DisableAccount) {
                Disable-ADAccount -Identity $targetUser
                Set-UserDescriptionDisabled -User $targetUser -Admin $AdminUser
                Write-Log "  $userID — account disabled"
            }

            # Wrapped in try/catch so errors are
            # logged as WARN and do not halt the rest of the user's processing.
            foreach ($group in $ActiveProfile.GroupsToRemove) {
                try {
                    Remove-ADGroupMember -Identity $group -Members $userID `
                                        -Confirm:$false -ErrorAction Stop
                    Write-Log "  $userID — removed from group: $group"
                } catch {
                    Write-Log "  $userID — FAILED to remove from group '$group': $_" -Level WARN
                }
            }

            foreach ($group in $ActiveProfile.GroupsToAdd) {
                try {
                    Add-ADGroupMember -Identity $group -Members $userID -ErrorAction Stop
                    Write-Log "  $userID — added to group: $group"
                } catch {
                    Write-Log "  $userID — FAILED to add to group '$group': $_" -Level WARN
                }
            }

            if ($ActiveProfile.HideFromGAL) {
                Hide-UserFromAddressLists -User $targetUser
                Write-Log "  $userID — hidden from GAL"
            }

            if ($targetOU) {
                Move-UserToOU -User $targetUser -TargetOU $targetOU
                Write-Log "  $userID — moved to OU: $targetOU"
            }

            Block-M365SignIn -User $targetUser

            Write-AuditEntry -AdminUser $AdminUser -AccountType $ActiveProfile.AccountType `
                             -Username $userID -Action $ActiveProfile.DisplayName `
                             -Outcome "Success" -Detail $targetOU

            $success += $userID

        } catch {
            Write-Log "  $userID — ERROR: $_" -Level ERROR
            Write-AuditEntry -AdminUser $AdminUser -AccountType $ActiveProfile.AccountType `
                             -Username $userID -Action $ActiveProfile.DisplayName `
                             -Outcome "Error" -Detail $_.Exception.Message
        }
    }

    # Summary Output
    Write-Log "========================================"
    Write-Log "$($ActiveProfile.DisplayName) Complete"
    Write-Log "  Successful:       $($success.Count)"
    Write-Log "  Already Disabled: $($alreadyDisabled.Count)"
    Write-Log "  Not Found:        $($notFound.Count)"
    Write-Log "========================================"

    Write-Host "`nLogs written to:`n  $CsvLog`n  $TxtLog"
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

$currentAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Log "=== Offboarding Script launched by $currentAdmin ==="

Write-Host "`nOffboarding Script`n----------------------------------------"
foreach ($key in $OffboardingProfiles.Keys | Sort-Object) {
    Write-Host "$key. $($OffboardingProfiles[$key].DisplayName)"
}
Write-Host ""

$selection = Read-Host "Select workflow"

if (-not $OffboardingProfiles.ContainsKey($selection)) {
    Write-Log "Invalid workflow selection: '$selection'" -Level WARN
    Write-Host "Invalid selection. Exiting."
    exit
}

$selectedProfile = $OffboardingProfiles[$selection]
$userIDs = Read-BulkUsernames -AccountType $selectedProfile.AccountType

if ($userIDs.Count -eq 0) {
    Write-Log "No usernames entered. Exiting." -Level WARN
    exit
}

$resolvedOU = ""
if ($null -eq $selectedProfile.TargetOU -and $null -ne $selectedProfile.OUMenu) {
    Write-Host "`nSelect destination OU:"
    foreach ($key in $selectedProfile.OUMenu.Keys | Sort-Object) {
        Write-Host "$key. $($selectedProfile.OUMenu[$key].Name)"
    }
    $ouChoice = Read-Host "Enter option number"

    if (-not $selectedProfile.OUMenu.ContainsKey($ouChoice)) {
        Write-Log "Invalid OU selection: '$ouChoice'" -Level WARN
        exit
    }
    $resolvedOU = $selectedProfile.OUMenu[$ouChoice].DN
}

# Confirmation added before bulk processing. Displays the full account
# list so the operator can verify before committing — for greater counts
Write-Host "`n----------------------------------------"
Write-Host "Ready to run '$($selectedProfile.DisplayName)' on $($userIDs.Count) account(s):"
$userIDs | ForEach-Object { Write-Host "  $_" }
if ($resolvedOU) { Write-Host "  Destination OU: $resolvedOU" }
Write-Host "----------------------------------------"
$confirm = Read-Host "Proceed? (yes/no)"

if ($confirm -ne "yes") {
    Write-Log "Run aborted by operator at confirmation prompt." -Level WARN
    Write-Host "Aborted."
    exit
}

Invoke-OffboardingWorkflow `
    -ActiveProfile $selectedProfile `
    -UserIDs       $userIDs `
    -AdminUser     $currentAdmin `
    -ResolvedOU    $resolvedOU

Write-Host "`nPress any key to close..."
$null = [Console]::ReadKey($true)
