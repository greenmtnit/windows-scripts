<#
.SYNOPSIS
    Disk cleanup script — removes old temp files, specific folders, and aged Recycle Bin items.
    If free space remains at or below 20% after cleanup, runs a disk usage report.

.DESCRIPTION
    - Logs all actions to C:\!TECH\DiskCleanupLogs\DiskCleanup_<hostname>_<timestamp>.txt
    - Reports free space on C:\ before and after (% and GB)
    - Deletes items older than 30 days from Windows Temp and all user Temp folders C:\Users\*\AppData\Local\Temp
    - Removes C:\!TECH\Windows11Setup and C:\!TECH\Packages if present (leftover paths from GMITS Windows upgrade scripts)
    - Purges Recycle Bin entries deleted more than 30 days ago (matches $I / $R pairs)
    - If free space remains at or below 20%, runs diskusage to produce a disk usage report,
      fires an Rmm-Alert in Syncro, and uploads the summary TXT to the Syncro asset page.

    SYNCRO SCRIPT VARIABLES
        $ScanPath
            Name: ScanPath
            Type: Runtime
            Description: Directory path to scan for disk usage (only used if cleanup leaves space <=20%).
                         Defaults to C:\ if not provided.
       TODO - add TicketNumber from automation
#>

# ============================================================================
#  FUNCTIONS
# ============================================================================

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
    $drive   = Get-PSDrive -Name C
    $freeGB  = [math]::Round($drive.Free / 1GB, 2)
    $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $freePct = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
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

function Invoke-SyncroCloseRmmAlert {
    param(
        [string]$Category,

        [ValidateSet("true", "false")]
        [string]$CloseAlertTicket
    )

    if ($script:InSyncro) {
        Write-Log "Running Syncro command: Close-Rmm-Alert -Category '$Category' -CloseAlertTicket '$CloseAlertTicket'"
        Close-Rmm-Alert -Category $Category -CloseAlertTicket $CloseAlertTicket
    }
    else {
        Write-Log "Not running in Syncro. Would have run: Close-Rmm-Alert -Category '$Category' -CloseAlertTicket '$CloseAlertTicket'"
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

function Invoke-SyncroCreateSyncroTicketComment {
    param(
        [string]$TicketIdOrNumber,
        [string]$Subject,
        [string]$Body,
        
        [ValidateSet("true", "false")]
        [string]$Hidden,

        [ValidateSet("true", "false")]
        [string]$DoNotEmail
    )

    if ($script:InSyncro) {
        Write-Log "Running Syncro command: Create-Syncro-Ticket-Comment -TicketIdOrNumber '$TicketIdOrNumber' -Subject '$Subject' -Body '$Body' -Hidden '$Hidden' -DoNotEmail '$DoNotEmail'"
        Create-Syncro-Ticket-Comment -TicketIdOrNumber $TicketIdOrNumber -Subject $Subject -Body $Body -Hidden $Hidden -DoNotEmail $DoNotEmail
    }
    else {
        Write-Log "Not running in Syncro. Would have run: Create-Syncro-Ticket-Comment -TicketIdOrNumber '$TicketIdOrNumber' -Subject '$Subject' -Body '$Body' -Hidden '$Hidden' -DoNotEmail '$DoNotEmail'"
    }
}

# ── Disk Usage report functions ──────────────────────────────────────────────

function Convert-DirsCSV {
    param(
        [string]$InFile,
        [string]$OutCSV,
        [string]$OutTXT,
        [int]$Decimals,
        [switch]$Append
    )
    if (-not (Test-Path $InFile)) {
        Write-Log "Directories CSV not found: $InFile — skipping." -Level WARN
        return
    }
    $rows = Import-Csv -Path $InFile
    $converted = foreach ($row in $rows) {
        [PSCustomObject]@{
            "SizeOnDisk_GB" = [math]::Round([double]$row.SizeOnDisk / 1GB, $Decimals)
            "Files"         = [int]$row.Files
            "SizePerDir_GB" = [math]::Round([double]$row.SizePerDir / 1GB, $Decimals)
            "Directory"     = $row."Directory path"
        }
    }
    $converted | Export-Csv -Path $OutCSV -NoTypeInformation -Encoding UTF8

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LARGEST FOLDERS")
    $lines.Add("")
    foreach ($r in $converted) {
        $lines.Add("$($r.SizeOnDisk_GB) GB  —  $($r.Directory)")
    }
    $lines.Add("")
    
    if ($Append) { $lines | Add-Content -Path $OutTXT -Encoding UTF8 }
    else         { $lines | Set-Content -Path $OutTXT -Encoding UTF8 }
    $lines | ForEach-Object { Write-Log $_ }
}

function Convert-FilesCSV {
    param(
        [string]$InFile,
        [string]$OutCSV,
        [string]$OutTXT,
        [int]$Decimals,
        [switch]$Append
    )
    if (-not (Test-Path $InFile)) {
        Write-Log "Files CSV not found: $InFile — skipping." -Level WARN
        return
    }
    $rows = Import-Csv -Path $InFile
    $converted = foreach ($row in $rows) {
        [PSCustomObject]@{
            "SizeOnDisk_GB" = [math]::Round([double]$row.SizeOnDisk / 1GB, $Decimals)
            "File path"     = $row."File path"
        }
    }
    $converted | Export-Csv -Path $OutCSV -NoTypeInformation -Encoding UTF8

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LARGEST FILES")
    $lines.Add("")
    foreach ($r in $converted) {
        $lines.Add("$($r.SizeOnDisk_GB) GB  —  $($r.'File path')")
    }
    $lines.Add("")
    
    if ($Append) { $lines | Add-Content -Path $OutTXT -Encoding UTF8 }
    else         { $lines | Set-Content -Path $OutTXT -Encoding UTF8 }
    $lines | ForEach-Object { Write-Log $_ }
}

function Invoke-DiskUsageReport {
    # Runs diskusage and produces CSV + TXT reports in $OutputReportsDir.
    # If running in Syncro, uploads the TXT summary to the asset page.
    param(
        [string]$ScanPath,
        [string]$OutputReportsDir,
        [int]$DecimalPlaces = 2
    )

    Write-Log "========================================================"
    Write-Log "Starting disk usage report (space still <= 20% after cleanup)."
    Write-Log "Scan path : $ScanPath"
    Write-Log "Output dir: $OutputReportsDir"

    # Check diskusage availability
    if (-not (Get-Item "C:\Windows\System32\diskusage.exe" -ErrorAction SilentlyContinue)) {
        Write-Log "diskusage.exe not found. Only available on later Windows 10 builds and Server 2022+. Skipping disk usage report." -Level WARN
        return
    }

    if (-not (Test-Path $OutputReportsDir)) {
        New-Item -ItemType Directory -Path $OutputReportsDir -Force | Out-Null
    }

    $timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
    $InputDirs      = Join-Path $env:TEMP "DiskUsageDirs_${timestamp}.csv"
    $InputFiles     = Join-Path $env:TEMP "DiskUsageFiles_${timestamp}.csv"
    $OutputDirsCSV  = Join-Path $OutputReportsDir "DiskUsageDirs_${script:Hostname}_${timestamp}.csv"
    $OutputFilesCSV = Join-Path $OutputReportsDir "DiskUsageFiles_${script:Hostname}_${timestamp}.csv"
    $OutputTxtFile  = Join-Path $OutputReportsDir "DiskUsageSummary_${script:Hostname}_${timestamp}.txt"

    # Seed the TXT file header
    Add-Content -Path $OutputTxtFile "Disk Usage Report for $script:Hostname" -Encoding UTF8
    Add-Content -Path $OutputTxtFile "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
    Add-Content -Path $OutputTxtFile "" -Encoding UTF8

    Write-Log "Running diskusage /TopDirectory:50 ..."
    diskusage /csv $ScanPath /TopDirectory:50 | Out-File -FilePath $InputDirs -Encoding UTF8

    Write-Log "Running diskusage /TopFile:50 ..."
    diskusage /csv $ScanPath /TopFile:50 | Out-File -FilePath $InputFiles -Encoding UTF8

    Write-Log "--- Processing: Largest Directories ---"
    Convert-DirsCSV  -InFile $InputDirs  -OutCSV $OutputDirsCSV  -OutTXT $OutputTxtFile -Append -Decimals $DecimalPlaces

    Add-Content -Path $OutputTxtFile "" -Encoding UTF8

    Write-Log "--- Processing: Largest Files ---"
    Convert-FilesCSV -InFile $InputFiles -OutCSV $OutputFilesCSV -OutTXT $OutputTxtFile -Append -Decimals $DecimalPlaces

    Write-Log "Disk usage reports saved to: $OutputReportsDir"

    # Upload to Syncro asset if running in Syncro
    if ($script:InSyncro) {
        Upload-File -FilePath $OutputTxtFile
        Write-Log "Uploaded disk usage summary to Syncro asset page."
    }

    Write-Log "========================================================"
    
    return $OutputTxtFile
}

# ============================================================================
#  VARIABLES
# ============================================================================

$RMMAlertCategory     = "low_hd_space_trigger"
$ActivityLogEventName = "Disk Cleanup Script"
$DiskUsageReportsDir  = "C:\!TECH\Disk Usage Reports"
$DecimalPlaces        = 2
$FreeSpaceThreshold   = 20

# ScanPath may be injected as a Syncro runtime variable; default to C:\ if absent
if (-not $ScanPath) { $ScanPath = "C:\" }

# ============================================================================
#  MAIN
# ============================================================================

# ── Syncro ───────────────────────────────────────────────────────────────────
$script:InSyncro = ($null -ne $env:SyncroModule)
if ($script:InSyncro) { Import-Module $env:SyncroModule -DisableNameChecking }

# ── Log file setup ────────────────────────────────────────────────────────────
$script:Hostname = $env:COMPUTERNAME
$Stamp           = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir          = "C:\!TECH\DiskCleanupLogs"
$script:LogFile  = Join-Path $LogDir "DiskCleanup_${script:Hostname}_${Stamp}.txt"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Log "========================================================"
Write-Log "Disk Cleanup started on: $script:Hostname"
Write-Log "Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "========================================================"

# ── Free space before ────────────────────────────────────────────────────────
$before = Get-FreeSpace
Write-Log "Free space BEFORE cleanup: $($before.FreeGB) GB free of $($before.TotalGB) GB  ($($before.FreePct)%)"

# ── C:\Windows\Temp — items older than 30 days ───────────────────────────────
Write-Log "--- Cleaning C:\Windows\Temp (>30 days) ---"
Remove-OldItems -FolderPath "C:\Windows\Temp" -DaysOld 30

# ── Per-user Temp folders — items older than 30 days ─────────────────────────
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

# ── C:\!TECH\Windows11Setup — remove entire folder ───────────────────────────
Write-Log "--- Removing C:\!TECH\Windows11Setup (if present) ---"
Remove-EntireFolder -FolderPath "C:\!TECH\Windows11Setup"

# ── C:\!TECH\Packages — remove entire folder ─────────────────────────────────
Write-Log "--- Removing C:\!TECH\Packages (if present) ---"
Remove-EntireFolder -FolderPath "C:\!TECH\Packages"

# ── Recycle Bin — pairs deleted more than 30 days ago ────────────────────────
#  Ref: https://forums.powershell.org/t/deleting-recycle-bin-items-deleted-over-28-days-ago-for-all-users/7070/14
#  Each recycled item creates two files under C:\$Recycle.Bin\<SID>\:
#    $Ixxxxxx — metadata; LastWriteTime = deletion timestamp
#    $Rxxxxxx — actual data; same 6-char suffix as its $I partner
#  Find $I files past the cutoff, derive the $R name, remove both.
Write-Log "--- Cleaning Recycle Bin (items deleted >30 days ago) ---"
$cutoffDate  = (Get-Date).AddDays(-30)
$recyclePath = 'C:\$Recycle.Bin'
$rbDeleted   = 0
$rbErrors    = 0

if (Test-Path $recyclePath) {
    Get-ChildItem -Path $recyclePath -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '$I*' -and $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            $iFile = $_
            $rName = '$R' + $iFile.Name.Substring(2)
            $rFile = Join-Path $iFile.DirectoryName $rName

            try {
                Remove-Item -Path $iFile.FullName -Force -Recurse -ErrorAction Stop
                Write-Log "  Deleted (meta) : $($iFile.FullName)"
                $rbDeleted++
            } catch {
                Write-Log "  Could not delete: $($iFile.FullName) — $($_.Exception.Message)" -Level WARN
                $rbErrors++
            }

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

# ── Final free space + threshold check ───────────────────────────────────────
$after   = Get-FreeSpace
$freedGB = [math]::Round($after.FreeGB - $before.FreeGB, 2)

Write-Log "========================================================"
Write-Log "Free space BEFORE cleanup: $($before.FreeGB) GB free of $($before.TotalGB) GB  ($($before.FreePct)%)"
Write-Log "Free space AFTER  cleanup: $($after.FreeGB) GB free of $($after.TotalGB) GB  ($($after.FreePct)%)"
Write-Log "Space reclaimed          : $freedGB GB"

if ($after.FreePct -gt $FreeSpaceThreshold) {

    Write-Log "RESULT: Free space ($($after.FreePct)%) IS more than ${FreeSpaceThreshold}%. Disk health OK."
    Invoke-SyncroLogActivity -Message "Disk cleanup script ran." -EventName $ActivityLogEventName
    
    $TicketComment = "Disk cleanup script SUCCESSFULLY freed sufficient space.`n`nFree space BEFORE: $($before.FreeGB) GB / $($before.TotalGB) GB ($($before.FreePct)%).`nAFTER: $($after.FreeGB) GB / $($after.TotalGB) GB ($($after.FreePct)%).`nSpace reclaimed: $freedGB GB.`n`nTicket will close"
    Invoke-SyncroCreateSyncroTicketComment -TicketIdOrNumber $ticketNumber -Subject "Completed" -Body $TicketComment -Hidden "false" -DoNotEmail "true"    

    Invoke-SyncroCloseRmmAlert -Category $RMMAlertCategory -CloseAlertTicket "true"

} else {

    Write-Log "RESULT: Free space ($($after.FreePct)%) IS NOT more than ${FreeSpaceThreshold}%. Further cleanup may be required." -Level WARN
    Invoke-SyncroLogActivity -Message "Disk cleanup script ran." -EventName $ActivityLogEventName

    Write-Log "--- Running disk usage report because free space is still less than ${FreeSpaceThreshold}% ---"
    $diskUsageTxtPath = Invoke-DiskUsageReport -ScanPath $ScanPath -OutputReportsDir $DiskUsageReportsDir -DecimalPlaces $DecimalPlaces # Function will return the output text file's path.
    $diskUsageContent = Get-Content -Path $diskUsageTxtPath -Raw
        
    Invoke-SyncroCreateSyncroTicketComment -TicketIdOrNumber $ticketNumber -Subject "Diagnosis" -Body $diskUsageContent -Hidden "false" -DoNotEmail "true"
    
    $TicketComment = "Disk cleanup script ran but was UNSUCCESSFUL in freeing sufficient space.`n`nFree space BEFORE: $($before.FreeGB) GB / $($before.TotalGB) GB ($($before.FreePct)%).`nAFTER: $($after.FreeGB) GB / $($after.TotalGB) GB ($($after.FreePct)%).`nSpace reclaimed: $freedGB GB.`nWARNING: Free space is still at or below ${FreeSpaceThreshold}%.`n`nNEXT STEPS:`nManual analysis is needed. Reference the disk usage results below. Follow this process: https://app.process.st/pages/Handling-Low-Disk-Space-Alerts-oIyZY2F-dckYmYITTxhK_Q/view`n`n"

    Invoke-SyncroCreateSyncroTicketComment -TicketIdOrNumber $ticketNumber -Subject "Diagnosis" -Body $TicketComment -Hidden "true" -DoNotEmail "true"

}

Write-Log "Disk Cleanup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "========================================================"