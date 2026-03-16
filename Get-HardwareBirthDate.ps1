<# 
    Get-HardwareBirthDate.ps1
      
    Determines birth date of a computer asset.

    Uses the warranty start date from Syncro's built-in warranty tracking.
    If the built-in warranty tracking data is missing or Unknown, the script uses fallback methods based on BIOS release date and the OS install date.
    Dates generated with fallback methods are appended with (Estimated)

    Writes the output to a Syncro asset custom field named "Birth Date".
    
    Syncro Script Variables:
    $AssetBirthDate - Existing Syncro platform asset custom field "Birth Date"
    $AssetWarrantyStartDate - Syncro platform var {{asset_warranty_start_date}} (from built-in warranty tracking)
    
#>

Import-Module $env:SyncroModule

# Function to check if running in a virtual machine
function Check-VM { 
    $model = Get-CimInstance Win32_ComputerSystem | select Model
    if ($model -match "virtual") {
        return $true
    }
    return $false
}

# Check if this is a VM
if (Check-VM) {
    $discoveredBirthDate = "N/A (VM)"
}

else { # Not a VM. Get birth date.
  
    # Use Syncro built-in warranty tracking data, if present
    if (($AssetWarrantyStartDate) -and ($AssetWarrantyStartDate -ne "Unknown")) {
        $discoveredBirthDate = (Get-Date $AssetWarrantyStartDate -Format "MM/dd/yyyy")
        Write-Host "Found birth date $discoveredBirthDate from Syncro's built-in warranty tracking."
    }

    else {
        Write-Host "Start date from Syncro's built-in warranty tracking is not present or Unknown. Using fallback methods."
        
        # Check BIOS release date
        $biosDate = Get-Date (Get-CimInstance -Class Win32_BIOS).ReleaseDate -Format "MM/dd/yyyy"
        
        # Estimate OS install Date by checking the date of the System Volume Information folder
        $osInstallDate = Get-Date (Get-CimInstance Win32_OperatingSystem).InstallDate -Format "MM/dd/yyyy"

        # Use the older of the two as a best guess for age
        if ($biosDate -lt $osInstallDate) {
            $discoveredBirthDate = $biosDate
            Write-Host "Using BIOS date as estimated birth date: $discoveredBirthDate"
        } else {
            $discoveredBirthDate = $osInstallDate
            Write-Host "Using estimated OS install date as estimated birth date: $discoveredBirthDate"
        }
        $discoveredBirthDate += " (Estimated)"
    }
}

# SANITY CHECK - make sure we're not overwriting with a newer date
# Check if existing date is present
if ($AssetBirthDate) {
    
    Write-Host "Found existing Birth Date field value: $AssetBirthDate"
  
    # Remove "(Estimated)" from variables, if present - strip out just the date

    $pattern = "(\d{2}/\d{2}/\d{4})"
    if ($AssetBirthDate -match $pattern) {
        $dateOnly = $matches[1]
        $AssetBirthDate = $dateOnly
    }
    
    if ($discoveredBirthDate -match $pattern) {
        $dateOnly = $matches[1]
        $discoveredBirthDateCleaned = $dateOnly
    }
    else { # If no (estimated) in $discoveredBirthDate, use as-is
        $discoveredBirthDateCleaned = $discoveredBirthDate
    }
    
    $AssetBirthDate = Get-Date $AssetBirthDate
    $discoveredBirthDateCleaned = Get-Date $discoveredBirthDateCleaned
               
    if ($discoveredBirthDateCleaned -gt $AssetBirthDate) { 
        # Discovered birth date is newer than existing date. Older value is likely more accurate, so don't overwrite it.
        Write-Host "Warning! The discovered birth date is newer than the existing asset Birth Date field. Will not overwrite."
        Exit 0
    }
    elseif ($discoveredBirthDateCleaned -eq $AssetBirthDate) {
        # Dates are the same. No update needed.
        Write-Host "Discovered birth date is the same as the existing asset Birth Date field. No update needed."
        Exit 0
    }
    else {
        Write-Host "Discovered birth date is older than existing asset Birth Date field. Will overwrite."
    }
}

# Write birth date to asset custom field
Write-Host "Writing value $discoveredBirthDate to asset Birth Date field"
Set-Asset-Field -Name "Birth Date" -Value "$discoveredBirthDate"


