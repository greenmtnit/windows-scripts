<#
     Uninstall-AutoElevate.ps1
    
     Uninstalls AutoElevate using MSI and verifies removal.
https://support.cyberfox.com/115000883892-New-to-AutoElevate-START-HERE/115003703811-System-Agent-Installation#scripted-un-installation-10

    - Downloads the uninstaller from:
      https://autoelevate-installers.s3.us-east-2.amazonaws.com/current/AESetup.msi
    - Executes:
      msiexec /uninstall AESetup.msi /quiet /lv AEInstallLog.log
    - Checks whether the "AutoElevateAgent" service still exists.
    - Exits with code 0 on success, non-zero on failure.

#>

$DownloadUrl = 'https://autoelevate-installers.s3.us-east-2.amazonaws.com/current/AESetup.msi'
$DownloadDir = 'C:\Windows\Temp'
$MsiPath     = Join-Path $DownloadDir 'AESetup.msi'
$LogPath     = Join-Path $DownloadDir 'AEUninstallLog.log'
$ServiceName = 'AutoElevateAgent'

# Logging helper functions
function Write-Info($Message)  { Write-Host "[INFO]  $Message"  -ForegroundColor Cyan }
function Write-Warn($Message)  { Write-Host "[WARN]  $Message"  -ForegroundColor Yellow }
function Write-ErrorMsg($Message){ Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Download MSI
try {
    Write-Info "Downloading uninstaller MSI..."
    # Use BITS if available; otherwise fall back to Invoke-WebRequest
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $DownloadUrl -Destination $MsiPath -DisplayName "AutoElevate Uninstaller"
    } else {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing
    }

    if (-not (Test-Path -LiteralPath $MsiPath)) {
        throw "Download failed: $MsiPath not found."
    }

    $fileInfo = Get-Item -LiteralPath $MsiPath
    if ($fileInfo.Length -lt 10240) { # sanity check: at least 10 KB
        throw "Downloaded MSI appears too small ($([math]::Round($fileInfo.Length/1KB,2)) KB)."
    }

    Write-Info "Downloaded MSI to: $MsiPath (Size: $([math]::Round($fileInfo.Length/1MB,2)) MB)"
}
catch {
    Write-ErrorMsg "Failed to download MSI. $_"
    exit 3
}

# Run MSI Uninstall
try {
    Write-Info "Starting silent uninstall. Logging to: $LogPath"
    $msiArgs = "/uninstall `"$MsiPath`" /quiet /lv `"$LogPath`""
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -PassThru -Wait -WindowStyle Hidden

    # If Start-Process doesn't return an ExitCode reliably, query it
    $exitCode = $proc.ExitCode
    Write-Info "msiexec exit code: $exitCode"

    # Common msiexec exit codes (0=success, 3010=reboot required)
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        Write-Warn "Uninstall returned non-success code $exitCode. See log: $LogPath"
    }
}
catch {
    Write-ErrorMsg "Uninstall process failed to start or complete. $_"
    exit 4
}

# Verify service removal
try {
    Start-Sleep -Seconds 10  # brief pause to allow service cleanup
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($null -eq $svc) {
        Write-Host "[SUCCESS] Uninstall verification passed. Service '$ServiceName' not found." -ForegroundColor Green
        exit 0
    } else {
        Write-Warn "Service '$ServiceName' still exists with status: $($svc.Status). Uninstall may not have fully completed."
        Write-Warn "Check the log for details: $LogPath"
        exit 5
    }
}
catch {
    Write-ErrorMsg "Error checking service state. $_"
    Write-Warn "Review uninstall log: $LogPath"
    exit 6
}