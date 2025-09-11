
<#
  Uninstall-SentinelOne.ps1
  
  Uninstalls SentinelOne. Useful when other uninstall methods (e.g. console-initiated) aren't working, and the S1 agent is broken or corrupted.
  
  Obtain and pass in the SentinelOne Site token from the Packages tab in the S1 console.
    
  S1SiteToken should be added as a variable in SyncroMSP scripting (or equivalent RMM feature).
  
#>
if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

## Define the log directory and log file path
$logDirectory = "C:\!TECH\SentinelOneUninstall" # change name if desired
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$logDirectory\MyScriptName_$timestamp.txt"

# Create the log directory if it does not exist
if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

# Start logging to a transcript
Start-Transcript -Path $logFile -Append
Write-Host "Logging output to: $logFile"

# Download file
$S1InstallerURL = "https://s3.us-east-1.wasabisys.com/gmits-public/sentinelone_windows_latest.exe"
$S1DownloadPath = "C:\Windows\Temp\sentinelone_windows_latest.exe"

Try {
    Write-Host "Downloading SentinelOne Installer .exe ..."
    $ProgressPreference = 'SilentlyContinue' # Speeds downloads by hiding progress bar
    Invoke-WebRequest -Uri $S1InstallerURL -OutFile $S1DownloadPath -ErrorAction Stop
} Catch {
    Write-Host "ERROR: Failed to download the file."
    Write-Host $_.Exception.Message
    Exit 1
}

# Do Uninstall
& "C:\Windows\Temp\sentinelone_windows_latest.exe" -q -c -t $S1SiteToken

# Stop logging
Stop-Transcript
