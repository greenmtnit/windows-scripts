<#
    Get-FileSharePermissions.ps1
    
    Gets a list of file shares and permissions on a server.
    Gets share permissions, not NTFS permissions. See separate script for that.
    
#>

$timestamp = Get-Date -Format yyyyMMddhhmm
$hostname = $env:COMPUTERNAME
$OutFile = "C:\!TECH\FileSharePermissions_${hostname}_$timestamp.csv"

# Get all SMB shares on the server
$shares = Get-SmbShare

# Initialize an array to store share information
$shareInfo = @()

foreach ($share in $shares) {
    # Get the share permissions for each share
    $permissions = Get-SmbShareAccess -Name $share.Name

    foreach ($permission in $permissions) {
        # Create a custom object to store the share information
        $shareInfo += [PSCustomObject]@{
            ShareName = $share.Name
            Path = $share.Path
            AccountName = $permission.AccountName
            AccessControlType = $permission.AccessControlType
            AccessRight = $permission.AccessRight
        }
    }
}



# Export the share information to a CSV file
$shareInfo | Export-Csv -Path $OutFile -NoTypeInformation
Write-Host "Saved report to $OutFile."
