# Get information about physical disks
$disks = Get-PhysicalDisk

# Loop through each disk and display relevant information
foreach ($disk in $disks) {
    # Disk information for debugging
    # Write-Host "DeviceID: $($disk.DeviceID)"
    # Write-Host "OperationalStatus: $($disk.OperationalStatus)"
    # Write-Host "HealthStatus: $($disk.HealthStatus)"
    
    # Check if the disk is unhealthy
    if (!($disk.HealthStatus -eq "Healthy")) {
      Write-Host "Disk $($disk.FriendlyName), $($disk.MediaType):"
      Write-Host "Disk $($disk.DeviceID) is unhealthy! Take corrective action."
      # Add RMM alert call here
    }
    else {
      Write-Host "Disk $($disk.FriendlyName), $($disk.MediaType):"
      Write-Host "Disk $($disk.DeviceID) is healthy."
    }
}

