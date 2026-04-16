<#
    Upgrade-EvoLDAPAgent.ps1
    
    Upgrades an existing installation of the Evo Security LDAP Agent.
        
    Summary:
        Checks if Evo LDAP Agent is installed.
        Downloads official Evo LDAP Agent deployment script: https://github.com/evosecurity/EvoWindowsAgentDeploymentScripts/blob/master/InstallLdapAgent.ps1
        Run the script with -Upgrade flag.
        Throws a Syncro RMM alert if upgrade fails.
        Clears open Evo LDAP Deployment RMM alerts (if any) if install succeeds.
    
    Logging & Troubleshooting:
        Check log file:  C:\Windows\temp\EvoLdapAgent_upgrade.log

#>

Import-Module $env:SyncroModule
# Detect existing installation
$installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -in @("Evo LDAPS Agent") }

if (-not $installed) {
    Write-Host "Evo LDAP Agent is not installed. Exiting."
    Exit 0
}

# Download official Evo LDAP install script
$scriptUrl  = "https://raw.githubusercontent.com/evosecurity/EvoWindowsAgentDeploymentScripts/refs/heads/master/InstallLdapAgent.ps1"
$scriptPath = Join-Path $env:TEMP "InstallLdapAgent.ps1"

Write-Host "Downloading Evo LDAP installer script..."

try {
    Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -ErrorAction Stop
}
catch {
    Write-Warning "Failed to download Evo installer script: $($_.Exception.Message)"
    exit 1
}

# Run script
try {
    Write-Host "Running Evo LDAP installer script..."

    $output = & $scriptPath -Upgrade -Log *>&1

    Write-Host ($output | Out-String)
    
    $installSucceeded = $true
}

catch {
    $msg = $_.Exception.Message

    if ($msg -match "The currently installed version is already at the most recent") {
        Write-Host "Evo LDAP Agent is already installed and up to date."
        $noInstallNeeded = $true
    }
    elseif ($msg -match "The currently installed version is more recent") {
        Write-Host "Installed Evo LDAP Agent version is newer than the installer version. No action taken."
        $noInstallNeeded = $true
    }
    else {
        Write-Warning "Evo LDAP installer encountered an error:"
        Write-Warning $msg
        Rmm-Alert -Category "Evo LDAP Agent Deployment" -Body "Evo deployment failed: $msg"
    }
}

if ($installSucceeded -or $noInstallNeeded) {
    Write-Host "Evo deployment completed successfully."
    Close-Rmm-Alert -Category "Evo LDAP Agent Deployment" -CloseAlertTicket "true"
}
