<#
.SYNOPSIS
    [Brief description of what the script does]

.DESCRIPTION
    [Detailed description of the script's functionality and usage]

.PARAMETER <ParameterName>
    [Description of the parameter]

.PARAMETER <ParameterName>
    [Description of the parameter]

.EXAMPLE
    [Example of how to use the script]
    PS C:\> .\YourScript.ps1 -Parameter1 value1 -Parameter2 value2

.EXAMPLE
    [Another example of how to use the script]
    PS C:\> .\YourScript.ps1 -Parameter1 value1 -Parameter2 value2

.NOTES
    Author: [Your Name]
    Date: [Date]
    Version: [Version]
    Additional Notes: [Any additional notes]

.LINK
    [Link to related documentation or resources]

#>

# ==================================
# TODO
# ==================================
<#
 - Put verbose as Syncro var
 - Add syncro var for client name
 - Update documentation at top of script
 - Add docs about updating file
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$s3AccessKey,

    [Parameter(Mandatory=$true)]
    [string]$s3SecretKey
)

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


# ==================================
# Variable Definitions
# ==================================
$Verbose = $true  # Set this to $false to suppress messages

$localClientAbbreviation = "roadside" # Will override if running in Syncro
$bucketName = "client-backgrounds" # Wasabi bucket name
$s3Endpoint = "s3.wasabisys.com"
$s3Provider = "Wasabi" # S3 Provider Name, as seen in rclone config. Case Sensitive! See here: https://rclone.org/s3/

# API keys




if ($null -ne $env:SyncroModule) { 
    # Running in Syncro; import the module
    Import-Module $env:SyncroModule -DisableNameChecking
}
else {
    # Not running in Syncro; use local variables. If running in Syncro, $clientAbbrevation will be pulled from Syncro vars.
    $clientAbbreviation = $localClientAbbreviation
}

# ==================================
# Use rclone to download the image
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

# Download rclone
$rcloneURL = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$downloadPath = Join-Path -Path $workingDirectory -ChildPath "rclone-current-windows-amd64.zip"
if (-not (Get-Item $downloadPath -ErrorAction SilentlyContinue)) {
    $ProgressPreference = "SilentlyContinue"
    Write-VerboseMessage -Message "Downloading rclone to $downloadPath"
    Invoke-WebRequest -Uri $rcloneURL -OutFile $downloadPath
}
else {
    Write-VerboseMessage "Found $downloadPath already exists; skipping download"
}

# Unzip
Write-VerboseMessage "Extracting archive to $workingDirectory"
Expand-Archive -Path $downloadPath -DestinationPath $workingDirectory -Force

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

# Download the file from Wasabi

# Covnert client abbreviation to lowercase, so we can find the filename
$clientAbbreviation = $clientAbbreviation.ToLower()
$imagePath = "$env:Public\Pictures\background.png"

# Rename file if already exists
if (Get-Item $imagePath -ErrorAction SilentlyContinue) {
    $timeStamp = Get-Date -Format yyyyMMdd_HHmmss
    $backupPath = "${imagePath}_${timeStamp}.bak"
    Write-VerboseMessage -Message "Found $imagePath already exists; backing up file to $backupPath."
    Move-Item -Path $imagePath -Destination $backupPath
}

# Rclone - we are using the :backend:path/to/dir syntax to create a remote on the fly. See https://rclone.org/docs/#backend-path-to-dir
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


