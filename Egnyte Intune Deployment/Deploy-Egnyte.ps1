param (
    [switch]$LogOutput,  # Log to a file
    [switch]$Verbose     # Print extra messages
)

# Logging setup
if ($LogOutput) {
    ## Define the log directory and log file path
    $logDirectory = "C:\Windows\Temp\egnyte_deployment"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$logDirectory\egnyte_deployment_$timestamp.log"

    # Create the log directory if it does not exist
    if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    # Start logging to a transcript
    Start-Transcript -Path $logFile -Append
    Write-Host "Logging output to: $logFile"
}

function Write-VerboseMessage {
    param (
        [string]$Message
    )

    if ($Verbose) {
        Write-Host $Message
    }
}

# Define paths for MSI and config files
$msiUrl = "https://egnyte-cdn.egnyte.com/egnytedrive/win/en-us/latest/EgnyteConnectWin.msi"
$msiFilePath = Join-Path $PSScriptRoot "EgnyteDrive.msi"

# Define path to .json config file. 
# If packaging into a .intunewin file, include the config.json in the source
$configSourceFile = Join-Path $PSScriptRoot "config.json"
$configDestinationDir = "C:\Program Files (x86)\Egnyte Connect\"
$configDestinationFile = "$configDestinationDir\defaultMassDeploymentConfig.json"

Write-VerboseMessage "Using config file: $configSourceFile"

# Ensure the destination directory exists
if (!(Test-Path -Path $configDestinationDir)) {
    Write-VerboseMessage "Creating directory: $configDestinationDir"
    New-Item -ItemType Directory -Path $configDestinationDir -Force | Out-Null
} else {
    Write-VerboseMessage "Directory already exists: $configDestinationDir"
}

# Copy config.json to the destination directory as defaultMassDeploymentConfig.json
if (Test-Path -Path $configSourceFile) {
    Write-VerboseMessage "Copying config to $configDestinationFile"
    Copy-Item -Path $configSourceFile -Destination $configDestinationFile -Force
} else {
    Write-Error "Source config.json not found at $configSourceFile. Exiting script."
    exit 1
}

# Create firewall rules
# Thanks to - https://github.com/chrysillis/egnyte/blob/main/Intune/Deploy-Egnyte-Intune.ps1
Write-VerboseMessage "Creating firewall rules for Egnyte..."
$firewallrule1 = @{
    DisplayName = "Egnyte TCP"
    Description = "Egnyte Desktop App"
    Direction   = "Inbound"
    Program     = "C:\Program Files (x86)\Egnyte Connect\EgnyteDrive.exe"
    Profile     = "Any"
    Action      = "Allow"
    Protocol    = "TCP"
}
$firewallstatus = New-NetFirewallRule @firewallrule1
Write-VerboseMessage $firewallstatus.status

$firewallrule2 = @{
    DisplayName = "Egnyte UDP"
    Description = "Egnyte Desktop App"
    Direction   = "Inbound"
    Program     = "C:\Program Files (x86)\Egnyte Connect\EgnyteDrive.exe"
    Profile     = "Any"
    Action      = "Allow"
    Protocol    = "UDP"
}
$firewallstatus = New-NetFirewallRule @firewallrule2
Write-VerboseMessage $firewallstatus.status

# Download the Egynte MSI file
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest -Uri $msiUrl -OutFile $msiFilePath

# Install the MSI
Write-VerboseMessage "Installing EgnyteDrive.msi..."

# IMPORTANT - set ED_SILENT=0 to make the install NON-Silent
# A silent deployment will not prompt the user to sign into Egnyte
$arguments = @("/i", "`"$msiFilePath`"", "ED_SILENT=0", "/quiet")

Start-Process msiexec.exe -ArgumentList $arguments -Wait

Write-VerboseMessage "Installation completed."

# Stop logging if enabled
if ($LogOutput) {
    Stop-Transcript
}