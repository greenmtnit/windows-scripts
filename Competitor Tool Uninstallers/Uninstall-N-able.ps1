<#
  Uninstall-N-able.ps1
    
  Uninstalls N-able RMM. Note: will not work if Windows Agent Uninstall Protection is enabled.
 https://documentation.n-able.com/remote-management/userguide/Content/windows_agent_uninstall_protection.htm
  
  Original source: https://documentation.n-able.com/remote-management/userguide/Content/uninstall_the_agent.htm
  
#>

$primaryPath = "C:\Program Files (x86)\Advanced Monitoring Agent\winagent.exe"
$fallbackPath = "C:\Program Files (x86)\Advanced Monitoring Agent GP\winagent.exe"

if (Test-Path $primaryPath) {
    Write-Host "Found primary installation at: $primaryPath"
    $nablePath = $primaryPath
} 
elseif (Test-Path $fallbackPath) {
    Write-Host "Primary path not found. Using fallback: $fallbackPath"
    $nablePath = $primaryPath
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
