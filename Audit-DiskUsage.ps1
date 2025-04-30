<#
.SYNOPSIS
    Scans C:\ and C:\Users directories for files larger than 50MB, generates reports, converts them to CSV, and uploads them to Syncro.

.DESCRIPTION
    This script uses Swiss File Knife (sfk.exe) to scan directories for large files (over 50MB), saves the results to a text file, 
    converts the text report to CSV format (handling file paths with commas), and uploads the CSV to Syncro using the Upload-File cmdlet.
    Designed for use in Syncro environments, but can be adapted for general use.

.NOTES
    Adapted from Syncro Community Script Library Audit-Disk-Usage script:
    https://<your_syncro_subdomain>.syncromsp.com/shared_scripts/47
    Output files are saved in C:\temp\ and uploaded to the Syncro asset
#>

# Import the SyncroModule module if running in Syncro
if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

# FUNCTIONS

# Function to scan and list files larger than 50MB in the specified directory
function Get-LargeFiles {
    param(
        [string]$Directory,
        [string]$OutputFile
    )

    # Scan and list files larger than 50MB in the specified directory
    # This usually takes about a minute or less
    & $sfkPath stat -minsize=50m -gb $Directory | Sort-Object -Descending | Select-Object -First 100 > $OutputFile

}

function Convert-SfkReportToCsv {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,
        [Parameter(Mandatory=$true)]
        [string]$OutputCsv
    )

    Get-Content $InputPath |
        Where-Object { $_ -match '^\s*\d+\s*mb,' } |
        ForEach-Object {
            if ($_ -match '^\s*(\d+)\s*mb,\s*(.+)$') {
                [PSCustomObject]@{
                    SizeInMB = $matches[1]
                    FilePath   = $matches[2]
                }
            }
        } |
        Export-Csv $OutputCsv -NoTypeInformation
}

# MAIN SCRIPT

# Download Swiss File Knife
$sfkPath = "C:\temp\sfk.exe"
$sfkUrl = "http://stahlworks.com/dev/sfk/sfk.exe"

# Create the directory if it doesn't exist
if (-not (Test-Path (Split-Path $sfkPath))) {
    New-Item -Path (Split-Path $sfkPath) -ItemType Directory -Force | Out-Null
}

# Download and overwrite sfk.exe if it already exists
try {
    Invoke-WebRequest -Uri $sfkUrl -OutFile $sfkPath -UseBasicParsing
    Write-Host "Downloaded sfk.exe to $sfkPath"
}
catch {
    Write-Error "Failed to download sfk.exe: $_"
    exit 1
}

# Get the current date as a YYYYMMDD format
$dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

# List of directories to scan
$Directories = @(
    @{Path="C:\"; Report="large-files"},
    @{Path="C:\Users"; Report="large-user-files"}
)

# Scan them and generate reports
foreach ($dir in $Directories) {
    $OutputTempReport = "C:\temp\$($dir.Report)_$dateStamp.txt"
    $OutputCsv = "C:\temp\$($dir.Report)_$dateStamp.csv"
    Get-LargeFiles -Directory $dir.Path -OutputFile $OutputTempReport
    Convert-SfkReportToCsv -InputPath $OutputTempReport -OutputCsv $OutputCsv
    if ($null -ne $env:SyncroModule) { # running in Syncro, upload the file
        Upload-File -FilePath $OutputCsv | Out-Null
        Write-Host "Uploaded file $OutputCsv to Syncro asset"
    }
    else {
        Write-Host "Not running in Syncro. Report available at $OutputCsv"
    }
}


<#
# Commented out from original Syncro script, but leaving for possible future use.

Note: The following two lines will list the 50 biggest files in the C:\ directory (slow)
Adapt these lines to enable this more intensive listing mode.
$OutputFilePath = "C:\temp\50-biggest-files.txt"
& $sfkPath list -big -mbytes C:\ | Sort-Object -Descending > $OutputFilePath
Get-Content $OutputFilePath
#>