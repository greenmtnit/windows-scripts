Import-Module $env:SyncroModule

# Define the service names
$ServiceNames = @('IDEXXApplicationServer', 'IDEXXLabsServer')

# Function to start a service with retries
function Start-ServiceWithRetries {
    param(
        [string]$ServiceName,
        [int]$MaxAttempts = 3,
        [int]$RetryIntervalSeconds = 20

    )

    $attempts = 0
    $service = Get-Service $ServiceName

    while (($service.Status -ne 'Running') -and ($attempts -lt $MaxAttempts)) {
        $attempts++
        Write-Host "Attempt $attempts : Starting service $ServiceName"
        Start-Service $ServiceName
        Start-Sleep -Seconds $RetryIntervalSeconds
        if ($service.Status -eq 'Running') {
            Write-Host "Service $ServiceName was found stopped and was successfully started by script."
            Log-Activity -Message "Service $ServiceName was not running and was started by script." -EventName "Service Started by Script"
        }
    } 

    if ($service.Status -eq 'Running') {
        Write-Host "Service $ServiceName is running."
        return $true
    } else {
        Write-Host "Failed to start service $ServiceName after $MaxAttempts attempts."
        return $false
    }
}

# Attempt to start each service
foreach ($ServiceName in $ServiceNames) {
    if (Start-ServiceWithRetries -ServiceName $ServiceName) {
        # Close the alert if service started successfully
        Close-Rmm-Alert -Category "IDEXX Services" -CloseAlertTicket "true"
    } else {
        # Create an RMM alert if service failed to start
        Rmm-Alert -Category 'IDEXX Services' -Body "Failed to start $ServiceName after multiple attempts"
    }
}
