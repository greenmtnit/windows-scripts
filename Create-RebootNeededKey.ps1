function Create-RebootNeededKey {
    <#
        Creates a volatile registry key to indicate whether a reboot is needed.
        
        This function creates a volatile registry key under `HKEY_LOCAL_MACHINE\SOFTWARE\Green Mountain IT Solutions\RMM\RebootReminder`.
        The key is named `RebootNeeded`, and it stores a boolean-like value (`1` for true, `0` for false) using the `REG_DWORD` type.
        
        Volatile registry keys are temporary and only exist while the system is running; they are deleted when the system shuts down.
        
        This means we can set the volatile key to indicate a reboot is needed, and the key will automatically clear after a reboot without any cleanup required.
    
        This is used in conjuction with Show-RebootReminder. You can add this function to other scripts.
        TODO - update notes on related scripts.
        
        For example, a script that installs software that requires a reboot can use this function to mark that a reboot is needed.
        Then, when Show-RebootReminder runs (usally automatically via RMM Policy), that script will detect if the RebootNeeded value exists to determine if the reminder should be shown.
    
        EXAMPLE of how to check the value in a script
            $RebootNeededPath = "HKLM:\SOFTWARE\Green Mountain IT Solutions\RMM\RebootReminder\RebootNeeded"
            if ((Get-ItemProperty -Path $RebootNeededPath -Name "RebootNeeded" -ErrorAction SilentlyContinue).RebootNeeded -eq 1) {
                    Write-Output "The registry value RebootNeeded is set to 1."
            } else {
                Write-Output "The registry value RebootNeeded is not set to 1 or does not exist."
            }
    
    #>
    param (
        [string]$ParentKeyPath = 'SOFTWARE\Green Mountain IT Solutions\RMM\RebootReminder',
        [string]$VolatileKeyName = 'RebootNeeded',
        [string]$ValueName = 'RebootNeeded',
        [int]$ValueData = 1
    )

    try {
        # Open the parent key directly, requesting write access (writable = $true).
        # This matches the working test - OpenSubKey succeeds here because the
        # ACL grant on RebootReminder allows this user to open it writable,
        # even though they can't CreateSubKey their way down from HKLM root.
        $parentKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($ParentKeyPath, $true)

        if ($null -eq $parentKey) {
            throw "Parent key 'HKLM\$ParentKeyPath' does not exist or is not accessible. Run Grant-RebootReminderParentAccess as admin first."
        }

        # Create (or open, if it already exists) the volatile counter subkey
        $volatileKey = $parentKey.CreateSubKey($VolatileKeyName, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [Microsoft.Win32.RegistryOptions]::Volatile)

        $volatileKey.SetValue($ValueName, $ValueData, [Microsoft.Win32.RegistryValueKind]::DWord)
        Write-Output "Volatile registry key 'HKEY_LOCAL_MACHINE\$ParentKeyPath\$VolatileKeyName' - value '$ValueName' set to '$ValueData'."
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}

# Example usage of the function
Create-RebootNeededKey
