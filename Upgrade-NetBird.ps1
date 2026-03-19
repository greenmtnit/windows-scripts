<#
    Upgrade-NetBird.ps1
    
    https://greenmtnit.huducloud.com/kba/f6ac6b618a4c
    
    Updates NetBird Windows software to the latest version, using Chocolatey.
    Makes sure NetBird is connected after upgrade.
    
    Prerequesities:
    NetBird must have been installed using Chocolatey. 
    If this is not the case, uninstall NetBird, choosing the option to keep the Configuration.
    Then install NetBird with Chocolatey: choco install netbird
    Your configuration should be preserved.
    
#>

$packageName = "netbird"
$syncroPath  = "$env:ProgramFiles\RepairTech\Syncro\kabuto_app_manager\choco.exe"
$chocoPath   = "$env:ProgramData\chocolatey\choco.exe"

# ── Logging setup ─────────────────────────────────────────────────────────────
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile    = "$env:TEMP\Upgrade-NetBird_$timestamp.log"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "Log file: $logFile"

# ── 1. Locate / install Chocolatey ────────────────────────────────────────────
try {
    if (Test-Path -Path $syncroPath) {
        Write-Log "Found Chocolatey from Syncro, using it."
        $choco = $syncroPath
    }
    elseif (Test-Path -Path $chocoPath) {
        Write-Log "Found Chocolatey in its default location, using it."
        $choco = $chocoPath
    }
    else {
        Write-Log "Chocolatey not found, installing it..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
        $choco = $chocoPath
    }
    # ── 2. Upgrade NetBird (unattended) ───────────────────────────────────────
    Write-Log "Upgrading $packageName..."
    & "$choco" upgrade $packageName -y
    
    Write-Log "$packageName upgrade completed."
}
catch {
    Write-Log "Error during Chocolatey upgrade: $_"
    exit 1
}
# ── 3. Run "netbird up" ───────────────────────────────────────────────────────
$netbirdExe = "$env:ProgramFiles\NetBird\netbird.exe"
if (-not (Test-Path $netbirdExe)) {
    Write-Log "ERROR: netbird.exe not found. Cannot run 'netbird up'."
    exit 1
}
Write-Log "Running 'netbird up'..."
try {
    & "$netbirdExe" up
    Write-Log "SUCCESS: 'netbird up' completed."
    exit 0
}
catch {
    Write-Log "ERROR running 'netbird up': $_"
    exit 1
}