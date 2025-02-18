<#
.SYNOPSIS
Creates a local user, then shares a folder and grants share and NTFS permissions so the new user can access it.
Typically used for creating a shared folder for scan-to-folder.

.DESCRIPTION
This script performs the following actions:
1. Creates a local user with a random password
2. Hides the user from the login screen.
2. Sets NTFS permissions on a specified folder, granting the new user access
3. Creates an SMB share for the specified folder, granting change access for Everyone

.EXAMPLE
.\Create-ps1

.NOTES
File Name      : Create-ScanToFolderSetup
Author         : Timothy West
#>

# ===========================================
#  Functions
# ===========================================

# Function to get a random password using password.ninja website API
function Get-NinjaPassword {
    param (
        [int]$Quantity = 1
    )

    $passwords = @()
    for ($i = 0; $i -lt $Quantity; $i++) {
        $password = ((Invoke-WebRequest -Uri "https://password.ninja/api/password?minPassLength=12&capitals=true&symbols=true&excludeSymbols=pf").Content).Trim('"')
        $passwords += $password
    }

    return $passwords
}

# ===========================================
#  Variables
# ===========================================    
$hostname = $env:COMPUTERNAME
$username = "scans"
$fullName = "Scan user"
$description = "Local user account for scan-to-folder"
$shareName = "Scans"

# Read share path from Syncro if running in Syncro; otherwise, define it locally
if ($null -ne $env:SyncroModule) {
    Import-Module $env:SyncroModule -DisableNameChecking
}
else {
    $sharePath = "C:\Path\To\Share"
}

# ===========================================
#  Local User Creation
# ===========================================    

if (Get-LocalUser $username) {
    Write-Host "User $username already exists!"
    exit 1
}

# Generate a random password
$password = Get-NinjaPassword

# Workaround for local user issue in PowerShell - https://github.com/PowerShell/PowerShell/issues/18624
Import-Module Microsoft.Powershell.LocalAccounts -UseWindowsPowerShell

# Create the local user
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
New-LocalUser -Name $username -Password $securePassword -FullName $fullName -Description $description -AccountNeverExpires -PasswordNeverExpires:$true

# Output the username and password
Write-Host "User $hostname\$username created successfully."
Write-Host "Password: $password"

# ===========================================
#  Set NTFS Permissions
# ===========================================

#Create folder if not exist
if (-Not (Test-Path $sharePath)) {
  New-Item -Path $sharePath -ItemType Directory
}

# Set NTFS permissions
$identity = "$hostname\$username"
$rights = [System.Security.AccessControl.FileSystemRights]"DeleteSubdirectoriesAndFiles, Modify, Synchronize"
$type = [System.Security.AccessControl.AccessControlType]::Allow

$acl = Get-Acl $sharePath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $type)
$acl.AddAccessRule($rule)
Set-Acl -Path $sharePath -AclObject $acl

# ===========================================
#  Create Share
# ===========================================    
#Create the share and set permissions
New-SmbShare -Name $shareName -Path $sharePath -ChangeAccess "Everyone" | Out-Null

