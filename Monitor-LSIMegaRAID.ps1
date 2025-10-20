<#
.SYNOPSIS
    Checks RAID health on LSI MegaRAID controllers.

.DESCRIPTION
    This script checks both virtual and physical drive status on LSI Controllers using the StoreCLI tool included in the MegaRAID storage manager.


.NOTES
    - MegaRAID Storage Manager must be installed, which includes the required StorCLI64.exe tool.
    - Syncro RMM Alerts will be generated for any issues.
    - You should schedule the script to run daily or hourly in Syncro

#>

Import-Module $env:SyncroModule

[string]$StorCLILocation = "C:\Program Files (x86)\MegaRAID Storage Manager\StorCLI64.exe"
[string]$StorCliGetControllersCount = "show j"

# Clean out vars
$ErrorStatus = ""
$RAIDStatus = ""
$ScriptError = ""

# Get number of controllers
try {
    $ExecuteStoreCLI = & $StorCLILocation $StorCliGetControllersCount | Out-String
    $ArrayControllersCount = ConvertFrom-Json $ExecuteStoreCLI
} catch {
    $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
    Write-Host $ScriptError
    exit
}

$ControllersCount = $ArrayControllersCount.Controllers.Count

# Controller count starts at 0
$ControllerNum = 0
while ($ControllerNum -le $ControllersCount) {
    Write-Host "`n--- Checking Controller $ControllerNum ---`n"

    # --- Virtual Drive Status Check ---
    Write-Host "-- Virtual Drives --"
    try {
        [string]$VDCommand = "/c$ControllerNum /vall show j"
        $VDOutput = & $StorCLILocation $VDCommand | Out-String
        $VDJson = ConvertFrom-Json $VDOutput

        foreach ($VirtualDrive in $VDJson.Controllers.'response data'.'Virtual Drives') {
            $Status = "Virtual Drive $($VirtualDrive.'DG/VD') With Size $($VirtualDrive.'Size') status is $($VirtualDrive.State)`n"
            Write-Host $Status
            if ($VirtualDrive.State -ne "Optl") {
                $ErrorStatus += "$Status`n"
            }
        }
    } catch {
        $ScriptError += "Virtual Drive Check Failed on Controller $ControllerNum : $($_.Exception.Message)`n"
    }

    # --- Physical Drive Status Check ---
    Write-Host "-- Physical Drives --"
    try {
        [string]$PDCommand = "/c$ControllerNum /eall /sall show j"
        $PDOutput = & $StorCLILocation $PDCommand | Out-String
        $PDJson = ConvertFrom-Json $PDOutput

        foreach ($Drive in $PDJson.Controllers.'response data'.'Drive Information') {
            $Status = "$($Drive.Model) with Disk ID $($Drive.DID) status is $($Drive.State)"
            Write-Host $Status
            if ($Drive.State -notmatch "^(Onln|UGood)$") {
                $ErrorStatus += "$Status`n"
            }
        }
    } catch {
        $ScriptError += "Physical Drive Check Failed on Controller $ControllerNum : $($_.Exception.Message)`n"
    }

    $ControllerNum++
}

# Final status
if ($ErrorStatus) {
    Write-Host "`nWARNING: Issues found!`n$ErrorStatus"
    Rmm-Alert -Category 'RAID' -Body 'Potential RAID failure! Please investigate ASAP.'
} else {
    $RAIDStatus = "Healthy"
    Write-Host "`nRAID status is $RAIDStatus."
    Close-Rmm-Alert -Category "RAID" -CloseAlertTicket "true"
}

if ($ScriptError) {
    Write-Host "`nWARNING! Script completed with errors:`n$ScriptError"
} else {
    $ScriptError = "Healthy"
}