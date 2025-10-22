<#

Install-Windows11Version24H2FromIso_LAPTOP_VERSION.ps1

.SYNOPSIS
    Upgrades Windows to Windows 11, Version 24H2, using a downloaded .iso file.
    
    This version is defined for laptops. It does not force a reboot. The feature update will proceed on the next reboot.
    
    This script should work on lower Windows 11 versions AND also upgrade Windows 10 to Windows 11.
        
.DESCRIPTION
    This script checks if the target machine is already running Windows 11 24H2. If all checks pass (or are skipped), it downloads and runs the Windows 11 24H2 .iso file, extracts the .iso, and then runs the upgrade using the extracted setup.exe . Optional logging is available.

.NOTES
    # SETUP.EXE ARGUMENTS
    # https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options
    
    /EULA Accept: Automatically accepts the Windows Setup end user license agreement (EULA), which is required starting with Windows 11 before the installation begins.

    /Auto Upgrade: Performs an automated upgrade of Windows, saving apps and data. This option disables the use of an unattend file and requires compatibility checks before installation.

    /Quiet: Suppresses any Windows Setup user interface, including error messages and rollback UI, allowing the setup to run silently.

    /MigrateDrivers all: Instructs Windows Setup to migrate all existing device drivers from the current installation to the upgraded installation.

    /DynamicUpdate Disable: Prevents Windows Setup from searching for, downloading, or installing updates during the setup process.

    /Telemetry disable: Disables the capture and reporting of installation telemetry data during Windows Setup.

    /Compat IgnoreWarning: Instructs Windows Setup to complete the installation regardless of any dismissible compatibility warnings that are detected.

    /ShowOOBE none: Skips the out-of-box experience (OOBE) by selecting the default settings, so the user is not prompted to interactively complete OOBE.
    
    /Priority Low: Runs the setup process with low thread priority, reducing the impact on system responsiveness during the upgrade process.

    /NoReboot: Prevents Windows Setup from automatically rebooting the computer after the installation phase is complete. Note this only suppresses the first reboot; subsequent reboots may still occur.

    /CopyLogs C:!TECH\Windows11Setup\Logs: Specifies that if the setup fails, Windows Setup logs will be copied to the folder C:!TECH\Windows11Setup\Logs for troubleshooting.

    
    # SYNCRO SETUP
    This script is intended to be run from the SyncroMSP environment.
    Set the following Syncro script variables:
        
        #SkipDownload
            Script runtime dropdown, strings "true" or "false" (default).
            When true, will skip downloading the Windows 11 24H2 .iso if already downloaded. If not previously downloaded, this parameter has no effect.
            When false, download will be forced regardless of whether the files were downloaded previously.
            
        $LogOutput
            Script runtime dropdown, strings "true" (default) or "false".
            Toggles whether to log output to a file.

#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

#Useful references
#https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options?view=windows-11
#https://www.reddit.com/r/sysadmin/comments/ylgedc/windows_11_microsoft_not_supporting_silent_build/

# Function to check if laptop
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

function Download-Iso {
    # Download the .iso and extract its contents
    
    # Define the download URI and paths

    $URI = "https://greenmtnitsolutions.egnyte.com/dd/76TbWJkFqBVX/"
    $DownloadPath = "C:\!TECH\Windows11_24H2_Setup\Windows11_24H2.iso"

    # Download the .iso
    # Set ProgressPreference to avoid slowdown from displaying progress
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $URI -OutFile $DownloadPath

    # Mount the downloaded disk image
    $mountResult = Mount-DiskImage -ImagePath $DownloadPath
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $ExtractPath = $driveLetter + ":\*"

    # Copy the contents of the mounted image to the Windows11Setup directory
    Copy-Item -Path "$ExtractPath" -Destination "C:\!TECH\Windows11_24H2_Setup\" -Recurse -Force

    # Dismount the disk image
    Dismount-DiskImage -ImagePath $DownloadPath

    # Remove the downloaded ISO file
    Remove-Item "C:\!TECH\Windows11_24H2_Setup\Windows11_24H2.iso" -Force
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

# Log to Syncro Activity Monitor (if running in Syncro)
if ($null -ne $env:SyncroModule) { 
    Log-Activity -Message "Script started 24H2 Upgrade" -EventName "FeatureUpdate"
}

# CHECKS

# Is this a laptop?
if (-not (Check-Laptop)) {
    Write-Host "NOTICE: This version of the script is meant to run on laptops. Will not run the upgrade. Exiting!"
    if ($LogOutput -eq "true") { Stop-Transcript }
    exit 0
}

# Are we at 24H2 already? If so, bail from script.
If ((Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion').DisplayVersion -eq '24H2') {
    Write-Output 'Host is already running version 24H2; no Update required - exiting.'
    exit
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

# Create the C:\!TECH directory if it doesn't exist
if (!(Test-Path -Path "C:\!TECH" -PathType Container)) {
    New-Item -Path "C:\!TECH" -ItemType Directory
}

# Create the Windows11Setup directory if it doesn't exist
if (!(Test-Path C:\!TECH\Windows11_24H2_Setup)) {
    New-Item -ItemType Directory -Path "C:\!TECH\Windows11_24H2_Setup"
}

# Create the Logs directory if it doesn't exist
if (!(Test-Path C:\!TECH\Windows11_24H2_Setup\Logs)) {
    New-Item -ItemType Directory -Path "C:\!TECH\Windows11_24H2_Setup\Logs"
}

# 
if ($SkipDownload -eq "true") {
    Write-Host "NOTICE: SkipDownload is set; will skip downloading .iso if setup files are already present."
    
    $setupPath = "C:\!TECH\Windows11_24H2_Setup\Setup.exe"
    
    if (-Not (Test-Path $setupPath)) {
        Write-Host "Setup file not found!"
        Write-Host "ERROR: SkipDownload was set, but the installer does not appear to have been downloaded previously. Will attempt to download."
        Download-Iso
    }
}

else {
    Write-Host "NOTICE: SkipDownload is set to false. Forcing download."
    Download-Iso
}

# Define arguments
$ArgumentList = "/Eula Accept /Auto Upgrade /Quiet /MigrateDrivers all /DynamicUpdate Disable /Telemetry disable /Compat IgnoreWarning /ShowOOBE none /Priority Low /NoReboot /CopyLogs C:\!TECH\Windows11_24H2_Setup\Logs"

# Start the upgrade Process
Write-Host "Starting upgrade!"
Start-Process -Wait -FilePath "C:\!TECH\Windows11_24H2_Setup\setup.exe" -ArgumentList $ArgumentList

# END LOGGING
if ($LogOutput -eq "true") {
    Stop-Transcript
}