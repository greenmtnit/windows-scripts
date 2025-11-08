
# Set-HKCUAllUsersRegistryValue

This is a PowerShell function to set or update a registry value under `HKEY_CURRENT_USER` (HKCU) for all existing and future user profiles on a Windows machine.

This function helps administrators with the challenge of managing configurations that are controlled by per-user registry keys. By setting per-user keys for all current and future users, administrators can effectively turn per-user settings into global settings. 

## Description

This function modifies registry keys and values under HKCU for all user profiles currently present on the machine and optionally for future users by editing the Default user registry hive. 

It supports setting any registry path, value name, value data, and value type, with options to overwrite existing values or skip them. It also backs up affected registry hives before making changes.

The function filters user profiles to local, domain, and Azure AD users only, skipping built-in and system accounts.

## Params and Examples
**See the function itself for full parameter documentation and examples.**

### One Example

Update DWORD value "UpgradeEligibility" to 1 under `HKCU\Software\Microsoft\PCHC` . This follows the default options:

- Set value for all current and future users
- Force overwrite if value already exists
- Back up hives before editing

		Set-HKCUAllUsersRegistryValue `
		    -SubKeyPath "Software\Microsoft\PCHC" `
		    -ValueName "UpgradeEligibility" `
		    -ValueData 1 `
		    -ValueType DWord `
		    -Force

## How It Works

### Modifying Existing Users
To modify existing users' `HKCU` hives, the script loads the profile list from `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ProfileList`.

The script loops through each profile, excluding system and built-in accounts. It loads each user's registry hive (the hive that would appear as `HKCU` when that user is logged in), sets the specified registry value, then unloads the user's hive.

### Modifying Future Users
The script modifies future users by editing the default user profile `C:\Users\Default\NTUSER.DAT`.

It loads the default profile hive temporarily, sets the specified registry value, then unloads the hive.

When a new user logs in for the first time, their profile will inherit the setting from the default profile.

## Damage Control - If You Mess Up
By default, the script will back up the default `NTUSER.dat` and each user's registry hive in a timestamped backup file.

The default path for backups is `C:\Windows\Temp\RegistryBackups`.

## Helper Functions for Testing
Here are functions you can use to load and unload the Default user hive `C:\Users\Default\NTUSER.DAT` for testing purposes. For example, you may wish to manually delete or edit the default user profile during testing, to make sure the function is working as intended.

	function Load-DefaultUserHive {
	    [CmdletBinding()]
	    param()

	    $TempHive = "HKLM\TempDefaultUser"
	    $NTUserDat = "C:\Users\Default\NTUSER.DAT"

	    reg load $TempHive $NTUserDat | Out-Null
	    
	    Write-Verbose "Loaded Default user hive to HKLM\TempDefaultUser."

	}
---

	function Unload-DefaultUserHive {
	    [CmdletBinding()]
	    param()

	    Write-Verbose "Unloading Default user hive..."
	    $TempHive = "HKLM\TempDefaultUser"

	    # Garbage collect to release handles before unload
	    [gc]::Collect()
	    [gc]::WaitForPendingFinalizers()

	    reg unload $TempHive | Out-Null
	        
	    Write-Verbose "Unloaded Default user hive..."

	}
