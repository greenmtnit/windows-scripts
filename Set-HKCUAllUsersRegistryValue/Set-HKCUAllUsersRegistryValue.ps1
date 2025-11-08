function Set-HKCUAllUsersRegistryValue {
    <#
    .SYNOPSIS
        Sets or updates a registry value under HKEY_CURRENT_USER for all current and future users on the local machine.

    .DESCRIPTION
        This function modifies registry keys and values under HKCU for all user profiles currently on the machine and/or for future user profiles 
        (by updating the Default user hive). It supports setting any registry path, value name, value data, and type, with options to overwrite 
        existing values or skip them. It also provides an optional backup of affected registry hives before modification.

    .PARAMETER SubKeyPath
        The relative registry path under HKCU where the value will be created or updated for each user. For example: "Software\Microsoft\PCHC".

    .PARAMETER ValueName
        The name of the registry value to set.

    .PARAMETER ValueData
        The data to assign to the registry value.

    .PARAMETER ValueType
        The type of the registry value. Valid options: String, ExpandString, DWord, QWord, Binary, MultiString.

    .PARAMETER Force
        Switch to overwrite existing registry values. If not specified and the value exists, it will be skipped.

    .PARAMETER NoBackup
        Switch to disable backing up each user hive before modification. By default, backup is enabled.

    .PARAMETER BackupPath
        The folder path where registry backups will be stored. Default is "C:\Windows\Temp\RegistryBackups".

    .PARAMETER ModifyExistingUsers
        Switch to enable modifying all existing user profile registry hives. Default is enabled.

    .PARAMETER ModifyFutureUsers
        Switch to enable modifying the Default user hive (which affects future new user profiles). Default is enabled.

    .EXAMPLE
        Set-HKCUAllUsersRegistryValue -SubKeyPath "Software\MyApp" -ValueName "Enabled" -ValueData 1 -ValueType DWord -Force

        Updates or creates the DWORD registry value "Enabled" with data 1 under HKCU\Software\MyApp for all current and future users,
        overwriting existing values and backing up hives before modification.

    .EXAMPLE
        Set-HKCUAllUsersRegistryValue `
            -SubKeyPath "Software\ContosoApp" `
            -ValueName "UserPreference" `
            -ValueData "DarkMode" `
            -ValueType String `
            -ModifyFutureUsers:$false `
            -Verbose
            
        Set a string registry value for all current users only, without modifying future user profiles,
        and without forcing overwrite if the value already exists (no $Force).

    .NOTES
        - Requires administrative privileges to load/unload user hives.
        - Only modifies local, domain, and Azure AD user profiles, avoiding system accounts.
        - Uses built-in support (SupportsShouldProcess) for -WhatIf and -Confirm via CmdletBinding.

    .LINK
        None
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SubKeyPath,  # e.g. "Software\Microsoft\PCHC"

        [Parameter(Mandatory)]
        [string]$ValueName,   # e.g. "UpgradeEligibility"

        [Parameter(Mandatory)]
        [string]$ValueData,   # e.g. 1

        [Parameter(Mandatory)]
        [ValidateSet('String','ExpandString','DWord','QWord','Binary','MultiString')]
        [string]$ValueType,

        [switch]$Force,                   # Overwrite existing values
        [switch]$NoBackup,                # Disable registry backup
        [string]$BackupPath = "C:\Windows\Temp\RegistryBackups",

        [switch]$ModifyExistingUsers = $true,
        [switch]$ModifyFutureUsers = $true
    )

    Write-Verbose "Starting Set-HKCUAllUsersRegistryValue for $SubKeyPath\$ValueName"

    # Define regex to match only desired SIDs. This matches local, domain, and Azure AD (Entra) users.
    # It will not match system or built-in users.
    #   S-1-5-21 = local or domain user
    #   S-1-12-1 = Azure AD user
    $PatternSID = 'S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$'

    if (-not $NoBackup) {
        if (-not (Test-Path $BackupPath)) { New-Item -ItemType Directory -Path $BackupPath | Out-Null }
    }

    function Backup-Hive ($RootPath, $Username) {
        if (-not $NoBackup) {
            $BackupFile = Join-Path $BackupPath "$($Username)_$(Get-Date -Format 'yyyyMMdd_HHmmss').regbak"
            Write-Verbose "Backing up $RootPath to $BackupFile"
            # Use full path for REG.EXE export
            reg export $RootPath $BackupFile /y | Out-Null 2>&1
        }
    }
    
    function Backup-NTUserDat ($UserHivePath, $Username) {
        if (-not $NoBackup) {
            $BackupFile = Join-Path $BackupPath "$($Username)_NTUSER_$(Get-Date -Format 'yyyyMMdd_HHmmss').dat"
            Write-Verbose "Backing up NTUSER.DAT for $Username to $BackupFile"
            Copy-Item -Path $UserHivePath -Destination $BackupFile -Force
        }
    }

    function Set-RegistryValueForHive($RootPath, $Username) {
        $TargetRegPath = Join-Path $RootPath $SubKeyPath
        if (-not (Test-Path $TargetRegPath)) { New-Item -Path $TargetRegPath -Force | Out-Null }
        
        $existing = Get-ItemProperty -Path $TargetRegPath -Name $ValueName -ErrorAction SilentlyContinue
        if ($existing -and -not $Force) {
            Write-Verbose "Skipping $Username, value already exists and -Force not specified."
        } else {
            Write-Verbose "Setting $TargetRegPath\$ValueName => $ValueData"
            New-ItemProperty -Path $TargetRegPath -Name $ValueName -Value $ValueData -PropertyType $ValueType -Force | Out-Null
        }
    }

    if ($ModifyExistingUsers) {
        Write-Verbose "Modifying existing users' hives..."
        $ProfileList = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
            Where-Object { $_.PSChildName -match $PatternSID } |
            Select-Object @{Name="SID"; Expression={ $_.PSChildName }},
                          @{Name="HivePath"; Expression={ "$($_.ProfileImagePath)\NTUSER.DAT" }},
                          @{Name="Username"; Expression={ Split-Path $_.ProfileImagePath -Leaf }}

        $LoadedHives = Get-ChildItem -Path Registry::HKEY_USERS |
            Where-Object { $_.PSChildName -match $PatternSID } |
            Select-Object -ExpandProperty PSChildName

        foreach ($User in $ProfileList) {
            $HiveWasLoaded = $true
            if ($User.SID -notin $LoadedHives) {
                Write-Verbose "Loading hive for $($User.Username)"
                reg load "HKU\$($User.SID)" $User.HivePath | Out-Null
                $HiveWasLoaded = $false
            }

            Backup-Hive "HKU\$($User.SID)" $User.Username
            Set-RegistryValueForHive "Registry::HKEY_USERS\$($User.SID)" $User.Username

            if (-not $HiveWasLoaded) {
                [gc]::Collect()
                reg unload "HKU\$($User.SID)" | Out-Null
            }
        }
    }

    if ($ModifyFutureUsers) {
        Write-Verbose "Backing up Default User NTUSER.DAT"
        Backup-NTUserDat "C:\Users\Default\NTUSER.DAT" "DefaultUser"
        
        Write-Verbose "Modifying Default User hive for future users..."
        $TempHive = "HKLM\TempDefaultUser"
        $NTUserDat = "C:\Users\Default\NTUSER.DAT"

        reg load $TempHive $NTUserDat | Out-Null

        $DefaultRegPath = "Registry::HKEY_LOCAL_MACHINE\TempDefaultUser\$SubKeyPath"
        if (-not (Test-Path $DefaultRegPath)) { New-Item -Path $DefaultRegPath -Force | Out-Null }

        Backup-Hive "HKLM\TempDefaultUser" "DefaultUser"
        Set-RegistryValueForHive "Registry::HKEY_LOCAL_MACHINE\TempDefaultUser" "DefaultUser"

        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        reg unload $TempHive | Out-Null
    }

    Write-Verbose "Completed registry modifications."
}