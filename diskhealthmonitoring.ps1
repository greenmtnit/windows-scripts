Import-Module $env:SyncroModule

# Functions

<#
    .SYNOPSIS
        Install-Smartmontools checks if smartctl.exe is present at C:\Program Files\smartmontools\bin\smartctl.exe
        If not, it installs smartmontools using chocolatey
        It returns nothing
#>
function Install-Smartmontools {
    $smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"
    if (!(Test-Path $smartctlPath)) {
        # We need to install smartctl, it wasn't found
        Write-Host "smartctl not found, installing it"
        # Here we incorporate the chocolatey script from here: https://greenmtnit.syncromsp.com/scripts/611809/edit

        $syncroPath = "$env:ProgramFiles\RepairTech\Syncro\kabuto_app_manager\choco.exe"
        $chocoPath = "$env:ProgramData\chocolatey\choco.exe"
        $packageName = "smartmontools"

        try {
            # Check for Chocolatey in Syncro path
            if (Test-Path -Path $syncroPath) {
                Write-Host "Found Chocolatey from Syncro, using it."
                $choco = $syncroPath
            }
            # Check for Chocolatey in its default location
            elseif (Test-Path -Path $chocoPath) {
                Write-Host "Found Chocolatey in its default location, using it."
                $choco = $chocoPath
            }
            else {
                Write-Host "Chocolatey not found, installing it..."
                
                # Install Chocolatey
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

                $choco = $chocoPath
            }

            Write-Host "Installing $packageName"
            
            # Use the "upgrade" command, which will either install or upgrade the package
            & "$choco" upgrade $packageName -y
        }
        catch {
            Write-Host "Error: $_"
        }
    }
}

<#
    .SYNOPSIS
        Invoke-Smartmontools checks every compatible disk on the computer and runs checks 
        It returns "Healthy" if all tests passed; otherwise, it returns details of the error
#>
function Invoke-Smartmontools {
    # This code was adapted from https://www.cyberdrain.com/monitoring-with-powershell-monitoring-smart-status-using-smartctl/
    # Credit to Kevin Tegelaar from CyberDrain
    # This code is covered under AGPL3.0

    ############ Thresholds #############
    $PowerOnTime = 35063 # about 4 years constant runtime.
    $PowerCycles = 4000 # 4000 times of turning drive on and off
    $Temperature = 70 # 70 degrees Celsius
    ############ End Thresholds #########

    # Find all connected HDDs
    $HDDs = (& "C:\Program Files\smartmontools\bin\smartctl.exe" --scan -j | ConvertFrom-Json).devices

    # TODO: Pare down HDDs list to only include disks that are of type SSD or HDD (not USB drives or other things we don't care about)

    # HDDInfo returns a custom PowerShell object with nested properties
    foreach ($HDD in $HDDs){
		$name =$HDD.name
        Write-Host "Checking $name"

        $HDDInfo = (& "C:\Program Files\smartmontools\bin\smartctl.exe" -t short -a -j $HDD.name) | convertfrom-json

        $model = $HDDInfo.model_name 
        $serial = $HDDInfo.serial_number
        Write-Host "Info for disk $model with SN $serial"
        function Print-ObjectProperties {
            param (
                [Parameter(Mandatory = $true)]
                $Object,
                [string]$Indent = ""
            )
        
            $Object.PSObject.Properties | ForEach-Object {
                Write-Host "$Indent$($_.Name):"
                $Value = $_.Value
                if ($Value -is [System.Management.Automation.PSCustomObject]) {
                    Print-ObjectProperties -Object $Value -Indent "$Indent    "
                } elseif ($Value -is [System.Object[]]) {
                    $Value | ForEach-Object {
                        Print-ObjectProperties -Object $_ -Indent "$Indent    "
                    }
                } else {
                    Write-Host "$Indent    $Value"
                }
            }
        }
        
        # Print HDDInfo
        Print-ObjectProperties -Object $HDDInfo

        $DiskHealth = "True"
        $DiskHealthDetails = ""
        # Checking SMART status
        $SmartFailed = $HDDInfo | Where-Object { $_.Smart_Status.Passed -ne $true }
        if ($SmartFailed) {
            $DiskHealthDetails = $DiskHealthDetails + "Smart Failed for disks: $($SmartFailed.serial_number)"
            Write-Host 'SmartErrors',"Smart Failed for disks: $name" #$($SmartFailed.serial_number)"
            $DiskHealth = "False"
        }
        # Checking Temp Status
        $TempFailed = $HDDInfo | Where-Object { 
            $_.temperature.current -ge $Temperature
        }
        Write-Host $TempFailed
        if ($TempFailed) { 
            $DiskHealthDetails = $DiskHealthDetails + "Temperature failed for disks: $($TempFailed.serial_number) `n" 
            Write-Host 'TempErrors',"Temperature failed for disks: $($TempFailed.serial_number)"
            $DiskHealth = "False"

        }
        # Checking Power Cycle Count status
        $PCCFailed = $HDDInfo | Where-Object { $_.Power_Cycle_Count -ge $PowerCycles }
        if ($PCCFailed ) { 
            $DiskHealthDetails = $DiskHealthDetails + "Power Cycle Count Failed for disks: $($PCCFailed.serial_number) `n" 
            Write-Host 'PCCErrors',"Power Cycle Count Failed for disks: $($PCCFailed.serial_number)"
            $DiskHealth = "False"
        }
        # Checking Power on Time Status
        $POTFailed = $HDDInfo | Where-Object { $_.Power_on_time.hours -ge $PowerOnTime }
        if ($POTFailed) { 
            $DiskHealthDetails = $DiskHealthDetails + "Power on Time for disks failed : $($POTFailed.serial_number) `n"
            Write-Host 'POTErrors',"Power on Time for disks failed : $($POTFailed.serial_number)"
            $DiskHealth = "False"
        }
        
        Write-Host $DiskHealthDetails

        #return $DiskHealth
    }
}

# Start with two easy checks using built-in functions: Get-PhysicalDisk Health and Get-StorageReliabilityCounter
$disks = Get-PhysicalDisk
foreach ($disk in $disks) {
    if (!($disk.HealthStatus -eq "Healthy")) {
        Write-Host "Problem! Disk $($disk.FriendlyName) is NOT healthy!"
        RMM-Alert -Category 'DISK HEALTH' -Body "Problem! Disk not healthy!"
        exit 1 # Can exit the script here. If there's a problem, that's all you need to know.
    }
    $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk

    # Check if any error counters are greater than 0
    if ($reliability.ReadErrorsTotal -gt 0 -or 
        $reliability.ReadErrorsUncorrected -gt 0 -or 
        $reliability.WriteErrorsTotal -gt 0 -or 
        $reliability.WriteErrorsUncorrected -gt 0) {
        Write-Host "Disk $($disk.FriendlyName) has errors:"
        Write-Host "Total Read Errors: $($reliability.ReadErrorsTotal)"
        Write-Host "Uncorrected Read Errors: $($reliability.ReadErrorsUncorrected)"
        Write-Host "Total Write Errors: $($reliability.WriteErrorsTotal)"
        Write-Host "Uncorrected Write Errors: $($reliability.WriteErrorsUncorrected)"
    }
    else {
        Write-Host "Basic checks passed for disk $($disk.FriendlyName)"
    }
}

# Easy checks didn't find anything
# Run deeper checks on every disk

# Install Smartmontools, if not already installed
Install-Smartmontools

Invoke-Smartmontools
# Run a SMART test with smartmontools
#$smartmonDiskHealth = Invoke-Smartmontools
#if (!($smartmonDiskHealth -eq "True")) {
#    # The drive is unhealthy
#    Write-Host "Problem - smartmontools health test found problems."
#    Write-Host "Details: $smartmonDiskHealth"
#    RMM-Alert -Category 'DISK HEALTH' -Body "Problem - smartmontools health test found problems on drive $diskName !"
#    exit 1
#} else {
#    Write-Host "smartmontools disk health PASSED"
#    exit 0
#}
