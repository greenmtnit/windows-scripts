<#
  Uninstall-N-able.ps1
    
  Uninstalls N-able RMM. Note: 
  If Windows Agent Uninstall Protection is enabled, which requires a passphrase to uninstall, this can be bypassed by removing the settings.ini file in the install path, e.g. "C:\Program Files (x86)\Advanced Monitoring Agent\settings.ini"
  Original source: https://documentation.n-able.com/remote-management/userguide/Content/uninstall_the_agent.htm
  
#>

# Delete settings.ini to bypass Windows Agent Uninstall Protection
Write-Host "Deleting settings.ini files"

$settingsFiles = @(
    "C:\Program Files (x86)\Advanced Monitoring Agent\settings.ini",
    "C:\Program Files (x86)\Advanced Monitoring Agent GP\settings.ini"
)

$timestamp = Get-Date -Format "yyyyMMddhhmm"

foreach ($settingsFile in $settingsFiles) {
    if (Test-Path $settingsFile) {
        $newName = "$settingsFile.bak$timestamp"
        Write-Host "Renaming $settingsFile to $newName"
        Rename-Item -Path $settingsFile -NewName (Split-Path $newName -Leaf)
    } else {
        Write-Host "File not found: $settingsFile"
    }
}

# Locate and run uninstall

$primaryPath = "C:\Program Files (x86)\Advanced Monitoring Agent\winagent.exe"
$fallbackPath = "C:\Program Files (x86)\Advanced Monitoring Agent GP\winagent.exe"

if (Test-Path $primaryPath) {
    Write-Host "Found primary installation at: $primaryPath"
    $nablePath = $primaryPath
} 
elseif (Test-Path $fallbackPath) {
    Write-Host "Primary path not found. Using fallback: $fallbackPath"
    $nablePath = $fallbackPath
}
else {
    Write-Host "Neither installation path found. Agent may not be installed."
    Write-Host "Checked paths:"
    Write-Host "  - $primaryPath"
    Write-Host "  - $fallbackPath"
    exit 1
}

Write-Host "Starting uninstall."
cmd /c """$nablePath"" /removequiet"

Write-Host "Uninstall process finished."
