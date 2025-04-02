<#
Clear-RecentFiles.ps1
Thanks to https://gist.github.com/tylerapplebaum/de9ea8d65c519ff52f149106672e6c52

For all users:
- Clears \AppData\Roaming\Microsoft\Windows\Recent
- Sets registry keys to disable and then re-enable displaying recent files, to complete the clear

Uses RunAsUser module to execute for the currently-logged in user.

#>

# Get all user directories in C:\Users
$users = Get-ChildItem -Path "C:\Users" | Where-Object {
    $_.PSIsContainer -and $_.Name -notmatch "Public" -and $_.Name -notmatch "Default*"
}

# Loop through each user directory and clear recent
foreach ($user in $users) {
    $recentFolder = "$($user.FullName)\AppData\Roaming\Microsoft\Windows\Recent"
    
    # Check if the Recent folder exists
    If (Test-Path $recentFolder) {
        Write-Host "Removing files from: $recentFolder"
        
        # Remove all files in the Recent folder
        Get-ChildItem -Path $recentFolder -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    } else {
        Write-Host "Recent folder does not exist for: $($user.Name)"
    }
}

# Loop through registry for non-logged in users and set keys

# Regex pattern for SIDs
# S-1-5-21 = local or domain user
# S-1-12-1 = Azure AD user
$PatternSID = 'S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$'

# Get Username, SID, and location of ntuser.dat for all users
$ProfileList = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
    Where-Object { $_.PSChildName -match $PatternSID } |
    Select-Object @{Name="SID"; Expression={ $_.PSChildName }},
                @{Name="UserHive"; Expression={ "$($_.ProfileImagePath)\ntuser.dat" }},
                @{Name="Username"; Expression={ $_.ProfileImagePath -replace '^(.*[\\\/])', '' }}

# Get all user SIDs found in HKEY_USERS (ntuser.dat files that are loaded)
$LoadedHives = Get-ChildItem -Path Registry::HKEY_USERS |
    Where-Object { $_.PSChildName -match $PatternSID } |
    Select-Object @{Name="SID"; Expression={ $_.PSChildName }}

# Get all users that are not currently logged in
$UnloadedHives = Compare-Object -ReferenceObject $ProfileList.SID -DifferenceObject $LoadedHives.SID |
    Select-Object @{Name="SID"; Expression={ $_.InputObject }}, UserHive, Username

# Loop through each profile on the machine and set their reg keys
foreach ($Item in $ProfileList) {
    # Load User ntuser.dat if it's not already loaded
    Write-Verbose "Loading $Item.SID"
    if ($Item.SID -in $UnloadedHives.SID) {
        reg load HKU\$($Item.SID) $($Item.UserHive) | Out-Null
    }
    $regPath = "Registry::HKEY_USERS\$($Item.SID)\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    #####################################################################
    # This is where you can read/modify each user's portion of the registry 

    # Backup current values before changing
    #####################################################################

    New-ItemProperty -Path $regPath -Name "Start_TrackDocs" -Value 0 -PropertyType DWORD
    Remove-ItemProperty -Path $regPath -Name "Start_TrackDocs"


    # Unload ntuser.dat        
    if ($Item.SID -in $UnloadedHives.SID) {
        # Garbage collection and closing of ntuser.dat
        [gc]::Collect()
        reg unload HKU\$($Item.SID) | Out-Null
    }
}

# =========================================================
# Use RunAsUser to Set Registry for the Current User
# =========================================================
# Install the RunAsUserModule

# Check if already installed 
if (Get-Module -Name RunAsUser -ListAvailable) {
    Write-Host "RunAsUser Module is already installed; skipping install"
}
else {
    $moduleURL = "https://github.com/KelvinTegelaar/RunAsUser/archive/refs/heads/master.zip"
    $moduleDownloadPath = Join-Path -Path $toolsDirectory -ChildPath "RunAsUser.zip"

    if (-not (Test-Path $moduleDownloadPath)) {
        $ProgressPreference = "SilentlyContinue"
        Write-Host -Message "Downloading to $moduleDownloadPath"
        Invoke-WebRequest -Uri $moduleURL -OutFile $moduleDownloadPath
    }
    else {
        Write-Host "Found $moduleDownloadPath already exists; skipping download"
    }

    # Unzip
    Write-Host "Extracting archive to $toolsDirectory"
    Expand-Archive -Path $moduleDownloadPath -DestinationPath $toolsDirectory -Force

    # Import the Module (Manual copy)
    $modulesPath = "C:\Program Files\WindowsPowerShell\Modules"

    Write-Host -Message "Manually copying module to $modulesPath and importing it."
    Copy-Item -Path "$toolsDirectory\RunAsUser-master" -Destination $modulesPath\RunAsUser -Recurse -Force
}
Import-Module -Name "RunAsUser"


$scriptBlock = {
    New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 0 -PropertyType DWORD
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs"
} 

# Execute the scriptblock
Invoke-AsCurrentUser -ScriptBlock $scriptblock

