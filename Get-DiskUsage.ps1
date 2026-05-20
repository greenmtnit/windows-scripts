<#
    Get-DiskUsage.ps1
    
    Uses the native Windows diskusage command to get a list of the largest files and directories on the system.
    Converts this data into human-readable CSV files and a summary TXT file.
    If running in Syncro, the TXT file is uploaded to the Syncro asset page.
    By default, reports are saved in C:\!TECH\Disk Usage Reports
    
    SYNCRO SCRIPT VARIABLES
        $ScanPath
            Name: ScanPath
            Type: Runtime
            Description: Directory path to scan for disk usage. If not path is provided, script will use C:\.
                         You can set this to scan a certain directory, or another drive such as D:\ or E:\.
        
    
#>

if ($null -ne $env:SyncroModule) { 
    Import-Module $env:SyncroModule -DisableNameChecking
}

# ════════════════════════════════════════════════════════════════════════════════
# VARIABLES
# ════════════════════════════════════════════════════════════════════════════════
# Output directory (all four report files land here, named automatically)
$OutputReportsDir = "C:\!TECH\Disk Usage Reports"

# Decimal places for GB values
$DecimalPlaces = 2

# Drive or path to scan. Should be read from Syncro. If not, use C:\ as default
if (-not $ScanPath) {
    Write-Host "No Scan Root path provided. Using default path: C:\"
    $ScanPath = "C:\"
}

# ════════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════════
function Convert-DirsCSV {
    # Convert the largest folders CSV from diskusage into a more readable CSV and text file
    param(
        [string]$InFile,
        [string]$OutCSV,
        [string]$OutTXT,
        [int]$Decimals,
        [switch]$Append
    )

    if (-not (Test-Path $InFile)) {
        Write-Warning "Directories CSV not found: $InFile  -- skipping."
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

    # ── CSV ──────────────────────────────────────────────────────────────────
    $converted | Export-Csv -Path $OutCSV -NoTypeInformation -Encoding UTF8

    # ── Text report ──────────────────────────────────────────────────────────
    $wSize = 14 ; $wFiles = 9 ; $wPerDir = 13 ; $wDir = 60
    $maxDirLen = ($converted | ForEach-Object { $_.Directory.Length } | Measure-Object -Maximum).Maximum
    if ($maxDirLen -gt $wDir) { $wDir = $maxDirLen }

    $fmt = "{0,-" + $wSize + "}  {1,-" + $wFiles + "}  {2,-" + $wPerDir + "}  {3}"
    $sep = "-" * ($wSize + $wFiles + $wPerDir + $wDir + 9)
    $hdr = $fmt -f "SizeOnDisk(GB)", "Files", "SizePerDir(GB)", "Directory"

    $totalSizeGB = [math]::Round(($converted | Measure-Object -Property SizeOnDisk_GB -Sum).Sum, $Decimals)
    $totalFiles  = ($converted | Measure-Object -Property Files -Sum).Sum

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LARGEST FOLDERS")
    $lines.Add($sep)
    $lines.Add($hdr)
    $lines.Add($sep)
    foreach ($r in $converted) {
        $lines.Add(($fmt -f $r.SizeOnDisk_GB, $r.Files, $r.SizePerDir_GB, $r.Directory))
    }
    $lines.Add($sep)

    if ($Append) {
        $lines | Add-Content -Path $OutTXT -Encoding UTF8
    } 
    else {
        $lines | Set-Content -Path $OutTXT -Encoding UTF8
    }
    $lines | Write-Host
}

# ─────────────────────────────────────────────────────────────────────────────

function Convert-FilesCSV {
    # Convert the largest files CSV from diskusage into a more readable CSV and text file
    param(
        [string]$InFile,
        [string]$OutCSV,
        [string]$OutTXT,
        [int]$Decimals,
        [switch]$Append
    )

    if (-not (Test-Path $InFile)) {
        Write-Warning "Files CSV not found: $InFile  -- skipping."
        return
    }

    $rows = Import-Csv -Path $InFile

    $converted = foreach ($row in $rows) {
        [PSCustomObject]@{
            "SizeOnDisk_GB" = [math]::Round([double]$row.SizeOnDisk / 1GB, $Decimals)
            "File path"     = $row."File path"
        }
    }

    # ── CSV ──────────────────────────────────────────────────────────────────
    $converted | Export-Csv -Path $OutCSV -NoTypeInformation -Encoding UTF8

    # ── Text report ──────────────────────────────────────────────────────────
    $wSize = 14 ; $wPath = 60
    $maxPathLen = ($converted | ForEach-Object { $_."File path".Length } | Measure-Object -Maximum).Maximum
    if ($maxPathLen -gt $wPath) { $wPath = $maxPathLen }

    $fmt = "{0,-" + $wSize + "}  {1}"
    $sep = "-" * ($wSize + $wPath + 4)
    $hdr = $fmt -f "SizeOnDisk(GB)", "File path"

    $totalSizeGB = [math]::Round(($converted | Measure-Object -Property SizeOnDisk_GB -Sum).Sum, $Decimals)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LARGEST FILES")
    $lines.Add($sep)
    $lines.Add($hdr)
    $lines.Add($sep)
    foreach ($r in $converted) {
        $lines.Add(($fmt -f $r.SizeOnDisk_GB, $r."File path"))
    }
    $lines.Add($sep)

    if ($Append) {
        $lines | Add-Content -Path $OutTXT -Encoding UTF8
    } 
    else {
        $lines | Set-Content -Path $OutTXT -Encoding UTF8
    }
   $lines | Write-Host
}

# ════════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════════

# Check that diskusage command is available - only since later versions of Windows 10, and Server 2022
if (-not (Get-Item "C:\Windows\System32\diskusage.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "The diskusage command is not available on this system.`ndiskusage is only available starting in later builds of Windows 10, and Server 2022 and up.`nYou will need to analyze disk space manually using WinDirStat or similar.`nScript will not run."
    exit 1
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ── Run diskusage and save source CSVs to %TEMP% ─────────────────────────────
$InputDirs  = Join-Path $env:TEMP "DiskUsageDirs_${timestamp}.csv"
$InputFiles = Join-Path $env:TEMP "DiskUsageFiles_${timestamp}.csv"

Write-Host ""
Write-Host "=== Collecting disk usage data for path $ScanPath ==="

Write-Host "Running diskusage /TopDirectory:50 ..."
diskusage /csv $ScanPath /TopDirectory:50 | Out-File -FilePath $InputDirs  -Encoding UTF8
Write-Host "  Saved: $InputDirs"

Write-Host "Running diskusage /TopFile:50 ..."
diskusage /csv $ScanPath /TopFile:50     | Out-File -FilePath $InputFiles -Encoding UTF8
Write-Host "  Saved: $InputFiles"

# ── Create output reports directory if needed ─────────────────────────────────
if (-not (Test-Path $OutputReportsDir)) { New-Item -ItemType Directory -Path $OutputReportsDir | Out-Null }

# ── Generate output file names ──────────────────────────────────────────
$OutputDirsCSV  = Join-Path $OutputReportsDir "DiskUsageDirs_${timestamp}.csv"
$OutputFilesCSV = Join-Path $OutputReportsDir "DiskUsageFiles_${timestamp}.csv"
$OutputTxtFile  = Join-Path $OutputReportsDir "DiskUsageSummary_${timestamp}.txt"

# Initialize text file
Add-Content -Path $OutputTxtFile "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# ── Use functions to process the reports

Write-Host ""
Write-Host "=== Processing: Largest Directories ==="
Convert-DirsCSV  -InFile $InputDirs  -OutCSV $OutputDirsCSV  -OutTXT $OutputTxtFile  -Append -Decimals $DecimalPlaces

Add-Content -Path $OutputTxtFile ""

Write-Host ""
Write-Host "=== Processing: Largest Files ==="
Convert-FilesCSV -InFile $InputFiles -OutCSV $OutputFilesCSV -OutTXT $OutputTxtFile -Append -Decimals $DecimalPlaces

# Upload report to Syncro asset, if running in Syncro
if ($null -ne $env:SyncroModule) { 
    Upload-File -FilePath $OutputTxtFile
    Write-Host ""
    Write-Host "Uploaded summary text file to Syncro asset page."
}

Write-Host ""
Write-Host "Saved reports to $OutputReportsDir."
Write-Host "Done."