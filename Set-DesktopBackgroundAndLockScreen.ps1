# ==================================
# TODO - Sloppy Notes
# ==================================
<#
 - Add syncro var for client name
 - Update documentation at top of script
 - Add docs about updating file, name of picture file
 - Add GitHub link https://github.com/KelvinTegelaar/RunAsUser
 - Documentation
 - Read only polciy example
 - Date check
 - Add Syncro documentaiton
 - Document methods: looping, ntuser default, RunOnce script for users
#>

# ==================================
# Function Definitions
# ==================================
function Write-VerboseMessage {
    param (
        [string]$Message
    )

    if ($Verbose) {
        Write-Output $Message
    }
}

function Write-Error {
    param (
        [string]$Message
    )

    Write-Host $Message -ForegroundColor Red -BackgroundColor Yellow
}

# Used to handle SyncroMSP's scripting variables, which are strings, not true Booleans
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

# ==================================
# Variable Definitions
# ==================================

$bucketName = "client-backgrounds" # Wasabi bucket name
$s3Endpoint = "s3.wasabisys.com"
$s3Provider = "Wasabi" # S3 Provider Name, as seen in rclone config. Case Sensitive! See here: https://rclone.org/s3/
# REMOVEME
$s3AccessKey = "CHANGEME"
$s3SecretKey = "CHANGEME"
$startDate = "2025-01-15" # works with $DateCheck - if you only want settings to apply for installs after a certain date.


# Syncro Variables
# Some variables are passed in from Syncro, or, if not running in Syncro, you can assign them in the else block below.

if ($null -ne $env:SyncroModule) { 
    # Running in Syncro; import the module
    Import-Module $env:SyncroModule -DisableNameChecking
    # Convert Syncro's string variables to boolean
    $DateCheck = ConvertTo-Boolean $DateCheck
    $Verbose = ConvertTo-Boolean $Verbose
    $ChangeExistingUsers = ConvertTo-Boolean $ChangeExistingUsers

}

# If not running in Syncro, handle variables here. You can change these as needed.
else {
    $DateCheck = $true # Set to false to force to run
    $Verbose = $true  # Set this to $false to suppress messages
    $clientAbbreviation = "abc" # Will override with Syncro varialbe if running in Syncro
    $ChangeExistingUsers = "$false" # Change desktop background for users who have already logged onto the machine 
}

# ==================================
# Initial Date Check
# ==================================
if ($DateCheck) {
    $installDate = (Get-ChildItem C:/ -Hidden | Where-Object { $_.Name -like "System Volume Information" }).CreationTime
    $targetDate = Get-Date $startDate
    if ($installDate -le $targetDate) {
        Write-VerboseMessage "Machine was installed before start date. Exiting"
        exit 0
    }
    else {
        Write-VerboseMessage "Machine is newer than start date. Proceeding!"
    }
}

# ==================================
# Setup
# ==================================

# Create working directory
$workingDirectory = "C:\Program Files\Green Mountain IT Solutions\RMM\Tools"
if (-not (Get-Item $workingDirectory -ErrorAction SilentlyContinue)) {
    Write-VerboseMessage -Message "Working directory $workingDirectory not found; creating it."
    New-Item -ItemType Directory $workingDirectory | Out-Null
}
else {
    Write-VerboseMessage "Found working directory $workingDirectory; using it"
}



# Download rclone executable. Will be used to download from S3
$rcloneURL = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$rcloneDownloadPath = Join-Path -Path $workingDirectory -ChildPath "rclone-current-windows-amd64.zip"
if (-not (Get-Item $rcloneDownloadPath -ErrorAction SilentlyContinue)) {
    $ProgressPreference = "SilentlyContinue"
    Write-VerboseMessage -Message "Downloading to $rcloneDownloadPath"
    Invoke-WebRequest -Uri $rcloneURL -OutFile $rcloneDownloadPath
}
else {
    Write-VerboseMessage "Found $rcloneDownloadPath already exists; skipping download"
}

Write-VerboseMessage "Extracting archive to $workingDirectory"
Expand-Archive -Path $rcloneDownloadPath -DestinationPath $workingDirectory -Force

# Find rclone executable
# Search for the rclone.exe file in child folders starting with "rclone"
$rclone = Get-ChildItem -Path $workingDirectory -Recurse -Filter "rclone.exe" |
          Where-Object { $_.DirectoryName -like "*\rclone*" } |
          Select-Object -ExpandProperty FullName -First 1

# Output the result
if ($rclone) {
    Write-VerboseMessage -Message "rclone.exe found at: $rclone"
} else {
    Write-Error "rclone.exe not found."
    exit 1
}

# Install the RunAsUserModule

# Check if already installed 
if (Get-Module -Name RunAsUser -ListAvailable) {
    Write-VerboseMessage "Module is already installed."
}
else {
    $moduleURL = "https://github.com/KelvinTegelaar/RunAsUser/archive/refs/heads/master.zip"
    $moduleDownloadPath = Join-Path -Path $workingDirectory -ChildPath "RunAsUser.zip"

    if (-not (Test-Path $moduleDownloadPath)) {
        $ProgressPreference = "SilentlyContinue"
        Write-VerboseMessage -Message "Downloading to $moduleDownloadPath"
        Invoke-WebRequest -Uri $moduleURL -OutFile $moduleDownloadPath
    }
    else {
        Write-VerboseMessage "Found $moduleDownloadPath already exists; skipping download"
    }

    # Unzip
    Write-VerboseMessage "Extracting archive to $workingDirectory"
    Expand-Archive -Path $moduleDownloadPath -DestinationPath $workingDirectory -Force

    # Import the Module (Manual copy)
    $modulesPath = "C:\Program Files\WindowsPowerShell\Modules"

    Write-VerboseMessage -Message "Manually copying module to $modulesPath and importing it."
    Copy-Item -Path "$workingDirectory\RunAsUser-master" -Destination $modulesPath\RunAsUser -Recurse -Force
}
Import-Module -Name "RunAsUser"

# ==================================
# MAIN SCRIPT ACTION
# ==================================

# ==================================
# Use rclone to download the image
# ==================================

# Convert client abbreviation to lowercase, so we can find the filename
$clientAbbreviation = $clientAbbreviation.ToLower()
$imagePath = "$env:Public\Pictures\background.png"

# Rename file if already exists
if (Get-Item $imagePath -ErrorAction SilentlyContinue) {
    $timeStamp = Get-Date -Format yyyyMMdd_HHmmss
    $backupPath = "${imagePath}_${timeStamp}.bak"
    Write-VerboseMessage -Message "Found $imagePath already exists; backing up file to $backupPath."
    Move-Item -Path $imagePath -Destination $backupPath
}

# rclone - we are using the :backend:path/to/dir syntax to create a remote on the fly. See https://rclone.org/docs/#backend-path-to-dir
$rcloneArgs = @(
    "copyto"
    ":s3:$bucketName/$clientAbbreviation.png"
    "$imagePath"
    "--s3-access-key-id $s3AccessKey"
    "--s3-secret-access-key $s3SecretKey"
    "--s3-endpoint $s3Endpoint"
    "--s3-provider $s3Provider"
)

# Execute the rclone command
Write-VerboseMessage "Executing command: $rclone $rcloneArgs"
try {
    Start-Process -FilePath $rclone -ArgumentList $rcloneArgs -NoNewWindow -Wait
    Write-VerboseMessage -Message "Successfully downloaded file to $imagePath"
}
catch {
    # Print error message
    Write-Error "An error occurred running rclone download!"
}

# ==================================================================
# Set Lock Screen. This applies for all users and can't be changed. 
# ==================================================================

#  If you ever need to revert, delete the entire PersonalizationCSP key
$RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
if (!(Test-Path $RegKeyPath)) {
    New-Item -Path $RegKeyPath -Force | Out-Null
}
New-ItemProperty -Path $RegKeyPath -Name "LockScreenImageStatus" -Value 1 -PropertyType DWORD -Force | Out-Null
New-ItemProperty -Path $RegKeyPath -Name "LockScreenImagePath" -Value $imagePath -PropertyType STRING -Force | Out-Null
New-ItemProperty -Path $RegKeyPath -Name "LockScreenImageUrl" -Value $imagePath -PropertyType STRING -Force | Out-Null




# =====================================================================================
# Set default desktop background for all new users (users who haven't logged in yet)
# =====================================================================================

# Create the script. We will use RunOnce to make each new user run the script
$scriptDirectory = "C:\Program Files\Green Mountain IT Solutions\Scripts"
if (-not (Get-Item $scriptDirectory -ErrorAction SilentlyContinue)) {
    Write-VerboseMessage -Message "Working directory $scriptDirectory not found; creating it."
    New-Item -ItemType Directory $scriptDirectory | Out-Null
}
else {
    Write-VerboseMessage "Found working directory $scriptDirectory; using it"
}

$scriptContent = @'
$blockImagePath = "$env:Public\Pictures\background.png"
$code = @"
using System.Runtime.InteropServices;
namespace Win32{
    public class Wallpaper{
        [DllImport("user32.dll", CharSet=CharSet.Auto)]
        static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

        public static void SetWallpaper(string thePath){
            SystemParametersInfo(20, 0, thePath, 3);
        }
    }
}
"@

Add-Type $code
[Win32.Wallpaper]::SetWallpaper($blockImagePath)
'@

$scriptPath = Join-Path -Path $scriptDirectory -ChildPath "Set-DesktopBackground.ps1"

# Add content to the script
Set-Content -Path $scriptPath -Value $scriptContent

# Add RunOnce
# See https://gist.github.com/goyuix/fd68db59a4f6355ee0f6

# Define the path to the default user's NTUSER.DAT file
$ntuserDatPath = "C:\Users\Default\NTUSER.DAT"

$tempKeyName = "HKLM\TempDefaultUser"
# Define a temporary key name for loading the hive

# Load the hive
reg load $tempKeyName $ntuserDatPath
# Define the registry path
$regPath = "HKLM:\TempDefaultUser\Software\Microsoft\Windows\CurrentVersion\RunOnce"

$runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`""

New-ItemProperty -Path $regPath -Name "FirstLogonDesktopBackground" -Value $runOnceCommand -PropertyType String -Force

# Unload keys
[gc]::Collect()
reg unload $tempKeyName


# =======================================================================
# EXISTING USER CHECKS 
# =======================================================================
# Set $ChangeExistingUsers to $true to change background for users who've already logged on.

if ($ChangeExistingUsers) {
    Write-VerboseMessage "Changing settings for existing users."

    # =======================================================================
    # Loop through and set the desktop background for all existing users 
    # =======================================================================

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

    # Loop through each profile on the machine and set their reg keys for desktop background
    foreach ($Item in $ProfileList) {
        # Load User ntuser.dat if it's not already loaded
        Write-Verbose "Loading $Item.SID"
        if ($Item.SID -in $UnloadedHives.SID) {
            reg load HKU\$($Item.SID) $($Item.UserHive) | Out-Null
        }
        $regPath = "Registry::HKEY_USERS\$($Item.SID)\Control Panel\Desktop"

        #####################################################################
        # This is where you can read/modify each user's portion of the registry 
        
        # Define the values to set
        $wallpaperStyle = 10
        $tileWallpaper = 0

        # Set the WallpaperStyle value
        Set-ItemProperty -Path $regPath -Name WallpaperStyle -Value $wallpaperStyle 
        
        # Set the TileWallpaper value
        Set-ItemProperty -Path $regPath -Name TileWallpaper -Value $tileWallpaper

        # Set the Wallpaper value to the $imagePath variable
        Set-ItemProperty -Path $regPath -Name Wallpaper -Value $imagePath
        #####################################################################

        # Unload ntuser.dat        
        if ($Item.SID -in $UnloadedHives.SID) {
            # Garbage collection and closing of ntuser.dat
            [gc]::Collect()
            reg unload HKU\$($Item.SID) | Out-Null
        }
    }

    # =========================================================
    # Use RunAsUser to Set Desktop Background for Current User
    # =========================================================

    $scriptBlock = {
        # I couldn't figure out how to access $imagePath from earlier in the script when using Invoke-AsCurrentUser, so we explicity re-define it here
        $blockImagePath = "$env:Public\Pictures\background.png"
        $code = @'
        using System.Runtime.InteropServices;
        namespace Win32{
            public class Wallpaper{
                [DllImport("user32.dll", CharSet=CharSet.Auto)]
                static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
                public static void SetWallpaper(string thePath){
                    SystemParametersInfo(20, 0, thePath, 3);
                }
            }
        }
'@
    # Previous line must not be indented or you'll get a a white space error.
        Add-Type $code
    
        # Apply the change on the system
        [Win32.Wallpaper]::SetWallpaper($blockImagePath)
    } # End of $ScriptBlock

    # Execute the scriptblock and pass the $imagePath variable
    Invoke-AsCurrentUser -ScriptBlock $scriptblock
}


else {
    Write-VerboseMessage "Not changing settings for existing users."
}