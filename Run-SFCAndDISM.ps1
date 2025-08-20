<#
  Run-SFCAndDISM.ps1
  
  Runs DISM and SFC commands to check for and repair Windows system files.
  Logs output to a file, and if running in Syncro, uploads the log file to the Syncro asset page.
    
#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

# Start logging
# Define the log directory and log file path
$logDirectory = "C:\!TECH"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$logDirectory\SFC_DISM_log_$timestamp.txt"

# Create the log directory if it does not exist
if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

# Start logging to a transcript
Write-Host "Logging output to: $logFile"

# Run DISM and SFC

# DISM Commands
# Checks if the Windows image has any corruption or issues (quick check)
dism /Online /Cleanup-Image /CheckHealth           | Tee-Object -FilePath "$logFile" -Append
# Performs a deeper scan to detect corruption in the Windows image
dism /Online /Cleanup-Image /ScanHealth            | Tee-Object -FilePath "$logFile" -Append
# Cleans up and removes unnecessary files from the Component Store to free disk space
dism /Online /Cleanup-Image /StartComponentCleanup | Tee-Object -FilePath "$logFile" -Append
# Repairs the Windows image by fixing detected corruption using Windows Update or a source
dism /Online /Cleanup-Image /RestoreHealth         | Tee-Object -FilePath "$logFile" -Append

# SFC command
# SFC.exe outputs in Unicode, so change the output encoding before running it in PowerShell:
$oldEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::Unicode
# Scans all protected system files and repairs corrupted or missing ones using the repaired image
sfc /scannow | Tee-Object -FilePath "$logFile" -Append
# Revert to old logging
[Console]::OutputEncoding = $oldEncoding                                   

# If running in Syncro, upload the log file to the Syncro asset page
if ($null -ne $env:SyncroModule) {
    Write-Host "Uploading log file to Syncro asset page"
    Upload-File -FilePath $logFile
}