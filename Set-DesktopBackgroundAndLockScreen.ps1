<#
# ===========================================
#  How to Add Client Image Files (GMITS)
# ===========================================    
- Create desktop background file:
    - PNG file
    - 1920 x 1080 or another 16:9 ratio reccomended
    - If the file is bigger than a few MB, compress the file: compresspng.com
    - Name file [client_name].png, e.g. evalco.PNG
- Upload to our Wasabi bucket 'client-backgrounds'
- Add the filename to the Syncro Customer Custom Field called 'BackgroundImageFile', e.g. evalco.png

# ==================================
# TODO - Sloppy Notes
# ==================================
 - Add better documentation in script itself
 - Note how to revert the script (remove reg keys, remove RunOnce, etc)
 - Explain date check and other vars
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

$bucketName = "client-backgrounds" # S3 bucket name
$s3Endpoint = "s3.wasabisys.com"
$s3Provider = "Wasabi" # S3 Provider Name, as seen in rclone config. Case Sensitive! See here: https://rclone.org/s3/

#$s3AccessKey = "YOURACCESSKEYHERE"
#$s3SecretKey = "YOURSECRETKEYHERE"

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
    $DateCheck = $true # Set to true to only run on new installs, less than $thresholdDays old
    $ThresholdDays = 14 # Less than this many days old is considered a new install by $DateCheck
    $Verbose = $true  # Set this to $false to suppress messages
    $BackgroundImageFile = "gmits.png" # This is the filename in the S3 bucket. Will override with Syncro varialbe if running in Syncro
    $ChangeExistingUsers = $true # Change desktop background for users who have already logged onto the machine 
}

# ==================================
# Initial Checks
# ==================================
if (-not ($BackgroundImageFile)) {
    Write-Error "Background image file platform var is not set! Exiting."
    exit 0
}

if (! $DateCheck) { # Skip date check
    Write-VerboseMessage "Date check disabled. Proceeding without checking install age."
}

else {
    # Check for date
    $installDate = (Get-ChildItem C:/ -Hidden | Where-Object { $_.Name -like "System Volume Information" }).CreationTime
    
    #Define default ThresholdDays
    if (! $ThresholdDays) {
        Write-VerboseMessage "`$ThresholdDays is not set. Using default value."
        $ThresholdDays = 14
    }
    
    # calculate cutoff date
    $cutoffDate = (Get-Date).AddDays(-$ThresholdDays)

    if ($installDate -lt $cutoffDate) {
        Write-VerboseMessage "This does not appear to be a new install. Exiting!"
        exit 0
    }
    else {
        Write-VerboseMessage "This appears to be a new install. Proceeding!"
    }
}
    
# ==================================
# Setup
# ==================================

# Create working directories
$baseDirectory = "C:\Program Files\Green Mountain IT Solutions"
$scriptsDirectory = Join-Path -Path $baseDirectory -ChildPath "Scripts"
$workingDirectory = Join-Path -Path $baseDirectory -ChildPath "RMM"
$toolsDirectory = Join-Path -Path $workingDirectory -ChildPath "Tools"

$directories = @($baseDirectory, $scriptsDirectory, $workingDirectory, $toolsDirectory)

foreach ($dir in $directories) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-VerboseMessage -Message "Created directory: $dir"
    }
    else {
        Write-VerboseMessage -Message "Directory already exists: $dir"
    }
}


# Download rclone executable. rclone will be used to download from S3

$rcloneURL = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$rcloneDownloadPath = Join-Path -Path $toolsDirectory -ChildPath "rclone-current-windows-amd64.zip"

# Check if rclone executable already exists
$rclone = Get-ChildItem -Path $toolsDirectory -Recurse -Filter "rclone.exe" |
          Where-Object { $_.DirectoryName -like "*\rclone*" } |
          Select-Object -ExpandProperty FullName -First 1

if ($rclone) {
    Write-VerboseMessage -Message "Found rclone at $rclone, skipping download"
}
else {
    # Download rclone executable if not found
    if (-not (Get-Item $rcloneDownloadPath -ErrorAction SilentlyContinue)) {
        $ProgressPreference = "SilentlyContinue"
        Write-VerboseMessage -Message "Downloading rclone"
        Write-VerboseMessage -Message "Downloading to $rcloneDownloadPath"
        Invoke-WebRequest -Uri $rcloneURL -OutFile $rcloneDownloadPath
    } else {
        Write-VerboseMessage "Found $rcloneDownloadPath already exists; skipping download"
    }

    Write-VerboseMessage "Extracting archive to $toolsDirectory"
    Expand-Archive -Path $rcloneDownloadPath -DestinationPath $toolsDirectory -Force

    # Find rclone executable again after extraction
    $rclone = Get-ChildItem -Path $toolsDirectory -Recurse -Filter "rclone.exe" |
              Where-Object { $_.DirectoryName -like "*\rclone*" } |
              Select-Object -ExpandProperty FullName -First 1

    Write-VerboseMessage -Message "rclone is now available at $rclone"
}

# Install the RunAsUserModule

# Check if already installed 
if (Get-Module -Name RunAsUser -ListAvailable) {
    Write-VerboseMessage "RunAsUser Module is already installed; skipping install"
}
else {
    $moduleURL = "https://github.com/KelvinTegelaar/RunAsUser/archive/refs/heads/master.zip"
    $moduleDownloadPath = Join-Path -Path $toolsDirectory -ChildPath "RunAsUser.zip"

    if (-not (Test-Path $moduleDownloadPath)) {
        $ProgressPreference = "SilentlyContinue"
        Write-VerboseMessage -Message "Downloading to $moduleDownloadPath"
        Invoke-WebRequest -Uri $moduleURL -OutFile $moduleDownloadPath
    }
    else {
        Write-VerboseMessage "Found $moduleDownloadPath already exists; skipping download"
    }

    # Unzip
    Write-VerboseMessage "Extracting archive to $toolsDirectory"
    Expand-Archive -Path $moduleDownloadPath -DestinationPath $toolsDirectory -Force

    # Import the Module (Manual copy)
    $modulesPath = "C:\Program Files\WindowsPowerShell\Modules"

    Write-VerboseMessage -Message "Manually copying module to $modulesPath and importing it."
    Copy-Item -Path "$toolsDirectory\RunAsUser-master" -Destination $modulesPath\RunAsUser -Recurse -Force
}
Import-Module -Name "RunAsUser"

# ==================================
# MAIN SCRIPT ACTION
# ==================================

# ==================================
# Use rclone to download the image
# ==================================

$imagePath = "$env:Public\Pictures\background.png"

# Rename file if already exists
if (Get-Item $imagePath -ErrorAction SilentlyContinue) {
    $timeStamp = Get-Date -Format yyyyMMdd_HHmmss
    $backupPath = "${imagePath}_${timeStamp}.bak"
    Write-VerboseMessage -Message "Found $imagePath already exists; backing up file to $backupPath."
    Move-Item -Path $imagePath -Destination $backupPath
}

# rclone - we are using the :backend:path/to/dir syntax to create a remote on the fly. See https://rclone.org/docs/#backend-path-to-dir
# we are passing a blank --config "" option to avoid an error about no config file
$rcloneArgs = @(
    "copyto"
    "--config `"`""
    ":s3:$bucketName/$BackgroundImageFile"
    "$imagePath"
    "--s3-access-key-id", $s3AccessKey
    "--s3-secret-access-key", $s3SecretKey
    "--s3-endpoint", $s3Endpoint
    "--s3-provider", $s3Provider
)


# Execute the rclone command
Write-VerboseMessage "Executing command: $rclone $rcloneArgs"
& $rclone $rcloneArgs


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

$scriptPath = Join-Path -Path $scriptsDirectory -ChildPath "Set-DesktopBackground.ps1"

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

# Source for cleanup of reg actions: https://stackoverflow.com/questions/46509349/powershell-registry-hive-unload-error
if (-not (Test-Path $regPath)) {
    Write-VerboseMessage "Reg path $regPath not found; creating it."
    $result = New-Item -Path $regPath -Force
    $result.Handle.Close()
}

$runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`""

New-ItemProperty -Path $regPath -Name "FirstLogonDesktopBackground" -Value $runOnceCommand -PropertyType String -Force | Out-Null

# Unload keys
[gc]::Collect()
[gc]::WaitForPendingFinalizers()
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

        # Backup current values before changing
        $currentWallpaperStyle = (Get-ItemProperty -Path $regPath -Name WallpaperStyle -ErrorAction SilentlyContinue).WallpaperStyle
        $currentTileWallpaper = (Get-ItemProperty -Path $regPath -Name TileWallpaper -ErrorAction SilentlyContinue).TileWallpaper
        $currentWallpaper = (Get-ItemProperty -Path $regPath -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

        $timeStamp = Get-Date -Format yyyyMMdd_HHmmss
        $backupPath = Join-Path -Path $scriptsDirectory -ChildPath "personalization_settings_backup_$($Item.SID).txt"
        "WallpaperStyle: $currentWallpaperStyle`nTileWallpaper: $currentTileWallpaper`nWallpaper: $currentWallpaper" | Out-File -FilePath $backupPath
        
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