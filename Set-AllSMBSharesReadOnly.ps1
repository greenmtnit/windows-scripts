# Sets all file shares to read-only

# Define the default shares to exclude
$defaultExcludedShares = @("ADMIN$", "IPC$", "NETLOGON", "PRINT$", "SYSVOL")

# Define the custom shares to exclude
#$customExcludedShares = @("Share1", "Share2") # Example
$customExcludedShares = "" # No non-default exclusions

# Define the path to the backup file
$timestamp = Get-Date -Format yyyyMMddhhmm
$hostname = $env:COMPUTERNAME
$backupFilePath = "C:\!TECH\SMBSharePermissionsBackup_${hostname}_$timestamp.csv"

### Main Script Starts Here

# Confirm
do {
    $confirmation = Read-Host "Are you sure to set file shares to read-only? Type 'YES' to proceed or 'N' to cancel"
    if ($confirmation -eq 'N') {
        Write-Output "Operation cancelled."
        exit
    }
} while ($confirmation -ne 'YES')

Write-Output "Confirmed. Proceeding with the operation!"

# Create array of excluded shares
$excludedShares = $defaultExcludedShares + $customExcludedShares

# Initialize an array to store the backup data
$backupData = @()

# Get all file shares
$shares = Get-SmbShare

foreach ($share in $shares) {
    # Check if the share is in the excluded list or if it matches the pattern for single letter shares
    if ($excludedShares -contains $share.Name -or $share.Name -match '^[A-Z]\$$') {
        Write-Output "Skipping excluded share: $($share.Name)"
        continue
    }

    # Get the current access permissions for the share
    $accessList = Get-SmbShareAccess -Name $share.Name

    # Backup the current access permissions
    foreach ($access in $accessList) {
        $backupData += [PSCustomObject]@{
            ShareName   = $share.Name
            AccountName = $access.AccountName
            AccessRight = $access.AccessRight
        }
    }

    # Modify each access entry to read-only
    foreach ($access in $accessList) {
        Grant-SmbShareAccess -Name $share.Name -AccountName $access.AccountName -AccessRight Read -Force | Out-Null
    }

    Write-Output "Set share $($share.Name) to read-only"
}

# Export the backup data to a CSV file
$backupData | Export-Csv -Path $backupFilePath -NoTypeInformation

Write-Output "SMB share permissions have been backed up to $backupFilePath"
