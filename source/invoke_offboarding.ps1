# =============================================================================
# Offboarding Script — Staff & Student
# Handles AD account disabling, group management, OU moves, and GAL hiding.
# =============================================================================

# Import the Active Directory module (required for all AD cmdlets)
Import-Module ActiveDirectory

# -----------------------------
# Config: OUs and Groups
# -----------------------------

# OU where disabled staff accounts are moved
$StaffDisabledOU = "OU=Staff,OU=Disable Accounts,DC=add_company/domain_name,DC=ac,DC=uk"

# OUs where disabled student accounts can be moved.
# The user selects one at runtime — the key is the menu option number.
$StudentDisabledOUs = @{
    "1" = @{
        Name = "Student Withdrawals"
        DN   = "OU=Student Withdrawals,OU=Disable Accounts,DC=add_company/domain_name,DC=ac,DC=uk"
    }
    "2" = @{
        Name = "Visa Reports"
        DN   = "OU=Visa Reports,OU=Disable Accounts,DC=add_company/domain_name,DC=ac,DC=uk"
    }
}

# AD groups to remove the staff member from during offboarding (modify as needed)
$StaffGroupsToRemove = @(
    "staff_group_to_remove1", 
    "staff_group_to_remove2"
)

# AD group to add the staff member to during offboarding (e.g. an A1 licence group, (modify as needed))
$StaffA1Group = "staff_group_to_add1"

# -----------------------------
# Helper Functions
# -----------------------------

# Sets the user's Description field to record who disabled the account and when.
function Set-UserDescriptionDisabled {
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User,

        [Parameter(Mandatory)]
        [string]$Admin
    )

    $description = "Disabled by $Admin, on $(Get-Date -Format 'dd MMMM yyyy')"
    Set-ADUser -Identity $User -Description $description
}

# Hides the user from Exchange/M365 address lists via the msExchHideFromAddressLists attribute.
function Hide-UserFromAddressLists {
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User
    )

    Set-ADUser -Identity $User -Replace @{msExchHideFromAddressLists = $true}
}

# Moves the user's AD object to the specified target OU.
# Note: uses the user's SamAccountName as the identity to avoid relying on a
# potentially stale DistinguishedName from an earlier Get-ADUser call.
function Move-UserToOU {
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User,

        [Parameter(Mandatory)]
        [string]$TargetOU
    )

    # Re-fetch the DN immediately before moving to ensure it reflects the
    # current state in AD, rather than trusting the DN from an earlier query.
    $freshDN = (Get-ADUser -Identity $User.SamAccountName).DistinguishedName
    Move-ADObject -Identity $freshDN -TargetPath $TargetOU
}

# Placeholder for blocking M365 sign-in via Microsoft Graph.
# Uncomment and configure if you want to automate this step.
function Block-M365SignIn {
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User
    )

    <#
        OPTIONAL: Requires Microsoft Graph PowerShell and appropriate permissions.

        Import-Module Microsoft.Graph.Users
        Connect-MgGraph -Scopes "User.ReadWrite.All"
        Update-MgUser -UserId $User.UserPrincipalName -AccountEnabled:$false
    #>
}

# Validates that an AD user object exists and is currently enabled.
# Returns $true if safe to proceed, $false otherwise.
# Note: only call this after a $null check — passing $null to a typed
# mandatory parameter will throw a binding error before the function body runs.
function Confirm-UserExistsAndEnabled {
    param(
        [Parameter(Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User
    )

    if ($User.Enabled -eq $false) {
        Write-Host "User is already in a disabled state."
        return $false
    }

    return $true
}

# -----------------------------
# Staff Offboarding Workflow
# -----------------------------

function Invoke-StaffOffboarding {

    # Capture the admin running the script for audit trail in the description field
    $currentAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $targetUserName = Read-Host "Please enter the STAFF username (sAMAccountName) you want to disable"

    $targetUser = Get-ADUser -Filter { SamAccountName -eq $targetUserName } `
                             -Properties Enabled, msExchHideFromAddressLists

    # Guard against user not found — must be checked before passing to
    # Confirm-UserExistsAndEnabled, as a $null cannot be bound to a typed mandatory param.
    if (-not $targetUser) {
        Write-Host "User '$targetUserName' not found in Active Directory."
        return
    }

    # Guard against the account already being disabled
    if (-not (Confirm-UserExistsAndEnabled -User $targetUser)) {
        return
    }

    # Disable the AD account
    Disable-ADAccount -Identity $targetUser

    # Update description to record who disabled the account and when
    Set-UserDescriptionDisabled -User $targetUser -Admin $currentAdmin

    # Remove from specified staff groups. SilentlyContinue so a missing group
    # doesn't abort the rest of the offboarding steps.
    foreach ($group in $StaffGroupsToRemove) {
        Remove-ADGroupMember -Identity $group -Members $targetUserName `
                             -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Add to the A1 licence group (e.g. to retain a basic M365 licence post-offboarding)
    Add-ADGroupMember -Identity $StaffA1Group -Members $targetUserName `
                      -ErrorAction SilentlyContinue

    # Hide from the Global Address List
    Hide-UserFromAddressLists -User $targetUser

    # Move to the staff disabled OU
    Move-UserToOU -User $targetUser -TargetOU $StaffDisabledOU

    # Block M365 sign-in (optional — see function definition above)
    Block-M365SignIn -User $targetUser

    Write-Host "Staff user '$targetUserName' has been disabled, updated, and moved to '$StaffDisabledOU'."
}

# -----------------------------
# Student Offboarding Workflow (Bulk)
# -----------------------------

function Invoke-StudentOffboarding {

    # Capture the admin running the script for audit trail in the description field
    $currentAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Host "Paste one or more STUDENT IDs (sAMAccountName)."
    Write-Host "Separate them by new lines, spaces, or commas."
    Write-Host "Press ENTER on an empty line when finished."
    Write-Host ""

    # Collect input lines until a blank line is entered
    $inputLines = @()
    while ($true) {
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $inputLines += $line
    }

    # Join all lines and split on whitespace or commas to get individual IDs
    $studentIDs = $inputLines -join " "
    $studentIDs = $studentIDs -split "[,\s]+" | Where-Object { $_ -ne "" }

    if ($studentIDs.Count -eq 0) {
        Write-Host "No student IDs entered. Exiting."
        return
    }

    Write-Host ""
    Write-Host "You entered $($studentIDs.Count) student IDs."
    Write-Host ""

    # Prompt admin to select the destination OU once — applies to all students in this batch
    Write-Host "Select destination OU for ALL disabled students:"
    foreach ($key in $StudentDisabledOUs.Keys | Sort-Object) {
        $name = $StudentDisabledOUs[$key].Name
        Write-Host "$key. $name"
    }

    $choice = Read-Host "Enter option number"

    if (-not $StudentDisabledOUs.ContainsKey($choice)) {
        Write-Host "Invalid selection. Exiting."
        return
    }

    $targetOUName = $StudentDisabledOUs[$choice].Name
    $targetOUDN   = $StudentDisabledOUs[$choice].DN

    Write-Host ""
    Write-Host "All students will be moved to: $targetOUName"
    Write-Host ""

    # Tracking arrays for the end-of-run summary
    $notFound        = @()
    $alreadyDisabled = @()
    $success         = @()

    $total   = $studentIDs.Count
    $counter = 0

    foreach ($studentID in $studentIDs) {
        $counter++
        Write-Host ""
        Write-Host "[$counter / $total] Processing: $studentID"
        Write-Host "----------------------------------------"

        $targetUser = Get-ADUser -Filter { SamAccountName -eq $studentID } `
                                 -Properties Enabled, msExchHideFromAddressLists, UserPrincipalName

        # Skip if user doesn't exist in AD
        if (-not $targetUser) {
            Write-Host "User not found."
            $notFound += $studentID
            continue
        }

        # Skip if already disabled — no need to process further
        if ($targetUser.Enabled -eq $false) {
            Write-Host "User already disabled."
            $alreadyDisabled += $studentID
            continue
        }

        # Disable the AD account
        Disable-ADAccount -Identity $targetUser

        # Update description to record who disabled the account and when
        Set-UserDescriptionDisabled -User $targetUser -Admin $currentAdmin

        # Hide from the Global Address List
        Hide-UserFromAddressLists -User $targetUser

        # Block M365 sign-in (optional — see function definition above)
        Block-M365SignIn -User $targetUser

        # Move to the selected disabled OU
        Move-UserToOU -User $targetUser -TargetOU $targetOUDN

        Write-Host "Successfully disabled and moved to $targetOUName."
        $success += $studentID
    }

    # -----------------------------
    # End-of-run Summary
    # -----------------------------
    Write-Host ""
    Write-Host "========================================"
    Write-Host "Bulk Student Offboarding Summary"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Successful: $($success.Count)"
    if ($success.Count -gt 0) { $success | ForEach-Object { Write-Host "   $_" } }

    Write-Host ""
    Write-Host "Not Found: $($notFound.Count)"
    if ($notFound.Count -gt 0) { $notFound | ForEach-Object { Write-Host "   $_" } }

    Write-Host ""
    Write-Host "Already Disabled: $($alreadyDisabled.Count)"
    if ($alreadyDisabled.Count -gt 0) { $alreadyDisabled | ForEach-Object { Write-Host "   $_" } }

    Write-Host ""
    Write-Host "Bulk student offboarding complete."
}

# -----------------------------
# Entry Point
# -----------------------------

Write-Host "Offboarding Script"
Write-Host "1. Staff"
Write-Host "2. Student"

$selection = Read-Host "Select type to offboard (1 or 2)"

switch ($selection) {
    "1"     { Invoke-StaffOffboarding }
    "2"     { Invoke-StudentOffboarding }
    default { Write-Host "Invalid selection. Exiting." }
}

Write-Host "`nPress any key to close..."
$null = [Console]::ReadKey($true)
