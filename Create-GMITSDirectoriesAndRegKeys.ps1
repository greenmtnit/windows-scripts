<#
.SYNOPSIS
Creates necessary directories and registry keys for Green Mountain IT Solutions RMM and automations.

.DESCRIPTION
This script creates a set of predefined directories and registry keys required for 
Green Mountain IT Solutions' RMM and automations. It checks for the existence of each directory 
and registry key before creating them, avoiding duplicate creations.

.NOTES
File Name      : Create-GMITSDirectoriesAndRegKeys.ps1
Author         : Timothy West

#>

# ===========================================
#  Directories
# ===========================================    

# Define directory paths
$techDirectory = "C:\!TECH"
$baseDirectory = "C:\Program Files\Green Mountain IT Solutions"
$scriptsDirectory = Join-Path -Path $baseDirectory -ChildPath "Scripts"
$workingDirectory = Join-Path -Path $baseDirectory -ChildPath "RMM"
$toolsDirectory = Join-Path -Path $workingDirectory -ChildPath "Tools"

# Array of all directories to be created
$directories = @($techDirectory, $baseDirectory, $scriptsDirectory, $workingDirectory, $toolsDirectory)

# Create directories if they don't exist
foreach ($dir in $directories) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $dir"
    }
    else {
        Write-Host "Directory already exists: $dir"
    }
}

# ===========================================
#  Registry Keys
# ===========================================    
# Define registry key paths
$baseKey = "HKLM:\SOFTWARE\Green Mountain IT Solutions"
$scriptsKey = "$baseKey\Scripts"
$rmmKey = "$baseKey\RMM"

# Array of all registry keys to be created
$keys = @($baseKey, $scriptsKey, $rmmKey)

# Create registry keys if they don't exist
foreach ($key in $keys) {
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
        Write-Host "Created registry key: $key"
    } else {
        Write-Host "Registry key already exists: $key"
    }
}
