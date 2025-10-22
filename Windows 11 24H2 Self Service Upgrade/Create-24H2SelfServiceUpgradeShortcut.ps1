<#

Create-Windows11SelfServiceUpgradeShortcut.ps1

Deploys a desktop shortcut to allow users to perform a self-service upgrade to Windows 11 version 24H2.

This PowerShell script performs the following tasks:
1. Creates necessary folder structure under "C:\Program Files\Green Mountain IT Solutions".
2. Downloads a batch script ("Windows24H2SelfServiceUpgrade.bat") that upgrades a computer to Windows 11. See Github link for that script.
3. Downloads a custom icon file for the shortcut from a publicly accessible URL.
4. Creates a shortcut on the public desktop that points to the batch script, using the downloaded icon.

#>

Import-Module $env:SyncroModule

# CHANGE THESE
# TODO
$shortcutPath = "C:\Users\Public\Desktop\Windows 11 24H2 Self Service Upgrade.lnk"
$batchFilePath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows24H2SelfServiceUpgrade.bat"
$scriptURL = "https://raw.githubusercontent.com/greenmtnit/windows-scripts/refs/heads/main/Windows%2011%20Self%20Service%20Upgrade/Windows11SelfServiceUpgrade.bat"
$scriptPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows24H2SelfServiceUpgrade.bat"
$iconURL = "https://s3.us-east-1.wasabisys.com/gmits-public/Windows11Upgrade.ico"
$iconPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows11Upgrade.ico"

    # CHECK IF ALREADY ON 24H2
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