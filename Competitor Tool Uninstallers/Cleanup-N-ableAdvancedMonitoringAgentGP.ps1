<#
  Cleanup-N-ableAdvancedMonitoringAgentGP.ps1
    
  Cleans up N-able Advanced Monitoring Agent GP remnants.

  This script is only for *cleanup* of Advanced Monitoring Agent GP remnants, not full uninstall. First, uninstall manually from appwiz.cpl, by using the Uninstall-N-able.ps1 script, and/or using Group Policy.
    
#>

# Check if N-Able agent is actually installed. If so, exit. This script is for cleanup only.
$nablePaths = @(
    "C:\Program Files (x86)\Advanced Monitoring Agent\winagent.exe",
    "C:\Program Files (x86)\Advanced Monitoring Agent GP\winagent.exe",
    "C:\Program Files\Advanced Monitoring Agent\winagent.exe",
    "C:\Program Files\Advanced Monitoring Agent GP\winagent.exe"
)

Write-Output "Checking N-able winagent.exe locations..."
$found = $false

foreach ($nablePath in $nablePaths) {
    if (Test-Path $nablePath) {
        Write-Output "FOUND: $nablePath" -ForegroundColor Red
        $found = $true
    } else {
        Write-Output "Not found: $nablePath"
    }
}

if (-not $found) {
    Write-Output "No N-able winagent.exe found in any checked location. N-able does not appear to be installed. Proceeding with cleanup."
} else {
    Write-Output "N-able agent files still present. This script is only for *cleanup* of Advanced Monitoring Agent GP remnants, not full uninstall. First, uninstall manually from appwiz.cpl, by using the Uninstall-N-able.ps1 script, and/or using Group Policy."
    exit 1
}


# Directories to remove (recursively and forcibly)
$DirsToRemove = @(
    "C:\Program Files\Advanced Monitoring Agent GP",
    "C:\Program Files\Advanced Monitoring Agent Network Management",
    "C:\Program Files (x86)\Advanced Monitoring Agent GP",
    "C:\Program Files (x86)\Advanced Monitoring Agent Network Management"
)

foreach ($dir in $DirsToRemove) {
    try {
        if (Test-Path $dir) {
            Write-Host "Removing directory: $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop

        } else {
            Write-Host "Directory not found (skip): $dir"
        }
    } catch {
        Write-Warning "Failed to remove $dir. $_"
    }
}

# ===============================
# Registry Uninstall Key Removal
# ===============================
$TargetDisplayName = "Advanced Monitoring Agent GP"
$UninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($root in $UninstallRoots) {
    Write-Host "Scanning uninstall root: $root"
    try {
        $subkeys = Get-ChildItem -Path $root -ErrorAction Stop
    } catch {
        Write-Warning "Unable to enumerate $root. $_"
        continue
    }
    
    if ([string]::IsNullOrWhiteSpace($subkeys)) {
        Write-Host "No registry keys found."
    }
    
    else {
        foreach ($sub in $subkeys) {
            try {
                $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction Stop
                $displayName = $props.DisplayName
            } catch {
                # Some keys have no readable properties; skip
                continue
            }

            if ($null -ne $displayName -and $displayName -eq $TargetDisplayName) {
                Write-Host "Deleting uninstall key with DisplayName '$TargetDisplayName': $($sub.Name)"
                try {
                    # Use Registry:: provider path to avoid PSDrive quirks
                    $regLiteral = $sub.PSPath
                    Remove-Item -LiteralPath $regLiteral -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-Warning "Failed to delete uninstall subkey: $($sub.Name). $_"
                }
            }
        }
    }
}
