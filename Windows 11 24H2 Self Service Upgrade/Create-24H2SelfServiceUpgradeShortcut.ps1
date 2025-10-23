<#

Create-24H2SelfServiceUpgradeShortcut.ps1

Deploys a desktop shortcut to allow users to perform a self-service upgrade to Windows 11 version 24H2.

Currently, will only be deployed on laptops.

This PowerShell script performs the following tasks:
- Check if the system is a laptop and if not, exits.
- Checks if the system is already on Windows 11 version 24H2
- Creates necessary folder structure under "C:\Program Files\Green Mountain IT Solutions".
- Downloads a batch script ("Windows24H2SelfServiceUpgrade.bat") that upgrades a computer to Windows 11 Version 24H2. See Github link for that script.
- Downloads a custom icon file for the shortcut from a publicly accessible URL.
- Creates a shortcut on the public desktop that points to the batch script, using the downloaded icon.

#>

Import-Module $env:SyncroModule

# FUNCTIONS
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

# VARIABLES - CHANGE THESE
$shortcutPath = "C:\Users\Public\Desktop\Self Service Upgrade.lnk"
$scriptURL = "https://raw.githubusercontent.com/greenmtnit/windows-scripts/refs/heads/main/Windows%2011%2024H2%20Self%20Service%20Upgrade/Windows24H2SelfServiceUpgrade.bat"
$batchScriptPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows24H2SelfServiceUpgrade.bat"
$iconURL = "https://s3.us-east-1.wasabisys.com/gmits-public/Windows11Upgrade.ico"
$iconPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\WindowsUpgrade.ico"

# MAIN SCRIPT ACTION
if (-not (Check-Laptop)) {
    Write-Host "This system is NOT a laptop. The script will only execute on laptops. Exiting."
    exit 0
}

# Check if already on 24H2
$CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
if ($CurrentVersion.DisplayVersion) {
    $DisplayVersion = $CurrentVersion.DisplayVersion
} else {
    # 19041 and older do not have DisplayVersion key, if so we grab ReleaseID instead (no longer updated in new versions)
    $DisplayVersion = $CurrentVersion.ReleaseId 
}

$Build = $CurrentVersion.CurrentBuildNumber

if ($Build -ge 26100) { # 26100 is 24H2
    Write-Host "This machine is already on Windows 11 version 24H2. Exiting!"
    exit 0
}

# Create working directories
$baseDirectory = "C:\Program Files\Green Mountain IT Solutions"
$scriptsDirectory = Join-Path -Path $baseDirectory -ChildPath "Scripts"
$workingDirectory = Join-Path -Path $baseDirectory -ChildPath "RMM"
$toolsDirectory = Join-Path -Path $workingDirectory -ChildPath "Tools"

$directories = @($baseDirectory, $scriptsDirectory, $workingDirectory, $toolsDirectory)

foreach ($dir in $directories) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# Download the batch script
$ProgressPreference = "SilentlyContinue"

Remove-Item $batchScriptPath -ErrorAction SilentlyContinue # Delete if already exist

Try {
    Write-Host "Downloading Windows24H2SelfServiceUpgrade.bat..."
    Invoke-WebRequest -Uri $scriptURL -OutFile $batchScriptPath -ErrorAction Stop
} Catch {
    Write-Host "ERROR: Failed to download the file."
    Write-Host $_.Exception.Message
    Exit 1
}

# Download icon file
Remove-Item $iconPath -ErrorAction SilentlyContinue # Delete if already exist

Try {
    Write-Host "Downloading shortcut icon..."
    Invoke-WebRequest -Uri $iconURL -OutFile $iconPath -ErrorAction Stop
} Catch {
    Write-Host "ERROR: Failed to download the file."
    Write-Host $_.Exception.Message
    Exit 1
}

# Check if shortcut already exists
if (Test-Path -Path $shortcutPath) {
    Write-Host "Shortcut already exists at $shortcutPath. Overwriting..."
    Remove-Item -Path $shortcutPath -Force
}

# Create the shortcut pointing to the batch script
$WshShell = New-Object -ComObject WScript.Shell
$shortcutObject = $WshShell.CreateShortcut($shortcutPath)
$shortcutObject.TargetPath = $batchScriptPath
$shortcutObject.IconLocation = $iconPath
$shortcutObject.WorkingDirectory = $scriptsDirectory
$shortcutObject.Save()

# Change permissions to allow deletion
$acl = Get-Acl -Path $shortcutPath
$readRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Read", "Allow")
$deleteRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Delete", "Allow")
$acl.AddAccessRule($readRule)
$acl.AddAccessRule($deleteRule)
Set-Acl -Path $shortcutPath -AclObject $acl