# Syncro Installer Script
# This script installs the Syncro RMM agent if it's not already installed on the system.
# It requires a Customer ID and Folder ID, which can be retrieved from the client's Syncro policy page.
# The script also supports a Debug mode for troubleshooting.

param (
    [string]$CustomerID,  # Unique identifier for the customer in Syncro
    [string]$FolderID,    # Folder ID for the Syncro agent installation
    [switch]$Debug        # Enables debug mode to print additional logs
)

# Example Usage:
# PowerShell:
#   .\SyncroInstaller.ps1 -CustomerID "123456" -FolderID "789123"
# With Debug Mode:
#   .\SyncroInstaller.ps1 -CustomerID "123456" -FolderID "789123" -Debug
# Intune Win32 App Usage
# %windir%\SysNative\WindowsPowershell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File  .\Install-Syncro.ps1 -CustomerID "1569462" -FolderID "4261465"

# Ensure required parameters are provided before proceeding
if (-not $CustomerID -or -not $FolderID) {
    Write-Host "Error: CustomerID and FolderID must be provided." -ForegroundColor Red
    exit 1
}

# Debug Mode: Display the provided parameters and enable logging
if ($Debug) {
    ## Define the log directory and log file path
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$env:Public\SyncroInstallLog_$timestamp.txt"
    # Start logging to a transcript
    Start-Transcript -Path $logFile -Append
    Write-Host "Logging output to: $logFile"
    
    Write-Output "Using CustomerID: $CustomerID"
    Write-Output "Using FolderID: $FolderID"
}

# Define paths and URLs for the Syncro installer
$syncroInstallerPath = 'C:\ProgramData\Syncro\bin\Syncro.Overmind.Service.exe' # Path where Syncro is installed
$syncroInstallerUri = 'https://rmm.syncromsp.com/dl/rs/djEtMzEyODAxOTAtMTczOTgxODAxMi00ODEwNS0zNzA1MjI3' # Syncro installer download URL
$syncroSetupPath = "$env:TEMP\SyncroSetup-GreenMountainITSolutions.exe" # Temporary path for the downloaded installer

# Check if Syncro is already installed
if (-not (Test-Path -Path $syncroInstallerPath -PathType Leaf)) {
    # Disable progress UI to speed up downloads
    $ProgressPreference = 'SilentlyContinue'

    try {
        # Download the Syncro installer from the official Syncro URL
        Invoke-WebRequest -Uri $syncroInstallerUri -OutFile $syncroSetupPath

        # Execute the Syncro installer with customer-specific arguments
        Start-Process -FilePath $syncroSetupPath -ArgumentList "--console --customerid $CustomerID --folderid $FolderID" -Wait
    }
    catch {
        # Error handling in case the download or installation fails
        if ($Debug) { 
            Write-Host "Installation failed: $_"
            Write-Host "Also see Syncro logs at C:\ProgramData\Syncro\Logs"
        }
    }
} 
else {
    # If Syncro is already installed, notify the user (only in Debug mode)
    if ($Debug) { Write-Host "Syncro is already installed. Exiting."}
}

if ($Debug) {
    Stop-Transcript
}