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
# regardless of which drive letter the .bat maps the UNC share to.
# -----------------------------------------------------------------------------

$LogDir     = Join-Path $PSScriptRoot "..\..\log_files"
$DateStamp  = Get-Date -Format "yyyy-MM-dd"
$CsvLog     = Join-Path $LogDir "offboarding_$DateStamp.csv"
$TxtLog     = Join-Path $LogDir "offboarding_$DateStamp.log"

# Ensure the log directory exists before any write attempts
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Initialise the CSV with headers if it does not already exist for today
if (-not (Test-Path $CsvLog)) {
    "Timestamp,AdminUser,AccountType,Username,Action,Outcome,Detail" | Out-File -FilePath $CsvLog -Encoding UTF8
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

# Appends a structured row to the CSV audit log.
function Write-AuditEntry {
    param(
        [Parameter(Mandatory)][string]$AdminUser,
        [Parameter(Mandatory)][string]$AccountType,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Outcome,
        [string]$Detail = ""
    )

    $row = "{0},{1},{2},{3},{4},{5},{6}" -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $AdminUser,
        $AccountType,
        $Username,
        $Action,
        $Outcome,
        $Detail

    $row | Out-File -FilePath $CsvLog -Append -Encoding UTF8
}

# -----------------------------------------------------------------------------
# Offboarding Profiles
# Each profile defines exactly what the offboarding workflow does.
# Add new profiles here without touching the workflow functions.
#
# Keys:
#   DisplayName     - shown in menus and logs
#   AccountType     - label used in CSV (e.g. "Staff", "Student")
#   DisableAccount  - $true/$false
#   GroupsToRemove  - array of AD group names to remove the user from
#   GroupsToAdd     - array of AD group names to add the user to
#   HideFromGAL     - $true/$false — sets msExchHideFromAddressLists
#   TargetOU        - DN string, or $null if resolved at runtime (e.g. student menu)
#   OUMenu          - hashtable of menu options when TargetOU is $null
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
            # Add further licence or retention groups here as needed
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
        TargetOU       = $null   # resolved at runtime via OUMenu below
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
    # Re-fetch DN immediately before move to avoid stale distinguished name
    $freshDN = (Get-ADUser -Identity $User.SamAccountName).DistinguishedName
    Move-ADObject -Identity $freshDN -TargetPath $TargetOU
}

# Placeholder — uncomment and configure if automating M365 sign-in block
function Block-M365SignIn {
    param([Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User)
    <#
        Import-Module Microsoft.Graph.Users
        Connect-MgGraph -Scopes "User.ReadWrite.All"
        Update-MgUser -UserId $User.UserPrincipalName -AccountEnabled:$false
    #>
}

# -----------------------------------------------------------------------------
# Bulk Username Input
# Shared by all workflows — parses free-form input (newlines, spaces, commas)
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
# Accepts a profile hashtable and processes all userIDs against it.
# -----------------------------------------------------------------------------

function Invoke-OffboardingWorkflow {
    param(
        [Parameter(Mandatory)][hashtable]$Profile,
        [Parameter(Mandatory)][string[]]$UserIDs,
        [Parameter(Mandatory)][string]$AdminUser,
        [string]$ResolvedOU = ""   # populated at call site when OUMenu is used
    )

    $notFound        = @()
    $alreadyDisabled = @()
    $success         = @()

    $total   = $UserIDs.Count
    $counter = 0

    Write-Log "Starting $($Profile.DisplayName) — $total account(s) — Admin: $AdminUser"

    foreach ($userID in $UserIDs) {
        $counter++
        Write-Log "[$counter / $total] Processing: $userID"

        $targetUser = Get-ADUser -Filter { SamAccountName -eq $userID } `
                                 -Properties Enabled, msExchHideFromAddressLists, UserPrincipalName

        if (-not $targetUser) {
            Write-Log "  $userID — NOT FOUND in Active Directory" -Level WARN
            Write-AuditEntry -AdminUser $AdminUser -AccountType $Profile.AccountType `
                             -Username $userID -Action $Profile.DisplayName `
                             -Outcome "NotFound"
            $notFound += $userID
            continue
        }

        if ($targetUser.Enabled -eq $false) {
            Write-Log "  $userID — already disabled, skipping" -Level WARN
            Write-AuditEntry -AdminUser $AdminUser -AccountType $Profile.AccountType `
                             -Username $userID -Action $Profile.DisplayName `
                             -Outcome "AlreadyDisabled"
            $alreadyDisabled += $userID
            continue
        }

        # Determine target OU — use profile value or the runtime-resolved value
        $targetOU = if ($Profile.TargetOU) { $Profile.TargetOU } else { $ResolvedOU }

        try {
            if ($Profile.DisableAccount) {
                Disable-ADAccount -Identity $targetUser
                Set-UserDescriptionDisabled -User $targetUser -Admin $AdminUser
                Write-Log "  $userID — account disabled"
            }

            foreach ($group in $Profile.GroupsToRemove) {
                Remove-ADGroupMember -Identity $group -Members $userID `
                                     -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "  $userID — removed from group: $group"
            }

            foreach ($group in $Profile.GroupsToAdd) {
                Add-ADGroupMember -Identity $group -Members $userID `
                                  -ErrorAction SilentlyContinue
                Write-Log "  $userID — added to group: $group"
            }

            if ($Profile.HideFromGAL) {
                Hide-UserFromAddressLists -User $targetUser
                Write-Log "  $userID — hidden from GAL"
            }

            if ($targetOU) {
                Move-UserToOU -User $targetUser -TargetOU $targetOU
                Write-Log "  $userID — moved to OU: $targetOU"
            }

            Block-M365SignIn -User $targetUser

            Write-AuditEntry -AdminUser $AdminUser -AccountType $Profile.AccountType `
                             -Username $userID -Action $Profile.DisplayName `
                             -Outcome "Success" -Detail $targetOU

            $success += $userID

        } catch {
            Write-Log "  $userID — ERROR: $_" -Level ERROR
            Write-AuditEntry -AdminUser $AdminUser -AccountType $Profile.AccountType `
                             -Username $userID -Action $Profile.DisplayName `
                             -Outcome "Error" -Detail $_.Exception.Message
        }
    }

    # -------------------------------------------------------------------------
    # End-of-run Summary
    # -------------------------------------------------------------------------
    Write-Log "========================================"
    Write-Log "$($Profile.DisplayName) Complete"
    Write-Log "  Successful:       $($success.Count)"
    Write-Log "  Already Disabled: $($alreadyDisabled.Count)"
    Write-Log "  Not Found:        $($notFound.Count)"
    Write-Log "========================================"

    Write-Host ""
    Write-Host "========================================"
    Write-Host "$($Profile.DisplayName) Summary"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Successful: $($success.Count)"
    if ($success.Count -gt 0)         { $success         | ForEach-Object { Write-Host "   $_" } }
    Write-Host ""
    Write-Host "Already Disabled: $($alreadyDisabled.Count)"
    if ($alreadyDisabled.Count -gt 0) { $alreadyDisabled | ForEach-Object { Write-Host "   $_" } }
    Write-Host ""
    Write-Host "Not Found: $($notFound.Count)"
    if ($notFound.Count -gt 0)        { $notFound        | ForEach-Object { Write-Host "   $_" } }
    Write-Host ""
    Write-Host "Logs written to:"
    Write-Host "   $CsvLog"
    Write-Host "   $TxtLog"
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

$currentAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Log "=== Offboarding Script launched by $currentAdmin ==="

Write-Host ""
Write-Host "Offboarding Script"
Write-Host "----------------------------------------"
foreach ($key in $OffboardingProfiles.Keys | Sort-Object) {
    Write-Host "$key. $($OffboardingProfiles[$key].DisplayName)"
}
Write-Host ""

$selection = Read-Host "Select workflow"

if (-not $OffboardingProfiles.ContainsKey($selection)) {
    Write-Log "Invalid workflow selection: '$selection'" -Level WARN
    Write-Host "Invalid selection. Exiting."
    $null = [Console]::ReadKey($true)
    exit
}

$selectedProfile = $OffboardingProfiles[$selection]

# Collect usernames
$userIDs = Read-BulkUsernames -AccountType $selectedProfile.AccountType

if ($userIDs.Count -eq 0) {
    Write-Log "No usernames entered. Exiting." -Level WARN
    Write-Host "No usernames entered. Exiting."
    $null = [Console]::ReadKey($true)
    exit
}

Write-Host ""
Write-Host "You entered $($userIDs.Count) $($selectedProfile.AccountType) ID(s)."

# Resolve OU at runtime if the profile uses a menu
$resolvedOU = ""
if ($null -eq $selectedProfile.TargetOU -and $null -ne $selectedProfile.OUMenu) {
    Write-Host ""
    Write-Host "Select destination OU:"
    foreach ($key in $selectedProfile.OUMenu.Keys | Sort-Object) {
        Write-Host "$key. $($selectedProfile.OUMenu[$key].Name)"
    }
    $ouChoice = Read-Host "Enter option number"

    if (-not $selectedProfile.OUMenu.ContainsKey($ouChoice)) {
        Write-Log "Invalid OU selection: '$ouChoice'" -Level WARN
        Write-Host "Invalid selection. Exiting."
        $null = [Console]::ReadKey($true)
        exit
    }

    $resolvedOU = $selectedProfile.OUMenu[$ouChoice].DN
    Write-Host "Destination OU: $($selectedProfile.OUMenu[$ouChoice].Name)"
    Write-Log "OU resolved to: $resolvedOU"
}

# Run the workflow
Invoke-OffboardingWorkflow `
    -Profile    $selectedProfile `
    -UserIDs    $userIDs `
    -AdminUser  $currentAdmin `
    -ResolvedOU $resolvedOU

Write-Host "`nPress any key to close..."
$null = [Console]::ReadKey($true)
