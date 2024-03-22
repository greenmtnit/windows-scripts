function Process-Disk {
    param (
        [Microsoft.Management.Infrastructure.CimInstance]$Disk
    )

    Write-Output "Disk Model: $($Disk.Model)"
    Write-Output "Disk Size: $($Disk.Size)"
    # Add more processing as needed
}

# Example usage:
$disks = Get-PhysicalDisk
foreach ($disk in $disks) {
    Process-Disk -Disk $disk
}
