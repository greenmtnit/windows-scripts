<#

    Check-FirewallProfileIsDomain.ps1

    Checks if a domain-joined machines's network profile is set to "Domain".
    Excludes VPN/virtual adapters like WireGuard, OpenVPN, iDRAC Remote NDIS). 
    If not, attempts to fix:  restarts NlaSvc and rechecks.
    Falls back to manually setting DomainAuthenticated on private-IP interfaces if still not fixed.
    Creates or closes a Syncro RMM alert based on the outcome.

#>

Import-Module $env:SyncroModule

# First check if server is a domain member
if (-not (Get-CimInstance -Class Win32_ComputerSystem).PartOfDomain) {
    Write-Host "This server is not a member of a domain. Exiting"
    exit 0
}

# Function to check if the firewall profile is set to Domain
function Check-AllDomainAuthenticated {
    # Exclude specific virtual/tunnel adapters by description
    $excludedPatterns = @(
        'Remote NDIS Compatible Device',  # iDRAC Service Module virtual NIC
        'WireGuard Tunnel',               # WireGuard
        'OpenVPN'                         # OpenVPN
    )

    # Get only adapters that are NOT in the excluded list
    $adapters = Get-NetAdapter | Where-Object {
        $desc = $_.InterfaceDescription
        -not ($excludedPatterns | Where-Object { $desc -like "*$_*" })
    }

    # Get the connection profiles for those adapters
    $profiles = Get-NetConnectionProfile |
        Where-Object { $adapters.ifIndex -contains $_.InterfaceIndex }

    # Return $true only if all remaining profiles are DomainAuthenticated
    return ($profiles | Where-Object { $_.NetworkCategory -ne 'DomainAuthenticated' }).Count -eq 0
}

# Check if the firewall profile is set to Domain
if (-not (Check-AllDomainAuthenticated)) {
    Write-Host "Firewall is not set to Domain. Will try restarting NLA service."
    # Restart-Service doensn't work for NlaSvc. Have to kill the process.
    $nlaSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='NlaSvc'"
    $nlaPid = $nlaSvc.ProcessId
    Write-Host "NlaSvc PID: $nlaPid"

    # Kill the process using the PID
    Stop-Process -Id $nlaPid -Force
    Write-Host "NlaSvc process with PID $nlaPid has been terminated."
    
    # Start NlaSvc
    Write-Host "Starting NlaSvc"
    Start-Service -Name "NlaSvc"

    # Wait 10 seconds and check again
    Start-Sleep 10

    if (-not (Check-AllDomainAuthenticated)) {
        Write-Host "Still not Domain profile. Will attempt to set using Set-NetConnectionProfile"

        # Get all network interfaces with valid private IPv4 addresses
        $privateInterfaces = Get-NetIPAddress -AddressFamily IPv4 | 
            Where-Object { $_.IPAddress -match '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)' }

        # Set each interface to Domain category
        foreach ($interface in $privateInterfaces) {
            $connectionProfile = Get-NetConnectionProfile -InterfaceIndex $interface.InterfaceIndex
            if ($connectionProfile.NetworkCategory -ne 'DomainAuthenticated') {
                Set-NetConnectionProfile -InterfaceIndex $interface.InterfaceIndex -NetworkCategory DomainAuthenticated
                Write-Host "Set interface $($interface.InterfaceAlias) to DomainAuthenticated category"
            } else {
                Write-Host "Interface $($interface.InterfaceAlias) is already DomainAuthenticated"
            }
        }

        # Check again if the firewall profile is set to Domain
        if (-not (Check-AllDomainAuthenticated)) {
            Write-Host "Firewall profile is still not set to Domain."
            Rmm-Alert -Category 'Firewall Monitoring' -Body 'Firewall profile is not set to domain.'
        } else {
            Write-Host "Firewall is now set to Domain. All set."
            Log-Activity -Message "Firewall Monitoring" -EventName "Firewall monitoring fixed firewall profile not set to Domain."
            Close-Rmm-Alert -Category "Firewall Monitoring" -CloseAlertTicket "true"
        }
    } else {
        Write-Host "Firewall is now set to Domain. All set."
        Log-Activity -Message "Firewall Monitoring" -EventName "Firewall monitoring fixed firewall profile not set to Domain."
        Close-Rmm-Alert -Category "Firewall Monitoring" -CloseAlertTicket "true"
    }
} else {
    Write-Host "Firewall is set to Domain already."
    Close-Rmm-Alert -Category "Firewall Monitoring" -CloseAlertTicket "true"
}
