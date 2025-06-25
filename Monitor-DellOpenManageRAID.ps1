<#
.SYNOPSIS
    Checks RAID health on DELL PERC controllers.

.DESCRIPTION
    This script checks both virtual and physical drive status on DELL PERC Controllers using the OpenManage tool included in the MegaRAID storage manager.
    Source: https://www.cyberdrain.com/blog-series-monitoring-using-powershell-part-two-using-powershell-to-monitor-dell-systems/
    
.NOTES
    - Dell OpenManage Server Administrator must be installed, which includes the required omconfig.exe and omreport.exe tools.
    - Syncro RMM Alerts will be generated for any issues.
    - You should schedule the script to run daily or hourly in Syncro

#>

Import-Module $env:SyncroModule

$version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentVersion
if ($Version -lt "6.3") {
  Throw "Unsupported OS. This component requires at least Server 2012R2"
}
try {
  $omconfig = "C:\Program Files\Dell\SysMgt\oma\bin\omconfig.exe"
  & $omconfig preferences cdvformat delimiter=comma
  $omreport = "C:\Program Files\Dell\SysMgt\oma\bin\omreport.exe"
  $OmOutput = & $omreport storage vdisk -fmt cdv |  select-string -SimpleMatch "ID,Status," -Context 0, 5000
}
catch {
  Rmm-Alert -Category 'Server Monitoring' -Body 'Dell RAID monitoring script: running omreport failed. It is likely that Dell Open Manage is not installed. Please install Dell Open Manage! Hint: choco install dell-omsa'
  throw "Error: omreport Command has Failed: $($_.Exception.Message). Check if Dell OpenManage is installed and OMReport is in the PATH variable."
}

$VDarray = convertfrom-csv $OmOutput -Delimiter ","

foreach ($VirtualDisk in $VDarray | where-object { $_.'> ID' -in 0..1000 }) {
  #Write-Host "Virtual disk name: $($VirtualDisk.name). State: $($VirtualDisk.State). Status: $($VirtualDisk.Status)."
  Write-Host "$($VirtualDisk.Name) / $($VirtualDisk.'Device Name') has status $($VirtualDisk.Status) / $($VirtualDisk.State)"
  if ($($virtualdisk.State) -eq "Ready" -or $($virtualdisk.Status) -eq "Ok") {
    Write-Host "No issues found."
  }
  else {
    Write-Host "WARNING! RAID issues found!"
    $RAIDStatus = "failed"
  }
}

if ($RAIDStatus) {
  Rmm-Alert -Category 'RAID' -Body 'Potential RAID failure! Please investigate ASAP.'
  if ($CreateTicket -eq "Yes") {
    Create-Syncro-Ticket -Subject "Potential RAID failure" -IssueType "RAID" -Status "New"
  }
}

