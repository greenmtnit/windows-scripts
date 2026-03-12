<#
    Get-DiskInfo.ps1
    
    Gets disk number, model, serial, if USB or not, and partions list for all disks.
    Saves the info to a text file and uploads to the Syncro asset page.
    
#>

Import-Module $env:SyncroModule

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$path = "C:\!TECH\DiskInfo_$timestamp.txt"

Get-PhysicalDisk | ForEach-Object { 
    $disk = $_
    $isUSB = ($disk.BusType -eq 'USB')
    $partitions = Get-Partition -DiskNumber $disk.DeviceID | ForEach-Object { "$($_.DriveLetter): $([math]::Round($_.Size/1GB,2)) GB" } 
    [PSCustomObject]@{
        DiskNumber    = $disk.DeviceID
        Model         = $disk.FriendlyName
        SerialNumber  = $disk.SerialNumber
        USB           = $isUSB
        Partitions    = ($partitions -join ', ')
    }
} | Format-Table | Out-File $path

Write-Host "Saved disk info to file $path. Uploading to Syncro asset now."

Upload-File -FilePath $path