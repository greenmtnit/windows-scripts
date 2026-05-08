<#

Install-Windows11Version25H2FromIso.ps1

.SYNOPSIS
    Upgrades Windows to Windows 11, Version 25H2, using a downloaded .iso file.
    This is a good fallback method if other methods, such as the Windows 11 Installation Assistant, fail.
    
    This script should work on lower Windows 11 versions AND also upgrade Windows 10 to Windows 11.
    
    *WARNING* - Automatically reboots the machine when upgrade is complete!
    
.DESCRIPTION
    This script checks if the target machine is already running Windows 11 25H2, whether it is a laptop, and if it officially supports Windows 11.
    It allows skipping the laptop check and support check via variables. If all checks pass (or are skipped), it downloads and runs the Windows 11 25H2 .iso file, extracts the .iso, and then runs the upgrade using the extracted setup.exe . Optional logging is available.

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

    /CopyLogs C:!TECH\Windows11Setup\Logs: Specifies that if the setup fails, Windows Setup logs will be copied to the folder C:!TECH\Windows11Setup\Logs for troubleshooting.

    
    # SYNCRO SETUP
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
            
        #SkipDownload
            Script runtime dropdown, strings "true" or "false" (default).
            Toggles whether to skip downloading the Windows 11 .iso
            Useful if the installer was downloaded previously, i.e. by a previous script run.
         

#>

#Useful references
#https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options?view=windows-11
#https://www.reddit.com/r/sysadmin/comments/ylgedc/windows_11_microsoft_not_supporting_silent_build/

# Function to check if laptop
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

# Function to write to log file
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $entry
    Write-Host $entry
}


# START LOGGING
$logDir = "C:\!TECH\WindowsUpgradeLogs"
$script:LogFile = "$logDir\WindowsIsoUpgrade_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

New-Item -ItemType Directory $logDir
New-Item $script:LogFile

# CHECKS

# Is this a laptop?
if (-not ($SkipLaptopCheck -eq "true")) {
    if (Check-Laptop) {
        Write-Log -Level WARN -Message "This is a laptop. Will not run the upgrade. Exiting!"
        exit 0
    }
    else {
        Write-Log "Detected this is NOT a laptop. Proceeding"
    }
} else {
    Write-Log "SkipLaptopCheck is set; skipping laptop check."
}

# Are we at 25H2 already? If so, bail from script.
If ((Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion').DisplayVersion -eq '25H2') {
    Write-Log 'Host is already running version 25H2; no Update required - exiting.'
    exit
}

# Does this machine support Windows 11?
if (-not ($SkipOfficialSupportCheck -eq "true")) {
    # Read $SupportsWindows11 platform var from Syncro
    if ($SupportsWindows11 -ne "Yes") {
        Write-Log -Level WARN -Message "This machine does not officially support Windows 11. Message: $SupportsWindows11. Exiting!"
        exit 0
    }
    else {
        Write-Log "SupportsWindows11 is Yes. This machine does officially support Windows 11."
    }
}
else {
    Write-Log "NOTICE: SkipOfficialSupportCheck is set; skipping Windows 11 official support check."
}

# Make sure at least 20GB are free
$driveLetter = "C:"
$disk = Get-CimInstance -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $driveLetter }
$freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    
if ($freeSpaceGB -lt 20) {
    Write-Log -Level ERROR -Message "Available disk space on drive $driveLetter is less than 20GB ($freeSpaceGB GB). Will not proceed. Exiting!"
    Exit 1
} 

# DO UPGRADE
# If we got here, all checks passed. Proceed with the Windows 11 Upgrade

Write-Log "Proceeding with upgrade!"

# Create the C:\!TECH directory if it doesn't exist
if (!(Test-Path -Path "C:\!TECH" -PathType Container)) {
    New-Item -Path "C:\!TECH" -ItemType Directory
}

# Create the Windows11Setup directory if it doesn't exist
if (!(Test-Path C:\!TECH\\Windows11Setup)) {
    New-Item -ItemType Directory -Path "C:\!TECH\Windows11Setup"
}

# Create the Logs directory if it doesn't exist
if (!(Test-Path C:\!TECH\\Windows11Setup\Logs)) {
    New-Item -ItemType Directory -Path "C:\!TECH\Windows11Setup\Logs"
}

# 
if ($SkipDownload -eq "true") {
    Write-Log -Level WARN -Message "SkipDownload is set; skipping downloading .iso."
    
    $setupPath = "C:\!TECH\\Windows11Setup\Setup.exe"
    
    if (-Not (Test-Path $setupPath)) {
        Write-Log -Level ERROR -Message "Setup file not found!"
        Write-Log -Level ERROR -Message "SkipDownload was set, but the installer does not appear to have been downloaded previously."
        exit 1
    }

}

else {
    # Download the .iso and extract its contents
    
    # Define the download URI and paths

    $URI = "https://greenmtnitsolutions.egnyte.com/dd/ykGqRHkJp9V3"
    $DownloadPath = "C:\!TECH\Windows11Setup\Windows11_25H2.iso"

    # Download the .iso
    # Set ProgressPreference to avoid slowdown from displaying progress
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $URI -OutFile $DownloadPath

    # Mount the downloaded disk image
    $mountResult = Mount-DiskImage -ImagePath $DownloadPath
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $ExtractPath = $driveLetter + ":\*"

    # Copy the contents of the mounted image to the Windows11Setup directory
    Copy-Item -Path "$ExtractPath" -Destination "C:\!TECH\Windows11Setup\" -Recurse -Force

    # Dismount the disk image
    Dismount-DiskImage -ImagePath $DownloadPath

    # Remove the downloaded ISO file
    Remove-Item "C:\!TECH\Windows11Setup\Windows11_25H2.iso" -Force

}

# Check if device is a laptop or desktop
$ArgumentList = "/Eula Accept /Auto Upgrade /Quiet /MigrateDrivers all /DynamicUpdate Disable /Telemetry disable /Compat IgnoreWarning /ShowOOBE none /CopyLogs C:\!TECH\Windows11Setup\Logs"

# Start the upgrade Process
Write-Log "Starting upgrade!"
Start-Process -Wait -FilePath "C:\!TECH\Windows11Setup\setup.exe" -ArgumentList $ArgumentList