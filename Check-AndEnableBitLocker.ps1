if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

<#
  Check-AndEnableBitLocker.ps1
  
  WHAT THIS SCRIPT DOES
   - Checks BitLocker status.
   - Backs up BitLocker info, if present, to a Syncro asset custom field
   - Does NOT enable BitLocker on Intune-managed devices (we use Intune policies for that), but does check for BitLocker enablement.
   - Enables BitLocker for non-Intune managed devices where the $UseBitlockerEncryption Syncro field is set to "true" the client
      
  SYNCRO VARIABLES TO SET
   - Create an asset custom field named "BitLockerRecoveryInfo" and add to script as:
   - $existingBitlockerInfo - Type = platform - {{asset_custom_field_bitlockerrecoveryinfo}
   - Create a organization (customer) custom field (checkbox) called "UseBitlockerEncryption" and check the box for clients who use BitLocker. Add to script as:
   - $UseBitlockerEncryption - Type = platform - {{customer_custom_field_usebitlockerencryption}}
   - $DisableSkippingServers - Type = dropdown - "true" or "false" (default false). Turn off the check that skips servers.
  TODO
   - By default, enable Bitlocker on non-VM server OS
  
#>

# FUNCTIONS

# Function to handle Syncro's variables
function ConvertTo-Boolean {
    param (
        [string]$value
    )
    switch ($value.ToLower()) {
        'true' { return $true }
        '1' { return $true }
        't' { return $true }
        'y' { return $true }
        'yes' { return $true }
        'false' { return $false }
        '0' { return $false }
        'f' { return $false }
        'n' { return $false }
        'no' { return $false }
        default { throw "Invalid boolean string: $value" }
    }
}

# Function to back up Bitlocker info to Syncro
function Save-BitlockerInfoToSyncro {
    # Get BitLocker information for all volumes
    $BitlockerVolumes = Get-BitLockerVolume

    # Initialize a variable to store all BitLocker info
    $newBitlockerInfo = ""

    foreach ($BitlockerVolume in $BitlockerVolumes) {
        if (-not $BitlockerVolume.KeyProtector) { # Empty / blank key protectors
            Write-Host "No BitLocker key protectors found on volume $($BitlockerVolume.MountPoint), skipping."      
        }
        
        else {
            Write-Host "BitLocker key protectors found on volume $($BitlockerVolume.MountPoint)."

            # Get ID and key
            $RecoveryProtector = $BitlockerVolume.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}
            $Id  = [string]$RecoveryProtector.KeyProtectorID
            $Key = [string]$RecoveryProtector.RecoveryPassword
            $volumeInfo = "Volume $($BitlockerVolume.MountPoint): ID = $Id key = $Key"
            Write-Host "Found BitLocker info: $volumeInfo"

            # Append the volume info to the new BitLocker info
            $newBitlockerInfo += "$volumeInfo`n"
        }
    }

    # Trim the trailing newline character
    $newBitlockerInfo = $newBitlockerInfo.TrimEnd("`r", "`n")

    if ([string]::IsNullOrWhiteSpace($newBitlockerInfo)) {
        Write-Host "New BitLocker info is blank, will not save blank info to Syncro."
    }

    # No existing BitLocker info. Save found info to Syncro.
    elseif ([string]::IsNullOrWhiteSpace($existingBitlockerInfo)) {
        Write-Host "No existing BitLocker info found, uploading new info to Syncro."
        Set-Asset-Field -Name "BitLockerRecoveryInfo" -Value $newBitlockerInfo
        return
    }

    # Found identical BitLocker info. Skip saving.
    elseif ($existingBitlockerInfo -like "*$newBitlockerInfo*") {
        Write-Host "New BitLocker info matches existing BitLocker info. No update needed."
    }
    
    else {
        # BitLocker info has changed. Save new info to Syncro.
        Write-Host "Found BitLocker info differs from stored value. Updating Syncro asset field."
        Set-Asset-Field -Name "BitLockerRecoveryInfo" -Value $newBitlockerInfo
    }
}

# VARIABLES
# Category for Syncro RMM Alerts
$alertCategory = "BitLocker"

# Convert Syncro's string variables to boolean
$UseBitlockerEncryption = ConvertTo-Boolean $UseBitlockerEncryption
$DisableSkippingServers = ConvertTo-Boolean $DisableSkippingServers

# PRECONDITION CHECKS
# Check if device is a server
if (-not ($DisableSkippingServers)) {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($osInfo.ProductType -ne 1) {
        Write-Host "This is a server. The script will NOT enable BitLocker if not already enabled, but will back up any existing BitLocker info to Syncro. Note: use `$DisableSkippingServers = true to override this behavior."
        Save-BitlockerInfoToSyncro
        exit
    }
}

# Check for BitLocker support
if (-Not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    Write-Host "Get-BitLockerVolume command not found! This system may not support Bitlocker."
    if ($UseBitlockerEncryption) {
        $message = "Client platform variable UseBitlockerEncryption is set, but this system does not support BitLocker. You should investigate."
        Write-Host $message
        Rmm-Alert -Category $alertCategory -Body $message
    }
    exit
}

# Check platform variable UseBitlockerEncryption
if (-not $UseBitlockerEncryption) {
    Write-Host "UseBitlockerEncryption platform variable not set. The script will NOT enable BitLocker if not already enabled, but will back up any existing BitLocker info to Syncro."
    Save-BitlockerInfoToSyncro
    exit
}

# Detect Intune (MDM) enrollment status
$mdmEnrollment = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo" -ErrorAction SilentlyContinue

# Detect BitLocker status for C:
$bitlockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
$bitlockerEnabled = ($bitlockerStatus -and (($bitlockerStatus.ProtectionStatus -eq "On") -or ($bitlockerStatus.VolumeStatus -eq "EncryptionInProgress")))

# Handle Possible Scenarios: Intune-managed or not; BitLocker enabled or not

# 1. Intune joined & BitLocker NOT enabled — throw alert
if ($mdmEnrollment -and -not $bitlockerEnabled) {
    $message = "Device is Intune-joined but BitLocker is not enabled on C:. Investigate Intune policy enforcement."
    Write-Host $message
    Rmm-Alert -Category $alertCategory -Body $message
    exit
}

# 2. Intune joined & BitLocker enabled — backup Bitlocker data
if ($mdmEnrollment -and $bitlockerEnabled) {
    Write-Host "Detected Intune-joined device with BitLocker already enabled."
    Close-Rmm-Alert -Category $alertCategory -CloseAlertTicket "true"
}

# 3. Not Intune & BitLocker NOT enabled — try to enable, then backup
if (-not $mdmEnrollment -and -not $bitlockerEnabled) {
    Write-Host "Detected non-Intune device with BitLocker not enabled. Attempting to enable BitLocker!"

    # Check TPM
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    
    # Handle no TPM
    if (-not ($tpm.TpmPresent -and $tpm.TpmReady)) {
        $message = "TPM not available or not ready. Cannot enable BitLocker."
        Write-Host $message
        Rmm-Alert -Category $alertCategory -Body $message
    }
    
    else # TPM present, proceed
    {
        try {
            # Add recovery password protector if not present
            if (-not ($bitlockerStatus.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })) {
                Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector -ErrorAction Stop
                Write-Host "Added BitLocker recovery key protector."
            }

            Write-Host "Enabling BitLocker with TPM protector..."
            Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TPMProtector -UsedSpaceOnly -SkipHardwareTest -ErrorAction Stop
            Resume-BitLocker -MountPoint "C:" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5 #Short Delay to wait for enablement
            Write-Host "BitLocker enablement command issued successfully. Backing up recovery info."
            Close-Rmm-Alert -Category $alertCategory -CloseAlertTicket "true"
        }
        catch {
            $message = "BitLocker enablement failed: $_"
            Write-Host $message
            Rmm-Alert -Category $alertCategory -Body $message
        }
    }
}

# 4. Not Intune & BitLocker enabled
if (-not $mdmEnrollment -and $bitlockerEnabled) {
    Write-Host "Detected non-Intune device with BitLocker already enabled."
    Close-Rmm-Alert -Category $alertCategory -CloseAlertTicket "true"
}

# Final failsafe: attempt to back up Bitlocker info to Syncro in all cases
Save-BitlockerInfoToSyncro