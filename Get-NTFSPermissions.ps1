<#
    Get-NTFSPermissions.ps1
    
.SYNOPSIS
    Exports NTFS folder permissions on a given path to a CSV file.
    
.DESCRIPTION
    Recursively scans a root directory and outputs NTFS ACL entries for every
    subfolder to a timestamped CSV file in C:\!TECH. Specific users/groups and
    folder paths can be excluded from the report. By default, NT AUTHORITY\SYSTEM
    and BUILTIN\Administrators are always excluded unless -SkipDefaultExclusions
    is specified.

    Non-inherited (explicit) permissions are flagged in the CSV output and
    highlighted in the console summary.
    
.PARAMETER RootPath
    The root directory to scan recursively for NTFS permissions.
    
.PARAMETER ExcludedUsersAndGroups
    An array of user or group identities (in DOMAIN\Name format) to omit from
    the report. These are appended to the default exclusions unless
    -SkipDefaultExclusions is specified.
    
.PARAMETER ExcludedPaths
    An array of full folder paths to skip entirely during the recursive scan.
    Subfolders of an excluded path are still scanned unless also listed here.
    
.PARAMETER SkipDefaultExclusions
    When specified, the built-in default exclusions (NT AUTHORITY\SYSTEM and
    BUILTIN\Administrators) are not applied. Only identities passed via
    -ExcludedUsersAndGroups will be excluded.
    
.PARAMETER MaxDepth
    Limits how many folder levels deep the scan will recurse beneath RootPath.
    Depth 0 scans only RootPath itself; depth 1 includes immediate subfolders, etc.
    Omit this parameter (or set to -1) for unlimited depth (original behaviour).
    
.OUTPUTS
    CSV file at C:\!TECH\NTFSPermissions_<hostname>_<timestamp>.csv
    Columns: FolderPath, IdentityReference, AccessControlType, IsInherited,
             IsExplicit, FileSystemRights, InheritanceFlags, PropagationFlags
             
.EXAMPLE
    .\Get-NTFSPermissions.ps1 -RootPath "D:\"
    Scans D:\ recursively. NT AUTHORITY\SYSTEM and BUILTIN\Administrators are
    excluded. All other identities appear in the report.
    
.EXAMPLE
    .\Get-NTFSPermissions.ps1 -RootPath "C:\" -ExcludedUsersAndGroups "EVALCO\EVALCO-Admin-Servers","EVALCO\EVALCO-Admin-Domain"
    Scans C:\ and excludes the two specific accounts in addition to the two
    default exclusions (four identities filtered in total).
    
.EXAMPLE
    .\Get-NTFSPermissions.ps1 -RootPath "E:\" -SkipDefaultExclusions
    Scans E:\ with no exclusions at all. NT AUTHORITY\SYSTEM and
    BUILTIN\Administrators will appear in the report.
    
.EXAMPLE
    .\Get-NTFSPermissions.ps1 -RootPath "D:\Shares" -ExcludedPaths "D:\Shares\data\USERS","D:\Shares\Temp"
    Scans D:\Shares but skips the two specified folders entirely. Default
    exclusions still apply.
    
.EXAMPLE
    .\Get-NTFSPermissions.ps1 -RootPath "D:\Shares" -MaxDepth 2
    Scans D:\Shares up to two levels deep (e.g. D:\Shares\Dept\Sub is included
    but D:\Shares\Dept\Sub\Child is not).
    
.NOTES
    Requires read access to the target directory tree and its ACLs.
    The output folder C:\!TECH must exist before running the script.
    Run as an account with sufficient privileges to read all ACLs (ideally
    local Administrator or Backup Operator).

    The IsExplicit column (True/False) flags any ACE where IsInherited = False,
    meaning the permission was set directly on that folder rather than flowing
    down from a parent. Review these entries carefully — they often indicate
    deliberate access changes or potential misconfigurations.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [string[]]$ExcludedUsersAndGroups = @(),

    [string[]]$ExcludedPaths = @(),

    [switch]$SkipDefaultExclusions,

    # -1 means unlimited depth (original behaviour)
    [int]$MaxDepth = -1
)

# ---------------------------------------------------------------------------
# Helper: calculate folder depth relative to RootPath
# ---------------------------------------------------------------------------
function Get-RelativeDepth {
    param([string]$FullPath, [string]$BasePath)
    $base = $BasePath.TrimEnd('\')
    if ($FullPath -eq $base) { return 0 }
    $relative = $FullPath.Substring($base.Length).TrimStart('\')
    return ($relative -split '\\').Count
}

# ---------------------------------------------------------------------------
# Build the exclusion list
# ---------------------------------------------------------------------------
$defaultExclusions = @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')
if (-not $SkipDefaultExclusions) {
    $ExcludedUsersAndGroups = $defaultExclusions + $ExcludedUsersAndGroups
}

# ---------------------------------------------------------------------------
# Prepare output file
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$hostname  = $env:COMPUTERNAME
$OutFile   = "C:\!TECH\NTFSPermissions_${hostname}_${timestamp}.csv"

$csvHeader = 'FolderPath,IdentityReference,AccessControlType,IsInherited,IsExplicit,FileSystemRights,InheritanceFlags,PropagationFlags'
Add-Content -Value $csvHeader -Path $OutFile

# ---------------------------------------------------------------------------
# Console banner
# ---------------------------------------------------------------------------
$depthLabel = if ($MaxDepth -lt 0) { 'unlimited' } else { $MaxDepth.ToString() }

Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '  NTFS Permission Scanner' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host "  Root path  : $RootPath"
Write-Host "  Max depth  : $depthLabel"
Write-Host "  Exclusions : $($ExcludedUsersAndGroups.Count) identity/identities filtered"
Write-Host "  Output     : $OutFile"
Write-Host '------------------------------------------------------' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Collect folders
# ---------------------------------------------------------------------------
Write-Host '[1/3] Enumerating folders...' -ForegroundColor Yellow

$allFolders = Get-ChildItem -Path $RootPath -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PSIsContainer -and
        $ExcludedPaths -notcontains $_.FullName -and
        ($MaxDepth -lt 0 -or (Get-RelativeDepth -FullPath $_.FullName -BasePath $RootPath) -le $MaxDepth)
    }

# Include the root folder itself
$rootItem  = Get-Item -Path $RootPath
$allFolders = @($rootItem) + @($allFolders)

$totalFolders = $allFolders.Count
Write-Host "    Found $totalFolders folder(s) to scan." -ForegroundColor Green
Write-Host ''

# ---------------------------------------------------------------------------
# Scan ACLs
# ---------------------------------------------------------------------------
Write-Host '[2/3] Reading ACLs...' -ForegroundColor Yellow

$totalACEs    = 0
$explicitACEs = 0
$errorCount   = 0
$processed    = 0

foreach ($Folder in $allFolders) {
    $processed++

    # Progress bar
    $pct = [int](($processed / $totalFolders) * 100)
    Write-Progress -Activity 'Scanning NTFS permissions' `
                   -Status "$processed of $totalFolders : $($Folder.FullName)" `
                   -PercentComplete $pct

    try {
        $acl  = Get-Acl -Path $Folder.FullName -ErrorAction Stop
        $aces = $acl.Access
    }
    catch {
        Write-Warning "  Could not read ACL: $($Folder.FullName) - $_"
        $errorCount++
        continue
    }

    foreach ($ace in $aces) {
        if ($ExcludedUsersAndGroups -contains $ace.IdentityReference.Value) { continue }

        $isExplicit = -not $ace.IsInherited   # True when permission is NOT inherited

        $csvLine = '"{0}","{1}",{2},{3},{4},"{5}",{6},{7}' -f
            $Folder.FullName,
            $ace.IdentityReference.Value,
            $ace.AccessControlType,
            $ace.IsInherited,
            $isExplicit,
            $ace.FileSystemRights,
            $ace.InheritanceFlags,
            $ace.PropagationFlags

        Add-Content -Value $csvLine -Path $OutFile

        $totalACEs++
        if ($isExplicit) { $explicitACEs++ }
    }
}

Write-Progress -Activity 'Scanning NTFS permissions' -Completed

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '[3/3] Complete.' -ForegroundColor Yellow
Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '  SUMMARY' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host ("  Folders scanned  : {0,6}"   -f $totalFolders)
Write-Host ("  Total ACEs       : {0,6}"   -f $totalACEs)

if ($explicitACEs -gt 0) {
    Write-Host ("  Explicit (non-inherited) ACEs : {0,6} - REVIEW THESE" -f $explicitACEs) -ForegroundColor Yellow
} else {
    Write-Host ("  Explicit (non-inherited) ACEs : {0,6}" -f $explicitACEs) -ForegroundColor Green
}

if ($errorCount -gt 0) {
    Write-Host ("  ACL read errors  : {0,6}  (see warnings above)" -f $errorCount) -ForegroundColor Red
} else {
    Write-Host ("  ACL read errors  : {0,6}" -f $errorCount) -ForegroundColor Green
}

Write-Host '------------------------------------------------------' -ForegroundColor Cyan
Write-Host "  Report saved to:" -ForegroundColor Green
Write-Host "  $OutFile" -ForegroundColor White
Write-Host '------------------------------------------------------' -ForegroundColor Cyan
Write-Host "  TIP: Filter the CSV by IsInherited - False to review explicit permissions." -ForegroundColor Green
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host ''