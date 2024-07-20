Import-Module $env:SyncroModule

# CHECK FOR EXISTING
# Check if the scheduled task already exists and if so, exit.
$taskName = "NodePing Heartbeat Monitor"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($taskExists) {
    Write-Host "Scheduled task '$taskName' already exists. Exiting script."
    exit
}

# GRACE PERIOD CHECK
# Check if we're in the grace period. If the grace period key is missing, create it.
$parentKeyPath = "HKLM:\SOFTWARE\Green Mountain IT Solutions"
$subKeyPath = "$parentKeyPath\Scripts"
$registryValueName = "NodePingSetupDate"

# Check if the install date registry value exists
$existingValue = Get-ItemProperty -Path $subKeyPath -Name $registryValueName -ErrorAction SilentlyContinue

#Create the value if it does not exist
if ($existingValue -eq $null) {
    # Ensure the parent key exists
    if (-not (Test-Path -Path $parentKeyPath)) {
        New-Item -Path $parentKeyPath -Force | Out-Null
    }

    # Ensure the sub key exists
    if (-not (Test-Path -Path $subKeyPath)) {
        New-Item -Path $subKeyPath -Force | Out-Null
    }

    # Get today's date
    $todayDate = Get-Date -Format "yyyy-MM-dd"

    # Set the registry value
    New-ItemProperty -Path $subKeyPath -Name $registryValueName -Value $todayDate -PropertyType String -Force
    
	# Suppress RMM alerts, since we just started the grace period
    Write-Host "Grace period just began! Supressing RMM Alerts"
	$throwRMMAlerts = $false
} 

else { 
    # Retrieve the date if the reg key exists and calculate the difference from today's date
    $registryDate = Get-Date $existingValue.$registryValueName
    $todayDate = Get-Date
    $dateDifference = ($todayDate - $registryDate).Days

    if ($dateDifference -gt 5) {
        $throwRMMAlerts = $true
    }
    else {
        # Suppress RMM alerts
        Write-Host "Still in grace period. Supressing RMM Alerts"
        $throwRMMAlerts = $false
    }
}

# CHECK VARS
if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($checkID)) {
    if ($throwRMMAlerts) {
        Rmm-Alert -Category 'NodePing Script Issue' -Body 'Token or checkID is blank or null.'
    }
	Write-Host "Token or checkID is blank or null. Exiting script."
    exit 1 	
}

# CREATE SCHEDULED TASK
try {
    $heartbeatURL = "https://push.nodeping.com/v1?id=$checkID&checktoken=$token"
    Write-Host "Using URL $heartbeatURL"
    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"Invoke-WebRequest -URI `'$heartbeatURL`' -Method POST -UseBasicParsing`""
    $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)    
    # $taskName = # we already set the $taskName earlier
    $description = "Sends uptime check to NodePing"
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Description $description `
        -User "System"
}

catch {
    if ($throwRMMAlerts) {
        Rmm-Alert -Category 'NodePing Script Issue' -Body 'Failed to create scheduled task.'
    }
	Write-Host "Failed to create scheduled task."
    exit 1 	
}

Write-Host "Successfully created NodePing scheduled task."