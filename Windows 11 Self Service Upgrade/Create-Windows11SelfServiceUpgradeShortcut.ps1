<#

Create-Windows11SelfServiceUpgradeShortcut.ps1

Deploys a desktop shortcut to allow users to perform a self-service upgrade to Windows 11.

This PowerShell script performs the following tasks:
1. Creates necessary folder structure under "C:\Program Files\Green Mountain IT Solutions".
2. Downloads a batch script ("Windows11SelfServiceUpgrade.bat") that upgrades a computer to Windows 11. See Github link for that script.
3. Downloads a custom icon file for the shortcut from a publicly accessible URL.
4. Creates a shortcut on the public desktop that points to the batch script, using the downloaded icon.

#>

Import-Module $env:SyncroModule

# CHANGE THESE
$shortcutPath = "C:\Users\Public\Desktop\Windows 11 Self Service Upgrade.lnk"
$batchFilePath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows11SelfServiceUpgrade.bat"
$scriptURL = "https://raw.githubusercontent.com/greenmtnit/windows-scripts/refs/heads/main/Windows%2011%20Self%20Service%20Upgrade/Windows11SelfServiceUpgrade.bat"
$scriptPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows11SelfServiceUpgrade.bat"
$iconURL = "https://s3.us-east-1.wasabisys.com/gmits-public/Windows11Upgrade.ico"
$iconPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows11Upgrade.ico"

if ($SkipAlreadyOn11Check -ne "true") {
    # CHECK IF ALREADY ON 11
    $CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    if ($CurrentVersion.DisplayVersion) {
        $DisplayVersion = $CurrentVersion.DisplayVersion
    } else {
        # 19041 and older do not have DisplayVersion key, if so we grab ReleaseID instead (no longer updated in new versions)
        $DisplayVersion = $CurrentVersion.ReleaseId 
    }

    $Build = $CurrentVersion.CurrentBuildNumber

    if ($Build -ge 22000) { # 22000 and greater are Windows 11
        Write-Host "This machine is already on Windows 11. Exiting!"
        exit 0
    }
}

# CHECK IF WINDOWS 11 IS SUPPORTED - CHECK SYNCRO CUSTOM FIELD
# Read $SupportsWindows11 platform var from Syncro
if ($SupportsWindows11 -ne "Yes") {
  Write-Host "This machine does not officially support Windows 11. Message: $SupportsWindows11. Shortcut will NOT be created. Exiting!"
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

# Download the script
$ProgressPreference = "SilentlyContinue"

Remove-Item $scriptPath -ErrorAction SilentlyContinue # Delete if already exist

Try {
    Write-Host "Downloading Windows11SelfServiceUpgrade.bat..."
    Invoke-WebRequest -Uri $scriptURL -OutFile $scriptPath -ErrorAction Stop
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
$shortcutObject.TargetPath = $batchFilePath
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