<#
  Detect-PotentiallyUnwantedSoftware.ps1
    
  Detects potentially undesirable software and throws a Syncro RMM alert if any found..
  
#>

Import-Module $env:SyncroModule

# Function to get a list of matching applications from the registry
function Get-MatchingApplications {
    <#
    .SYNOPSIS
    Retrieves a list of installed applications that match a predefined list.

    .DESCRIPTION
    This function searches through the registry to find installed applications
    and returns a list of those that match a predefined list of application names,
    supporting wildcard characters for partial matches. Additionally, it allows 
    excluding specific applications from the results.

    .PARAMETER ApplicationList
    An array of application names to search for in the registry. Supports wildcard characters.

    .PARAMETER ExcludeList
    An array of application names to exclude from the search results. Supports wildcard characters.

    .OUTPUTS
    [System.Collections.Generic.List[string]] A list of matching application names.

    .EXAMPLE
    $ApplicationList = @("Zoho*", "Chrome*")
    $ExcludeList = @("Zoho Mail Outlook Addin")
    $matchedApps = Get-MatchingApplications -ApplicationList $ApplicationList -ExcludeList $ExcludeList
    Write-Output "Found the following matching applications: $($matchedApps -join ', ')"
    
    This example retrieves all applications matching "Zoho*" and "Chrome*" but excludes "Zoho Mail Outlook Addin".
    
    .EXAMPLE
    $ApplicationList = @("AnyDesk*", "Atera", "Chrome")
    $matchedApps = Get-MatchingApplications -ApplicationList $ApplicationList
    Write-Output "Found the following matching applications: $($matchedApps -join ', ')"
    
    This example retrieves all applications matching "AnyDesk*", "Atera", and "Chrome" without exclusions.
    #>

    param (
        [Parameter(Mandatory=$true)]
        [string[]]$ApplicationList,
        
        [Parameter(Mandatory=$false)]
        [string[]]$ExcludeList
    )

    try {
        # Get installed applications from the registry
        $InstalledApps = Get-ChildItem "HKLM:\software\microsoft\windows\currentversion\uninstall", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop

        # Filter and collect matching applications
        $MatchingApps = $InstalledApps | ForEach-Object {
            try {
                $app = Get-ItemProperty $_.PSPath -ErrorAction Stop
                if ($app.PSObject.Properties['DisplayName']) {
                    $app.DisplayName
                } else {
                    $null
                }
            } catch {
                Write-Warning "Failed to get properties for registry path: $_.PSPath"
                $null
            }
        } | Where-Object { 
            $appName = $_ 
            # Include only apps that match the ApplicationList and are not in ExcludeList
            ($ApplicationList | ForEach-Object { if ($appName -like $_) { return $true } }) -and 
            -not ($ExcludeList | ForEach-Object { if ($appName -like $_) { return $true } }) 
        }

        return $MatchingApps
    } catch {
        Write-Error "An error occurred while retrieving installed applications: $_"
        return @()
    }
}


$ApplicationList = @(
    "Action1*"
    "Advanced Monitoring Agent*"
    "Adobe Flash Player*"
    "Adobe Shockwave Player*"
    "Aero*"
    "AeroAdmin*"
    "ahnlab*"
    "alpemix*"
    "Ammyy*"
    #"AnyDesk*"
    "Apera*"
    "Atera*"
    "Aspia*"
    "Augmentt*"
    "Auvik*"
    "avast*"
    "avg*"
    "avira*"
    "Barracuda*"
    "Beyond*"
    "BeyondTrust*"
    "bitdefender*"
    "BlackPoint*"
    "bomgar*"
    "checkpoint*"
    "Chrome*"
    # "Chrome Remote*"
    "clamwin*"
    "Cloudberry Remote*"
    "Comodo*"
    "Connectsecure*"
    "Connectwise*"
    "Continuum*"
    "Dameware*"
    "Dameware Remote Everywhere*"
    "Datto*"
    "Datto RMM*"
    "Dayon*"
    "DeskRoll*"
    "Dr.Web*"
    "dualmon*"
    "DWServices*"
    "ehorus*"
    "eset*"
    "fixme.it*"
    "fortinet*"
    "f-prot*"
    "f-secure*"
    "G Data*"
    "GFI*"
    "GoTo Resolve*"
    # "GoToMyPC*"
    "GoSupportNow*"
    "Guacamole*"
    "impcremote*"
    "immunet*"
    "Instant Housecall*"
    "instatech*"
    "ITarian*"
    "ITarian RMM*"
    "ITSupport247*"
    "ISL AlwaysOn*"
    "ISL Light*"
    "Join.me*"
    "Jump Desktop*"
    "Kaseya*"
    "Kaspersky*"
    "LiteManager*"
    #"LogMeIn*"
    "ManageEngine*"
    "ManageEngine Endpoint Central*"
    "ManageEngine RMM Central*"
    "McAfee*"
    "MeshCentral*"
    "mikogo*"
    "mRemoteNG*"
    "MSP*"
    "MSP360*"
    "N-Able*"
    "N-Central*"
    "N=Sight*"
    "nano*"
    "Nave*"
    "Naverisk*"
    "Ninja*"
    "NinjaOne*"
    "NinjaOne RMM*"
    "NoMachine*"
    "Norton*"
    "O&O Syspectr*"
    "OneLaunch*"
    "OpenNX*"
    "Optitune*"
    "Paessler PRTG*"
    "Panda*"
    "Parsec*"
    "Pilixo*"
    "Pulseway*"
    "Qihoo 360*"
    "Quicktime*"
    "Radmin*"
    "Reason*"
    "RealVNC*"
    #"RemotePC*" # Used legitimately by some clients
    "RemoteToPC*"
    "Remote Utilities*"
    "RescueAssist*"
    "Rippling*"
    "RMM Agent*"
    "Scale*"
    "Scalefusion*"
    "ScreenConnect*"
    "Segurazo*"
    #"Sentinel Agent*" # GMITS uses this!
    "ShowMyPC*"
    "SimpleHelp*"
    "SnapAgent*"
    "Solarwinds*"
    "Sophos*"
    "SuperOps*"
    "SuperOps.ai*"
    "Supremo*"
    "Symantec*"
    "Syxsense*"
    "Take Control*"
    #"TeamViewer*"
    "Thinfinity*"
    "Threatlocker"
    "TightVNC*"
    "Tactical RMM*"
    "Trend Micro*"
    "TrustPort*"
    #"UltraVNC*"
    "UltraViewer*"
    "Umbrella Roaming Client*"
    "VNC*"
    "Wave*"
    "Wayk Now*"
    "Webroot*"
    #"Winzip*"
    "Windows Agent*"
    "X2Go*"
    "XEOX*"
    "Zoho*"
    "Zoho Assist*"
    "ZoneAlarm*"
)

$ExcludeList = @(
    "Chrome Remote Desktop Host" # Bad but will need to adress later
    "ScreenConnect Client (d7503fb93fda8d05)" # GMITS Screenconnect Instance
    "ScreenConnect Client (375332c90b2078d5)" # IMerchant (Vendor) Screenconnect Instance
    "Sophos Connect" # Sophos VPN client - not Sophos AV
    "Zoho Mail Outlook Addin"
)

$rmmAlertCategory = "Potentially Unwanted App Found"
$MatchedApps = Get-MatchingApplications -ApplicationList $ApplicationList -ExcludeList $ExcludeList
if ($MatchedApps.Count -gt 0) {
    $msg = "Found potentially unwanted applications:`n" + ($MatchedApps -join "`n")
    Write-Output $msg
    Rmm-Alert -Category $rmmAlertCategory -Body $msg
} else {
    Write-Output "No matching applications found."
    Close-Rmm-Alert -Category $rmmAlertCategory -CloseAlertTicket "true"
}
