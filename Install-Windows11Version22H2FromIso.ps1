<#

Install-Windows11Version22H2FromIso.ps1

.SYNOPSIS
    Upgrades Windows to Windows 11, Version 22H2, using a downloaded .iso file.
    This is a good fallback method if other methods, such as the Windows 11 Installation Assistant, fail.
    
    This script should work on lower Windows 11 versions AND also upgrade Windows 10 to Windows 11.
    
    *WARNING* - Automatically reboots the machine when upgrade is complete!
    
.DESCRIPTION
    This script checks if the target machine is already running Windows 11 22H2, whether it is a laptop, and if it officially supports Windows 11.
    It allows skipping the laptop check and support check via variables. If all checks pass (or are skipped), it downloads and runs the Windows 11 22H2 .iso file, extracts the .iso, and then runs the upgrade using the extracted setup.exe . Optional logging is available.

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

#Useful references
#https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options?view=windows-11
#https://www.reddit.com/r/sysadmin/comments/ylgedc/windows_11_microsoft_not_supporting_silent_build/

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

# Is this a laptop?
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

# Are we at 22H2 already? If so, bail from script.
If ((Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion').DisplayVersion -eq '22H2') {
    Write-Output 'Host is already running version 22H2; no Feature Update required - exiting.'
    exit
}

# Does this machine support Windows 11?
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

# Make sure at least 20GB are free
$driveLetter = "C:"
$disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $driveLetter }
$freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    
if ($freeSpaceGB -lt 20) {
    Write-Host "Available disk space on drive $driveLetter is less than 20GB ($freeSpaceGB GB). Will not proceed. Exiting!"
    Exit 1
} 

# DO UPGRADE
# If we got here, all checks passed. Proceed with the Windows 11 Upgrade

Write-Host "Proceeding with upgrade!"

# Create the C:\!TECH directory if it doesn't exist~
if (!(Test-Path -Path "C:\!TECH" -PathType Container)) {
    New-Item -Path "C:\!TECH" -ItemType Directory
}

# Create the WindowsSetup directory if it doesn't exist
if (!(Test-Path C:\!TECH\\WindowsSetup)) {
    New-Item -ItemType Directory -Path "C:\!TECH\WindowsSetup"
}

# Create the Logs directory if it doesn't exist
if (!(Test-Path C:\!TECH\\WindowsSetup\Logs)) {
    New-Item -ItemType Directory -Path "C:\!TECH\WindowsSetup\Logs"
}

# Define the download URI and paths

$URI = "https://greenmtnitsolutions.egnyte.com/dd/76TbWJkFqBVX/"
$DownloadPath = "C:\!TECH\WindowsSetup\Windows11_22H2.iso"

# Download the .iso
# Set ProgressPreference to avoid slowdown from displaying progress
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest -Uri $URI -OutFile $DownloadPath

# Mount the downloaded disk image
$mountResult = Mount-DiskImage -ImagePath $DownloadPath
$driveLetter = ($mountResult | Get-Volume).DriveLetter
$ExtractPath = $driveLetter + ":\*"

# Copy the contents of the mounted image to the WindowsSetup directory
Copy-Item -Path "$ExtractPath" -Destination "C:\!TECH\WindowsSetup\" -Recurse -Force

# Dismount the disk image
Dismount-DiskImage -ImagePath $DownloadPath

# Remove the downloaded ISO file
Remove-Item "C:\!TECH\WindowsSetup\Windows11_22H2.iso" -Force

# Check if device is a laptop or desktop
$ArgumentList = "/Eula Accept /Auto Upgrade /Quiet /MigrateDrivers all /DynamicUpdate Disable /Telemetry disable /compat IgnoreWarning /ShowOOBE none /copylogs C:\!TECH\WindowsSetup\Logs"

# Start the upgrade Process
Write-Host "Starting upgrade!"
Start-Process -Wait -FilePath "C:\!TECH\WindowsSetup\setup.exe" -ArgumentList $ArgumentList

if (!(Test-IsLaptop)){
    Start-Sleep -Seconds 10
    Restart-Computer
}

# END LOGGING
if ($LogOutput -eq "true") {
    Stop-Transcript
}