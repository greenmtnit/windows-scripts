<#
    Deploy-EvoSecurity.ps1
    
    Syncro RMM Deployment script for Evo Security Agent
    
    Syncro Script Variables:
        $EvoDeploymentToken - Platform Variable. Set to Customer Custom Field "Evo Deployment Token". Paste the client's deployment token in this field in Syncro.
        $EvoServerToken - Platform Variable. Set to Customer Custom Field "Evo Server Deployment Token". Paste the client's SERVER deployment token in this field in Syncro.
        $ForceBranding - Dropdown. String values "true" or "false". Default: "false". If true, custom branding will be applied in every case, regardless of if Evo is already installed.
        $Remove - Dropdown. String values "true" or "false". Default: "false". If true, remove the Evo agent.
        $CustomInstallerURL - Runtime. Enter a URL of a custom Evo agent download. This can be used to install older versions of the agent.
            Download URLs are in this format: https://download.evosecurity.com/release/credpro/credential-provider-v2.5.2.0_x64.zip.
            To download another version, change the version number in the URL.
    
    Summary:
        Checks if Evo is already installed.
        Downloads official Evo deployment script: https://raw.githubusercontent.com/evosecurity/EvoWindowsAgentDeploymentScripts/refs/heads/master/InstallEvoAgent.ps1
        If Evo is already installed, runs the official install script with -Upgrade flag.
        If Evo is not installed, runs official install script normally.
        Throws a Syncro RMM alert if install fails.
        Clears open Evo Deployment RMM alerts (if any) if install succeeds.
        Applies custom branding (https://helpdesk.evosecurity.com/product-information/5t3848WNzTVsSU4KkXazrX/end-user-elevation-custom-branding/69qPZzsDFUEA5aJtyDrbkf)
    
    Logging & Troubleshooting:
        Check log file:  C:\Windows\temp\EvoAgent_install.log

#>

Import-Module $env:SyncroModule

# Check for AutoElevate, to avoid conflicts
if ($Remove -ne "true") {
    if (Get-Service -Name "AutoElevateAgent" -ErrorAction SilentlyContinue) { 
        Write-Host "Detected conflicting software AutoElevate. Evo install will be aborted."
        exit 1
    }
}

# Detect existing installation
$installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -in @("Evo Agent","Evo Secure Login") }
$evoVersion = ($installed | Select -First 1).DisplayVersion

$upgradeMode = $false

if ($Remove -eq "true") {
    Write-Host "Remove is set. Removing Evo!"
}
elseif ($installed) {
    $upgradeMode = $true
    Write-Host "Existing Evo installation detected. Version: $EvoVersion. Running install script in upgrade mode."
}
else {
    Write-Host "Evo not currently installed. Running install."
}

# Check for and download optional custom installer
if ($CustomInstallerURL) {
    Write-Host "NOTICE: `$CustomInstallerURL was passed. Running custom install."
    $CustomInstall = $true
    $CustomInstallerFileName = $CustomInstallerURL.Split('/')[-1]
    $CustomInstallerPath = Join-Path $env:TEMP $CustomInstallerFileName

    Write-Host "Downloading custom installer..."

    try {
        Invoke-WebRequest -Uri $CustomInstallerURL -OutFile $CustomInstallerPath -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to download custom installer: $($_.Exception.Message)"
        exit 1
    }
    
    # If download is a ZIP, extract it and locate MSI
    if ($CustomInstallerFileName -like "*.zip") {
        Write-Host "Extracting $CustomInstallerFileName..."
        $CustomInstallerExtractPath = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($CustomInstallerFileName))
        try {
            Expand-Archive -Path $CustomInstallerPath -DestinationPath $CustomInstallerExtractPath -Force -ErrorAction Stop
            Write-Host "Extracted to: $CustomInstallerExtractPath"
        }
        catch {
            Write-Warning "Failed to extract zip: $($_.Exception.Message)"
            exit 1
        }
        
        $CustomInstallerMSIPath = Get-ChildItem -Path $CustomInstallerExtractPath -Filter "*.msi" -Recurse | Select-Object -First 1 -ExpandProperty FullName
        if ($CustomInstallerMSIPath) {
            Write-Host "Found MSI: $CustomInstallerMSIPath"
        }
        else {
            Write-Warning "No .msi file found in extracted contents."
            exit 1
        }
    }
    
    # If download is already an MSI, not a ZIP
    elseif ($CustomInstallerFileName -like "*.msi") {
        $CustomInstallerMSIPath = $CustomInstallerDownloadPath
    }
    
    else {
        Write-Host "Error locating MSI file in custom installer."
        Exit 1
    }
}

# Server Check
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
if ($osInfo.ProductType -ne 1) {
    Write-Host "This is a server. Using server token."
    if (-not $EvoServerToken) {
        # Check for deployment token
        $msg = "Error! Evo server deployment token not found!"
        Write-Host $msg
        Rmm-Alert -Category "Evo Deployment" -Body "Evo deployment failed: $msg"
        exit 1
    }
    else {
        $DeploymentToken = $EvoServerToken
    }
}

else { # Not a server. Use regular token.
    if (-not $EvoDeploymentToken) {
        # Check for deployment token
        $msg = "Error! Evo deployment token not found!"
        Write-Host $msg
        Rmm-Alert -Category "Evo Deployment" -Body "Evo deployment failed: $msg"
        exit 1
    }
    else {
        $DeploymentToken = $EvoDeploymentToken
    }
}

# Download official Evo install script
$scriptUrl  = "https://raw.githubusercontent.com/evosecurity/EvoWindowsAgentDeploymentScripts/refs/heads/master/InstallEvoAgent.ps1"
$scriptPath = Join-Path $env:TEMP "InstallEvoAgent.ps1"

Write-Host "Downloading Evo installer script..."

try {
    Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -ErrorAction Stop
}
catch {
    Write-Warning "Failed to download Evo installer script: $($_.Exception.Message)"
    exit 1
}

try {
    Write-Host "Running Evo installer script..."
    if ($Remove -eq "true") {
        Write-Host "Running: $scriptPath -Remove"
        $output = & $scriptPath -Remove *>&1
    }
    elseif ($upgradeMode) {
        $params = @{
            DeploymentToken = $DeploymentToken
            Upgrade         = $true
            Log             = $true
        }
        if ($CustomInstall -eq $true) { $params['MSIPath'] = $CustomInstallerMSIPath }
        Write-Host "Running: $scriptPath $(($params.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' ')"
        $output = & $scriptPath @params *>&1
    }
    else {
        $params = @{
            DeploymentToken = $DeploymentToken
            Log             = $true
        }
        if ($CustomInstall -eq $true) { $params['MSIPath'] = $CustomInstallerMSIPath }
        Write-Host "Running: $scriptPath $(($params.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' ')"
        $output = & $scriptPath @params *>&1
    }
    Write-Host ($output | Out-String)
    
    $installSucceeded = $true
}

catch {
    $msg = $_.Exception.Message

    if ($msg -match "The currently installed version is already at the most recent") {
        Write-Host "Evo is already installed and up to date."
        $noInstallNeeded = $true
    }
    elseif ($msg -match "The currently installed version is more recent than that downloaded") {
        Write-Host "Installed Evo version is newer than the installer version. No action taken."
        $noInstallNeeded = $true
    }
    else {
        Write-Warning "Evo installer encountered an error:"
        Write-Warning $msg
        Rmm-Alert -Category "Evo Deployment" -Body "Evo deployment failed: $msg"
    }
}

if ($installSucceeded -or $noInstallNeeded) {
    Write-Host "Evo deployment completed successfully."
    Close-Rmm-Alert -Category "Evo Deployment" -CloseAlertTicket "true"
}

# BRANDING SECTION
if (($installSucceeded -or ($ForceBranding -eq "true")) -and ($Remove -ne "true")) {
    Write-Host "Applying branding"

    # Dowload Logo File
    $logoURL = "https://s3.us-east-1.wasabisys.com/gmits-public/gmits_logo_evo.png"
    $logoPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\gmits_logo_evo.png"
    Invoke-WebRequest -Uri $logoURL -OutFile $logoPath

    # Set Branding Registry Values
    $CustomizationParams = @{
        BrandLogoPath   = $logoPath
        WindowTitle     = "Privilege Request"
        HeaderText      = "Administrator Privileges Required"
        GeneralPrompt   = "Would you like to request administrator privileges for this action?"
        ReasonLine1     = "Please enter the reason for your request below."
        ProcessingText  = "Validating request..."
        ReasonLine2     = "NOTE: REQUESTS ARE NOT RECEIVED AUTOMATICALLY. Please email support@greenmtnit.com after making your request."
    }

    $RootCustomizationPath = "HKLM:\\Software\\EvoSecurity\\EvoLogin-CP\\Customization"

    if (-not (Test-Path $RootCustomizationPath)) {
        New-Item $RootCustomizationPath
    }

    foreach ($key in $CustomizationParams.Keys) {
        $value = $CustomizationParams[$key]
        Set-ItemProperty $RootCustomizationPath "ConsentUI.$Key" "$value"
    }

}

