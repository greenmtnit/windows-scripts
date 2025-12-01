<#
  Get-WindowsOSVersionInfo.ps1
  
  Gets Windows version, build number, and edition. 
  
  Also checks if Windows 10 or Windows 11 is running a supported version.
  If on an unsupported version, an RMM alert is generated in SyncroMSP.
  
  In the case of Windows 10, the script will also check if Extended Support Updates (ESU) are enabled.
    
  Thanks to https://gist.github.com/asheroto/cfa26dd00177a03c81635ea774406b2b for Get-OSInfo function
  
#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

# VARIABLES - CHANGE THESE 

# Minimum Build Versions
# To get build numbers, see: https://en.wikipedia.org/wiki/Windows_11_version_history

$Windows10MinimumBuild = "19045" # 22H2, EoL October 14, 2025 (see note on ESU)
$Windows11MinimumBuild = "26100" # 24H2, EoL October 13, 2026

$Windows10ESUYear = "1" # Current year for Windows 10 Extended Support updates. See Test-Windows10ESU function.

# SCRIPT BLOCKS - For GUI Pop-Ups

# FUNCTIONS
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

function Get-OSInfo { # https://gist.github.com/asheroto/cfa26dd00177a03c81635ea774406b2b
    <#
        .SYNOPSIS
        Retrieves detailed information about the operating system version and architecture.

        .DESCRIPTION
        This function queries both the Windows registry and the Win32_OperatingSystem class to gather comprehensive information about the operating system. It returns details such as the release ID, display version, name, type (Workstation/Server), numeric version, edition ID, version (object that includes major, minor, and build numbers), and architecture (OS architecture, not processor architecture).

        .EXAMPLE
        Get-OSInfo

        This example retrieves the OS version details of the current system and returns an object with properties like ReleaseId, DisplayVersion, Name, Type, NumericVersion, EditionId, Version, and Architecture.

        .EXAMPLE
        (Get-OSInfo).Version.Major

        This example retrieves the major version number of the operating system. The Get-OSInfo function returns an object with a Version property, which itself is an object containing Major, Minor, and Build properties. You can access these sub-properties using dot notation.

        .EXAMPLE
        $osDetails = Get-OSInfo
        Write-Output "OS Name: $($osDetails.Name)"
        Write-Output "OS Type: $($osDetails.Type)"
        Write-Output "OS Architecture: $($osDetails.Architecture)"

        This example stores the result of Get-OSInfo in a variable and then accesses various properties to print details about the operating system.
    #>
    [CmdletBinding()]
    param ()

    try {
        # Get registry values
        $registryValues = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $releaseIdValue = $registryValues.ReleaseId
        $displayVersionValue = $registryValues.DisplayVersion
        $nameValue = $registryValues.ProductName
        $editionIdValue = $registryValues.EditionId

        # Strip out "Server" from the $editionIdValue if it exists
        $editionIdValue = $editionIdValue -replace "Server", ""

        # Get OS details using Get-CimInstance because the registry key for Name is not always correct with Windows 11
        $osDetails = Get-CimInstance -ClassName Win32_OperatingSystem
        $nameValue = $osDetails.Caption

        # Get architecture details of the OS (not the processor)
        $architecture = $osDetails.OSArchitecture

        # Normalize architecture
        if ($architecture -match "(?i)32") {
            $architecture = "x32"
        } elseif ($architecture -match "(?i)64" -and $architecture -match "(?i)ARM") {
            $architecture = "ARM64"
        } elseif ($architecture -match "(?i)64") {
            $architecture = "x64"
        } else {
            $architecture = "Unknown"
        }

        # Get OS version details (as version object)
        $versionValue = [System.Environment]::OSVersion.Version

        # Determine product type
        # Reference: https://learn.microsoft.com/en-us/dotnet/api/microsoft.powershell.commands.producttype?view=powershellsdk-1.1.0
        if ($osDetails.ProductType -eq 1) {
            $typeValue = "Workstation"
        } elseif ($osDetails.ProductType -eq 2 -or $osDetails.ProductType -eq 3) {
            $typeValue = "Server"
        } else {
            $typeValue = "Unknown"
        }

        # Extract numerical value from Name
        $numericVersion = ($nameValue -replace "[^\d]").Trim()

        # Create and return custom object with the required properties
        $result = [PSCustomObject]@{
            Name           = $nameValue
            ReleaseId      = $releaseIdValue
            DisplayVersion = $displayVersionValue
            Type           = $typeValue
            NumericVersion = $numericVersion
            EditionId      = $editionIdValue
            Version        = $versionValue
            Architecture   = $architecture
        }

        return $result
    } catch {
        Write-Error "Unable to get OS version details.`nError: $_"
        exit 1
    }
}

function Sleep-Random {
    param (
        [int]$MaximumSeconds = 300
    )
    if ($RandomDelay -eq "true") {
        $RandomSleep = Get-Random -Maximum $MaximumSeconds
        Write-Host "Sleeping for $RandomSleep seconds"
        Start-Sleep -Seconds $RandomSleep
    }
    else {
        Write-Host "Random delay is not enabled. Skipping sleep."
    }
}

function Test-Windows10ESU {
    <#
    .SYNOPSIS
    Tests whether a Windows 10 Extended Support Update license is activated.

    .DESCRIPTION
    Test-Windows10ESU checks the SoftwareLicensingProduct CIM class for the
    Extended Security Updates (ESU) activation ID that corresponds to the
    specified ESU year (1, 2, or 3) and returns $true if the license status
    is activated, otherwise $false.

    .PARAMETER ESUYear
    The ESU program year to test. Valid values are 1, 2, or 3, which map to
    the respective ESU activation IDs for Windows 10.
    
    - ESU Year 1: October 15, 2025 – October 14, 2026.​

    - ESU Year 2: October 15, 2026 – October 14, 2027.​

    - ESU Year 3: October 15, 2027 – October 14, 2028.​

    .OUTPUTS
    System.Boolean
    Returns $true if the specified ESU year license is activated, otherwise $false.

    .EXAMPLE
    Test-Windows10ESU -ESUYear 1
    Tests whether the Windows 10 ESU Year 1 license is activated and returns $true or $false.

    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(1,2,3)]
        [int]$ESUYear
    )

    # ESU Activation IDs
    $ActivationIDs = @{
        1 = "f520e45e-7413-4a34-a497-d2765967d094"
        2 = "1043add5-23b1-4afb-9a0f-64343c8f3f8d"
        3 = "83d49986-add3-41d7-ba33-87c7bfb5c0fb"
    }

    $ActivationID = $ActivationIDs[$ESUYear]
    if (-not $ActivationID) {
        throw "Invalid ESU year specified."
    }

    $CIMFilter = 'id="{0}"' -f $ActivationID
    $ESU = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $CIMFilter

    if (-not $ESU) {
        Write-Verbose "No ESU license instance found for Activation ID $ActivationID."
        return $false
    }

    # LicenseStatus 1 = Licensed
    if ($ESU.LicenseStatus -eq 1) { [bool]$true } else { [bool]$false }
}


## MAIN SCRIPT ACTION

$osInfo = Get-OSInfo
$osInfo | Format-List

$currentBuild = $osInfo.Version.Build
$currentName = $osInfo.Name
$currentDisplayVersion = $osInfo.DisplayVersion

# Alert Messages
$AlertCategory = "Windows OS Version"

# Windows 10 Checks
if ($osInfo.NumericVersion -eq "10") {
    $esuActive = Test-Windows10ESU -ESUYear $Windows10ESUYear
    $buildSupported = ($currentBuild -ge $Windows10MinimumBuild)

    if ($esuActive -and $buildSupported) {
        Write-Host "Detected Windows 10, but ESU is active and machine is on a supported build. OK for now."

        if ($null -ne $env:SyncroModule) {
            Close-Rmm-Alert -Category $AlertCategory -CloseAlertTicket "true"
        }
    }
    elseif ($esuActive -and -not $buildSupported) {
        $AlertBody = "WARNING: Windows 10 ESU is active, but Windows 10 build is below the supported minimum."
        Write-Host $AlertBody
        if ($null -ne $env:SyncroModule) {
            Rmm-Alert -Category $AlertCategory -Body $AlertBody
        }
    }
    else {
        $AlertBody = "WARNING: Windows 10 detected and ESU is NOT active. You should upgrade to a newer OS or enable ESU and make sure Windows 10 is on version 22H2."
        Write-Host $AlertBody
        if ($null -ne $env:SyncroModule) {
            Rmm-Alert -Category $AlertCategory -Body $AlertBody
        }
    }
}



# Windows 11 Checks
elseif ($osInfo.NumericVersion -eq "11") {
    if ($currentBuild -lt $Windows11MinimumBuild) {
        $AlertBody = "WARNING: Unsupported Windows 11 build version detected!"
        Write-Host $AlertBody
        if ($null -ne $env:SyncroModule) {
            Rmm-Alert -Category $AlertCategory -Body $AlertBody
        }
    }
    else {
        Write-Host "This machine is running a supported operating system version."
        if ($null -ne $env:SyncroModule) {
            Close-Rmm-Alert -Category $AlertCategory -CloseAlertTicket "true"
        }
    }
}

else {
    $AlertBody = "Unsupported or unknown OS version detected."
    Write-Host $AlertBody
    if ($null -ne $env:SyncroModule) {
        Rmm-Alert -Category $AlertCategory -Body $AlertBody
    }
}

