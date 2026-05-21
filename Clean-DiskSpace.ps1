<#
.SYNOPSIS
    Disk cleanup script — removes old temp files, specific folders, and aged Recycle Bin items.

.DESCRIPTION
    - Logs all actions to C:\!TECH\DiskCleanupLogs\DiskCleanup_<hostname>_<timestamp>.txt
    - Reports free space on C:\ before and after (% and GB)
    - Deletes items older than 30 days from Windows Temp and all user Temp folders C:\Users\*\AppData\Local\Temp
    - Removes C:\!TECH\Windows11Setup and C:\!TECH\Packages if present (leftover paths from GMITS Windows upgrade scripts
    - Purges Recycle Bin entries deleted more than 30 days ago (matches $I / $R pairs)
    - Warns if free space remains at or below 20 %
#>

# ---------------------------------------------------------------------------
#  FUNCTIONS
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $entry
    Write-Host $entry
}

function Get-FreeSpace {
    $drive = Get-PSDrive -Name C
    $freeGB   = [math]::Round($drive.Free / 1GB, 2)
    $totalGB  = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $freePct  = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
    return [PSCustomObject]@{ FreeGB = $freeGB; TotalGB = $totalGB; FreePct = $freePct }
}

function Remove-OldItems {
    param(
        [string]$FolderPath,
        [int]$DaysOld = 30
    )

    if (-not (Test-Path $FolderPath)) {
        Write-Log "Skipping (not found): $FolderPath" -Level WARN
        return
    }

    $cutoff  = (Get-Date).AddDays(-$DaysOld)
    $deleted = 0
    $errors  = 0

    Get-ChildItem -Path $FolderPath -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Sort-Object FullName -Descending |   # deepest paths first
        ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
                $deleted++
            } catch {
                Write-Log "Could not delete: $($_.FullName) — $($_.Exception.Message)" -Level WARN
                $errors++
            }
        }

    Write-Log "  $FolderPath — deleted $deleted item(s); $errors error(s)."
}

function Remove-EntireFolder {
    param([string]$FolderPath)

    if (-not (Test-Path $FolderPath)) {
        Write-Log "Skipping (not found): $FolderPath" -Level WARN
        return
    }

    try {
        Remove-Item -Path $FolderPath -Recurse -Force -ErrorAction Stop
        Write-Log "Removed folder: $FolderPath"
    } catch {
        Write-Log "Failed to remove folder: $FolderPath — $($_.Exception.Message)" -Level ERROR
    }
}

function Invoke-SyncroRmmAlert {
    param(
        [string]$Category,
        [string]$Body
    )
    if ($script:InSyncro) {
        Write-Log "Running Syncro command: Rmm-Alert -Category '$Category' -Body '$Body'"
        Rmm-Alert -Category $Category -Body $Body
    } else {
        Write-Log "Not running in Syncro. Would have run: Rmm-Alert -Category '$Category' -Body '$Body'"
    }
}

function Invoke-SyncroLogActivity {
    param(
        [string]$Message,
        [string]$EventName
    )
    if ($script:InSyncro) {
        Write-Log "Running Syncro command: Log-Activity -Message '$Message' -EventName '$EventName'"
        Log-Activity -Message $Message -EventName $EventName
    } else {
        Write-Log "Not running in Syncro. Would have run: Log-Activity -Message '$Message' -EventName '$EventName'"
    }
}


# ---------------------------------------------------------------------------
#  VARIABLES 
# ---------------------------------------------------------------------------
$RMMAlertCategory = "Low Hd Space Trigger"
$ActivityLogEventName = "Disk Cleanup Script"

# ---------------------------------------------------------------------------
#  MAIN SCRIPT ACTION 
# ---------------------------------------------------------------------------

# Import Syncro Module
$script:InSyncro = ($null -ne $env:SyncroModule)
if ($script:InSyncro) { Import-Module $env:SyncroModule -DisableNameChecking }

# Initialize log file 
$Hostname    = $env:COMPUTERNAME
$Stamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir      = "C:\!TECH\DiskCleanupLogs"
$script:LogFile = Join-Path $LogDir "DiskCleanup_${Hostname}_${Stamp}.txt"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Log "========================================================"
Write-Log "Disk Cleanup started on: $Hostname"
Write-Log "Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "========================================================"

# --- Initial free space ---
$before = Get-FreeSpace
Write-Log "Free space BEFORE cleanup: $($before.FreeGB) GB free of $($before.TotalGB) GB  ($($before.FreePct)%)"

# Delete C:\Windows\Temp  — items older than 30 days
# ---------------------------------------------------------------------------
Write-Log "--- Cleaning C:\Windows\Temp (>30 days) ---"
Remove-OldItems -FolderPath "C:\Windows\Temp" -DaysOld 30

# Delete all user's Temp folders — items older than 30 days
# ---------------------------------------------------------------------------
Write-Log "--- Cleaning per-user Temp folders (>30 days) ---"

$userProfileRoot = "C:\Users"
if (Test-Path $userProfileRoot) {
    Get-ChildItem -Path $userProfileRoot -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $userTemp = Join-Path $_.FullName "AppData\Local\Temp"
            if (Test-Path $userTemp) {
                Write-Log "  Processing: $userTemp"
                Remove-OldItems -FolderPath $userTemp -DaysOld 30
            } else {
                Write-Log "  No Temp folder for user: $($_.Name)" -Level WARN
            }
        }
} else {
    Write-Log "User profile root not found: $userProfileRoot" -Level WARN
}

# Delete C:\!TECH\Windows11Setup  — remove entire folder
Write-Log "--- Removing C:\!TECH\Windows11Setup (if present) ---"
Remove-EntireFolder -FolderPath "C:\!TECH\Windows11Setup"

# Delete C:\!TECH\Packages  — remove entire folder
Write-Log "--- Removing C:\!TECH\Packages (if present) ---"
Remove-EntireFolder -FolderPath "C:\!TECH\Packages"

# Clear RECYCLE BIN — items deleted more than 30 days ago
#
#  As noted here: https://forums.powershell.org/t/deleting-recycle-bin-items-deleted-over-28-days-ago-for-all-users/7070/14
#    • Each recycled item creates TWO files under C:\$Recycle.Bin\<SID>\:
#        $Ixxxxxx  — metadata file; its LastWriteTime = deletion timestamp
#        $Rxxxxxx  — the actual data; same 6-char suffix as its $I partner
#    • To avoid deleting orphans, find $I files older than the threshold,
#      derive the matching $R name, and remove both together.
# ---------------------------------------------------------------------------
Write-Log "--- Cleaning Recycle Bin (items deleted >30 days ago) ---"

$cutoffDate  = (Get-Date).AddDays(-30)
$recyclePath = 'C:\$Recycle.Bin'
$rbDeleted   = 0
$rbErrors    = 0

if (Test-Path $recyclePath) {
    # Find every $I metadata file whose LastWriteTime (= deletion date) is past the cutoff
    Get-ChildItem -Path $recyclePath -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '$I*' -and $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            $iFile = $_

            # Derive the $R counterpart: replace the leading '$I' with '$R'
            $rName = '$R' + $iFile.Name.Substring(2)
            $rFile = Join-Path $iFile.DirectoryName $rName

            # Remove the $I metadata file
            try {
                Remove-Item -Path $iFile.FullName -Force -Recurse -ErrorAction Stop
                Write-Log "  Deleted (meta) : $($iFile.FullName)"
                $rbDeleted++
            } catch {
                Write-Log "  Could not delete: $($iFile.FullName) — $($_.Exception.Message)" -Level WARN
                $rbErrors++
            }

            # Remove the matching $R data file / folder (may not exist if already gone)
            if (Test-Path $rFile) {
                try {
                    Remove-Item -Path $rFile -Force -Recurse -ErrorAction Stop
                    Write-Log "  Deleted (data) : $rFile"
                    $rbDeleted++
                } catch {
                    Write-Log "  Could not delete: $rFile — $($_.Exception.Message)" -Level WARN
                    $rbErrors++
                }
            } else {
                Write-Log "  No matching data file found for: $($iFile.FullName)" -Level WARN
            }
        }
} else {
    Write-Log "Recycle Bin path not found: $recyclePath" -Level WARN
}

Write-Log "  Recycle Bin — deleted $rbDeleted item(s); $rbErrors error(s)."

# Final Checks
$after = Get-FreeSpace
Write-Log "========================================================"
Write-Log "Free space BEFORE cleanup: $($before.FreeGB) GB free of $($before.TotalGB) GB  ($($before.FreePct)%)"
Write-Log "Free space AFTER  cleanup: $($after.FreeGB) GB free of $($after.TotalGB) GB  ($($after.FreePct)%)"

$freedGB = [math]::Round($after.FreeGB - $before.FreeGB, 2)
Write-Log "Space reclaimed  : $freedGB GB"

$threshold = 20
if ($after.FreePct -gt $threshold) {
    Write-Log "RESULT: Free space ($($after.FreePct)%) IS more than ${threshold}%. Disk health OK."
} else {
    Write-Log "RESULT: Free space ($($after.FreePct)%) IS NOT more than ${threshold}%. Further cleanup may be required." -Level WARN
}

# Log to Syncro
Invoke-SyncroLogActivity -Message "Disk cleanup script ran. Free space BEFORE cleanup: $($before.FreeGB) GB free of $($before.TotalGB) GB  ($($before.FreePct)%). Free space AFTER  cleanup: $($after.FreeGB) GB free of $($after.TotalGB) GB  ($($after.FreePct)%)" -EventName $ActivityLogEventName

Write-Log "Disk Cleanup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Log "========================================================"