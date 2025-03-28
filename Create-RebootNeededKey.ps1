function Create-RebootNeededKey {
    <#
        Creates a volatile registry key to indicate whether a reboot is needed.
        
        This function creates a volatile registry key under `HKEY_LOCAL_MACHINE\SOFTWARE\Green Mountain IT Solutions\RMM`.
        The key is named `RebootNeeded`, and it stores a boolean-like value (`1` for true, `0` for false) using the `REG_DWORD` type.
        
        Volatile registry keys are temporary and only exist while the system is running; they are deleted when the system shuts down.
        
        This means we can set the volatile key to indicate a reboot is needed, and the key will automatically clear after a reboot without any cleanup required.
    
        This is used in conjuction with Show-RebootReminder. You can add this function to other scripts.
        
        For example, a script that installs software that requires a reboot can use this function to mark that a reboot is needed.
        Then, when Show-RebootReminder runs (usally automatically via RMM Policy), that script will detect if the RebootNeeded value exists to determine if the reminder should be shown.

    
        EXAMPLE of how to check the value in a script
            if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Green Mountain IT Solutions\RMM\RebootNeeded' -Name 'RebootNeeded' -ErrorAction SilentlyContinue).RebootNeeded -eq 1) {
                    Write-Output "The registry value 'RebootNeeded' is set to 1."
            } else {
                Write-Output "The registry value 'RebootNeeded' is not set to 1 or does not exist."
            }
    
    #>
    param (
        [string]$BaseKeyPath = 'SOFTWARE\Green Mountain IT Solutions',
        [string]$SubKeyPath = 'RMM',
        [string]$VolatileKeyName = 'RebootNeeded',
        [string]$ValueName = 'RebootNeeded',
        [int]$ValueData = 1 
    )

    try {
        # Open the HKEY_LOCAL_MACHINE base key
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Default)

        # Open or create the base key
        $baseKey = $hklm.CreateSubKey($BaseKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Open or create the subkey
        $subKey = $baseKey.CreateSubKey($SubKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Create a volatile subkey
        $volatileKey = $subKey.CreateSubKey($VolatileKeyName, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [Microsoft.Win32.RegistryOptions]::Volatile)

        # Set the value in the volatile key as REG_DWORD (boolean-like)
        $volatileKey.SetValue($ValueName, $ValueData, [Microsoft.Win32.RegistryValueKind]::DWord)

        Write-Output "Volatile registry key 'HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName' created with value '$ValueName' set to '$ValueData'."
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        # Close all keys
        if ($volatileKey) { $volatileKey.Close() }
        if ($subKey) { $subKey.Close() }
        if ($baseKey) { $baseKey.Close() }
        if ($hklm) { $hklm.Close() }
    }
}

# Example usage of the function
Create-RebootNeededKey
