<#
  Get-MsftEntraDeviceId.ps1
  
  Gets the Microsoft Entra Device ID and writes it to the msftEntraDeviceId Syncro asset custom field.
  
  For use with SAASAlerts. Reference: https://help.saasalerts.kaseya.com/help/Content/Information/information-on-microsoft-entra-device-id.htm
#>

Import-Module $env:SyncroModule

# Get Entra Device status output lines
$DsregCmdStatus = dsregcmd /status

# Initialize DeviceId variable
$DeviceId = $null

# Find the line containing DeviceId (case-insensitive)
$deviceIdLine = $DsregCmdStatus | Where-Object { $_ -match "DeviceId\s*:\s*(.+)" }

if ($deviceIdLine) {
    # Extract DeviceId value after colon and trim
    $DeviceId = ($deviceIdLine -split ":")[1].Trim()
}

if ($DeviceId) {
    Write-Host "Device ID is: $DeviceId"
    Set-Asset-Field -Name msftEntraDeviceId -Value $DeviceId
} else {
    Write-Host "Device ID not found. This may not be an Entra-joined device."
}
