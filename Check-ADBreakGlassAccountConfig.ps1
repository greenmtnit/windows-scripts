<#
    Check-ADBreakGlassAccountConfig.ps1
    
    Script to check configuration for ActiveDirectory Break Glass accounts.
        
    Syncro Script Variables:
        $BreakGlassUsername - Dropdown Variable. Set a default value of the standard break-glass account Active Directory username.
            Username is not hard-coded into the script for security reasons.

    Summary:
        Checks if the machine is a domain controller and exits if not.
        Performs checks on the break glass user:
            Is the user a member of the Domain Admins group?
            Is the user a member of the Enterprise Admins group?
            Check that a password change is NOT requred on next logon.
            Check that the user's password is set to never expire.
            Check that the account is set to never expire.
        If configuration issues are found, throw a Syncro RMM Alert.
        If there are no configuration issues found, close the RMM alert (if any).
        
    
#>
Import-Module $env:SyncroModule
Import-Module ActiveDirectory

$alertCategory = "Active Directory Break Glass Config"
$username = $BreakGlassUsername # from Syncro script variables

if ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 2) { 
    Write-Host "This machine is not a domain controller. This script is mean to be run on domain controllers."
    exit 1
}


# Get user with required properties
$user = Get-ADUser $Username -Properties pwdLastSet, msDS-UserPasswordExpiryTimeComputed, PasswordNeverExpires, AccountExpirationDate, MemberOf

Write-Host "Checking user: $Username"

# Initialize $warnings array
$warnings = @()

# 1. Domain Admins membership
$isDomainAdmin = $user.MemberOf -match "CN=Domain Admins,CN=Users,DC="
if ($isDomainAdmin) {
    Write-Host "OK: User IS a member of the Domain Admins group."
}
else {
    $msg = "WARNING: User is NOT a member of the Domain Admins group."
    Write-Host "$msg"
    $warnings += $msg
}

# 2. Enterprise Admins membership  
$isEnterpriseAdmin = $user.MemberOf -match "CN=Enterprise Admins,CN=Users,DC="
if ($isEnterpriseAdmin) {
    Write-Host "OK: User IS a member of the Enterprise Admins group."
}
else {
    $msg = "WARNING: User is NOT a member of the Enterprise Admins group."
    Write-Host "$msg"
    $warnings += $msg
}

# 3. Check that a password change is NOT requred on next logon.
$pwdLastSet = $user.pwdLastSet
$isPwdChangeRequired = ($pwdLastSet -eq 0)
if (-not $isPwdChangeRequired) {
    Write-Host "OK: User is not set to require a password change on next login."
}
else {
    $msg = "WARNING: User IS set to require a password change on next login. Fix this manually now."
    Write-Host "$msg"
    $warnings += $msg
}

# 4. Check that the user's password is set to never expire.
$isPwdNeverExpires = $user.PasswordNeverExpires
if ($isPwdNeverExpires) {
    Write-Host "OK: User password is set to never expire."
}
else {
    $msg = "WARNING: User password is set to expire. Fix this manually now."
    Write-Host "$msg"
    $warnings += $msg
}

# 5. Check that the account is set to never expire.
# AccountExpires = 0 (never) OR 9223372036854775807 (max date/never)
# https://learn.microsoft.com/en-us/windows/win32/adschema/a-accountexpires
$accountExpires = $user.AccountExpirationDate
$isNeverExpires = ($accountExpires -eq 0) -or ($accountExpires -eq 9223372036854775807) -or ($AccountExpires -eq $null)
if ($isNeverExpires) {
    Write-Host "OK: User account is set to never expire."
}
else {
    $msg = "WARNING: User account is set to expire. Fix this manually now."
    Write-Host "$msg"
    $warnings += $msg
}

if ($warnings) {
    Write-Host "CONFIGURATION ERRORS FOUND!"
    Rmm-Alert -Category $alertCategory -Body $msg
}
else {
    Write-Host "No issues found. Configuration is correct."
    Close-Rmm-Alert -Category $alertCategory -CloseAlertTicket "true"
}