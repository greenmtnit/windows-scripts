<#
.SYNOPSIS
    Script to silently upgrade a Windows 10 machine to Windows 11, with optional checks for device type and official support.
    *WARNING* - Automatically reboots the machine when upgrade is complete!
    
.DESCRIPTION
    This script checks if the target machine is already running Windows 11, whether it is a laptop, and if it officially supports Windows 11.
    It allows skipping the laptop check and support check via variables. If all checks pass (or are skipped), it downloads and runs the
    Windows 11 Installation Assistant in silent mode. Optional logging is available.

.NOTES
    This script is intended to be run from the SyncroMSP environment.
    Set the following Syncro script variables:
        $SupportsWindows11
            Syncro custom asset platform variable.
            This is set by the separate script found here: https://github.com/greenmtnit/windows-scripts/blob/main/Check-Windows11Support.ps1

        $SkipOfficialSupportCheck
            Script runtime dropdown, strings "true" or "false" (default).
            Toggles whether to skip checking $SupportsWindows11 for official support.
            If the check is not skipped, the script will not run on machines that are not officialy Windows 11 compatible ($SupportsWindows11 does not equal "Yes").
            
        $SkipLaptopCheck
            Script runtime dropdown, strings "true" or "false" (default).
            Toggles whether to skip checking if the machine is a laptop.
            If the check is not skipped, the script will not run on laptops.
         
        $LogOutput
            Script runtime dropdown, strings "true" (default) or "false".
            Toggles whether to log output to a file.

#>



Import-Module $env:SyncroModule

# VARIABLES
# These should be defined by Syncro, but we add safety definitions here
if (-not $SkipLaptopCheck) { $SkipLaptopCheck = "false" }
if (-not $SkipOfficialSupportCheck) { $SkipOfficialSupportCheck = "false" }

# FUNCTIONS

# Function to check if laptop
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

# START LOGGING (if $LogOutput is set)
if ($LogOutput -eq "true") {
    ## Define the log directory and log file path
    $logDirectory = "C:\!TECH\Windows11UpgradeScriptLogs"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$logDirectory\Windows11Upgrade_$timestamp.txt"

    # Create the log directory if it does not exist
    if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    # Start logging to a transcript
    Start-Transcript -Path $logFile -Append
    Write-Host "Logging output to: $logFile"
}

# CHECKS

## CHECK 1 - Are we already on Windows 11?

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
    if ($LogOutput -eq "true") { Stop-Transcript }
    exit 0
}
else {
    Write-Host "Detected this machine is NOT yet on Windows 11."
}

## CHECK 2 - Is this a laptop?
if (-not ($SkipLaptopCheck -eq "true")) {
    if (Check-Laptop) {
        Write-Host "This is a laptop. Will not run the upgrade. Exiting!"
        if ($LogOutput -eq "true") { Stop-Transcript }
        exit 0
    }
    else {
        Write-Host "Detected this is NOT a laptop."
    }
} else {
    Write-Host "NOTICE: SkipLaptopCheck is set; skipping laptop check."
}

## CHECK 3 - Does this machine support Windows 11?

if (-not ($SkipOfficialSupportCheck -eq "true")) {
    # Read $SupportsWindows11 platform var from Syncro
    if ($SupportsWindows11 -ne "Yes") {
        Write-Host "This machine does not officially support Windows 11. Message: $SupportsWindows11. Exiting!"
        if ($LogOutput -eq "true") { Stop-Transcript }
        exit 0
    }
    else {
        Write-Host "SupportsWindows11 is Yes. This machine does officially support Windows 11."
    }
}
else {
    Write-Host "NOTICE: SkipOfficialSupportCheck is set; skipping Windows 11 official support check."
}

# DO UPGRADE
# If we got here, all checks passed. Proceed with the Windows 11 Upgrade

Write-Host "Proceeding with upgrade!"

# Define the working directory and URL for the Windows 11 Installation Assistant
$workingdir = "C:\temp"
$url = "https://go.microsoft.com/fwlink/?linkid=2171764"
$file = "$($workingdir)\Windows11InstallationAssistant.exe"

# Create the working directory if it does not exist
If (!(Test-Path $workingdir)) {
    New-Item -ItemType Directory -Force -Path $workingdir | Out-Null
}

# Download the Windows 11 Installation Assistant
Write-Host "Downloading Windows 11 Installation Assistant"
try {
    Invoke-WebRequest -Uri $url -OutFile $file -ErrorAction Stop
} catch {
    Write-Host "ERROR: Failed to download Windows 11 Installation Assistant. Exiting!"
    if ($LogOutput -eq "true") { Stop-Transcript }
    exit 1
}
# Run the Windows 11 Installation Assistant with silent install arguments
Write-Host "Starting install!"
Start-Process -FilePath $file -ArgumentList "/QuietInstall /SkipEULA /Auto upgrade /NoRestartUI /copylogs $workingdir"

# END LOGGING
if ($LogOutput -eq "true") {
    Stop-Transcript
}