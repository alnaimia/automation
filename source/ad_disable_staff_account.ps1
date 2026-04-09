
# Import the Active Directory module
Import-Module ActiveDirectory

# Step 1: Get the name of the user that is running the current PowerShell session
$currentAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Step 2: Prompt the user to enter a username to disable
$targetUserName = Read-Host "Please enter the username you want to disable"

# Step 3: Search for the user in Active Directory
$targetUser = Get-ADUser -Filter {SamAccountName -eq $targetUserName} -Properties Enabled, msExchHideFromAddressLists

if (!$targetUser) {
    Write-Host "User not found in Active Directory."
    
}

elseif ($targetUser.Enabled -eq $false) {
    Write-Host "User is already in a disabled state."
    
}

else {


# Step 4: If the user is found and not currently in a disabled state, disable the user
Disable-ADAccount -Identity $targetUser

# Step 5: Add a description to the AD user with the admin and date info
$description = "Disabled by $currentAdmin, on $(Get-Date -Format 'dd MMMM yyyy')"
Set-ADUser -Identity $targetUser -Description $description

# Step 6: Remove the user from multiple security groups (Modify the list as needed)
$groupsToRemove = @("group_to_remove_1", "group_to_remove_2")
foreach ($group in $groupsToRemove) {
    Remove-ADGroupMember -Identity $group -Members $targetUserName -Confirm:$false -ErrorAction SilentlyContinue
}

# Step 7: Add the user to the "groups to add" security group
Add-ADGroupMember -Identity "group_to_add_1" -Members $targetUserName


# Step 8: Set the "msExchHideFromAddressLists" attribute to True
Set-ADUser -Identity $targetUser -Replace @{msExchHideFromAddressLists=$true}

# Step 9: Move the disabled user to the "OU=Staff,OU=Disable Accounts,DC=add_company/domain_name,DC=ac,DC=uk"
$destinationOU = "OU=Staff,OU=Disable Accounts,DC=add_company/domain_name,DC=ac,DC=uk"
Move-ADObject -Identity $targetUser.DistinguishedName -TargetPath $destinationOU


# Final Step: Notify the user about the success of the operation
Write-Host "The user account '$targetUserName' has been successfully disabled, removed from groups, and updated."

}
