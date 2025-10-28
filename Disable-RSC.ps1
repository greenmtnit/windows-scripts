<#
  Disable-RSC.ps1
  
  Disables RSC on Hyper-V network adapters. See here: 
  https://hudu.greenmtnit.com/kba/disabling-rsc-to-fix-poor-storage-performance-over-network-especially-server-2019-31deaba88045
  
  The script disables RSC on all VM switches, and also creates a Scheduled Task to repeat the process on every bootup, in case RSC is re-enabled automatically.
  
#>

# Check if VM host
if (!(Get-Command "Get-VMSwitch" -ErrorAction SilentlyContinue)) {
  Write-Host "VMSwitch cmdlets not found. Is this a Hyper-V host? EXITING"
  exit 0
}

Write-Host "Checking current status of RSC on Virtual Switches"
Get-VMSwitch | Select-Object Name, SoftwareRscEnabled, RscOffloadEnabled

Write-Host "Disabling RSC on all virtual switches"
Get-VMSwitch | Set-VMSwitch -EnableSoftwareRsc:$false

# Prepare folders
$baseFolder = "C:\Program Files\Green Mountain IT Solutions"
$scriptsFolder = "$baseFolder\Scripts"
$disableRscScript = "$scriptsFolder\DisableRsc.ps1"

Write-Host "Ensuring required folders exist..."
if (-not (Test-Path $baseFolder)) {
  New-Item -ItemType Directory -Path $baseFolder | Out-Null
}
if (-not (Test-Path $scriptsFolder)) {
  New-Item -ItemType Directory -Path $scriptsFolder | Out-Null
}

# Create DisableRsc.ps1 script content
$disableRscContent = @'
if (! (Get-Command "Get-VMSwitch" -ErrorAction SilentlyContinue)) {
  Write-Host "VMSwitch cmdlets not found. Is this a Hyper-V host? EXITING"
  exit 0
}

Write-Host "Checking current status of RSC on Virtual Switches"
Get-VMSwitch | Select-Object Name, SoftwareRscEnabled, RscOffloadEnabled

Write-Host "Disabling RSC on all virtual switches"
Get-VMSwitch | Set-VMSwitch -EnableSoftwareRsc:$false
'@

Set-Content -Path $disableRscScript -Value $disableRscContent -Encoding UTF8
Write-Host "Created DisableRsc.ps1 script at $disableRscScript"

# Create scheduled task to run script at startup
$taskName = "Disable RSC"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Write-Host "Scheduled task '$taskName' already exists. No changes made."
} else {
  Write-Host "Creating scheduled task '$taskName'..."

  $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$disableRscScript`""
  $taskTrigger = New-ScheduledTaskTrigger -AtStartup
  $description = "Disable RSC on all virtual switches at startup."

  Register-ScheduledTask `
    -TaskName $taskName `
    -Action $taskAction `
    -Trigger $taskTrigger `
    -Description $description `
    -User "SYSTEM"

  Write-Host "Scheduled task '$taskName' has been created successfully."
}
