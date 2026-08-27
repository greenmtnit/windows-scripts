<#
.SYNOPSIS
    Creates a new project folder from the company template folder, renames
    the files, and fills in the Client Name / Project Title / Project Number
    placeholders inside the Word (.docx) and Excel (.xlsx) files.

.PARAMETER ClientName
    Full client name, e.g. "Evalco, Inc". Prompted for if not supplied.

.PARAMETER ProjectTitle
    Project title, e.g. "Server Migration". Prompted for if not supplied.

.PARAMETER ProjectNumber
    Project number (main project ticket number), e.g. "12345". Prompted for if not supplied.

.PARAMETER ClientAbbreviation
    Short client code used in folder/file names, e.g. "EVALCO".
    Prompted for if not supplied.

.PARAMETER ClientFolder
    Full path to the client's folder, e.g.
    "$env:USERPROFILE\Green Mountain IT Solutions, LLC\Clients - Documents\Evalco Inc"
    Prompted for if not supplied.

.PARAMETER TemplateFolder
    Optional. Overrides the default template source folder.
    Default:
    "$env:USERPROFILE\Green Mountain IT Solutions, LLC\Clients - Documents\!Project Template"

.EXAMPLE
    .\New-Project.ps1 -ClientName "Evalco, Inc" -ProjectTitle "Server Migration" `
        -ProjectNumber "12345" -ClientAbbreviation "EVALCO" `
        -ClientFolder "C:\Users\TimWest\Green Mountain IT Solutions, LLC\Clients - Documents\Evalco Inc"

.NOTES
    - Requires Microsoft Word and Excel installed (uses COM automation).
    - Run in Windows PowerShell (not PowerShell 7 / pwsh) - Office COM
      automation needs the full .NET Framework.
    - Close the template files before running so Word/Excel don't lock them.
#>

[CmdletBinding()]
param(
    [string]$ClientName,
    [string]$ProjectTitle,
    [string]$ProjectNumber,
    [string]$ClientAbbreviation,
    [string]$ClientFolder,
    [string]$TemplateFolder = (Join-Path $env:USERPROFILE "Green Mountain IT Solutions, LLC\Clients - Documents\!Project Template")
)

# This script must run in PowerShell 5 (not PowerShell 7 / pwsh)
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "WARNING: This script is designed for Windows PowerShell 5 (uses Office COM automation)." -ForegroundColor Yellow
    Write-Host "You are running PowerShell $($PSVersionTable.PSVersion). Word/Excel automation may fail in PowerShell 7+ (pwsh.exe). You can switch to PowerShell 5 by typing `"powershell`" at your prompt and pressing enter" -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -notmatch '^[Yy]') {
        exit 1
    }
}

# --- 0. Prompt for anything not supplied ---
if ([string]::IsNullOrWhiteSpace($ClientName))         { $ClientName         = Read-Host "Enter the Client Name (e.g. Evalco, Inc)" }
if ([string]::IsNullOrWhiteSpace($ProjectTitle))        { $ProjectTitle       = Read-Host "Enter the Project Title (e.g. Server Migration)" }
if ([string]::IsNullOrWhiteSpace($ProjectNumber))       { $ProjectNumber      = Read-Host "Enter the Project Number (e.g. 12345)" }
if ([string]::IsNullOrWhiteSpace($ClientAbbreviation))  { $ClientAbbreviation = Read-Host "Enter the Client Abbreviation (e.g. EVALCO)" }
if ([string]::IsNullOrWhiteSpace($ClientFolder))        { $ClientFolder       = Read-Host "Enter the full path to the Client Folder (e.g. $env:USERPROFILE\Green Mountain IT Solutions, LLC\Clients - Documents\Evalco Inc)" }

foreach ($pair in @(
        @{Name="ClientName"; Value=$ClientName},
        @{Name="ProjectTitle"; Value=$ProjectTitle},
        @{Name="ProjectNumber"; Value=$ProjectNumber},
        @{Name="ClientAbbreviation"; Value=$ClientAbbreviation},
        @{Name="ClientFolder"; Value=$ClientFolder}
    )) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) {
        Write-Host "$($pair.Name) cannot be blank. Exiting." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $TemplateFolder)) {
    Write-Host "Template folder not found: $TemplateFolder" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ClientFolder)) {
    Write-Host "Client folder not found: $ClientFolder" -ForegroundColor Red
    exit 1
}

# --- 1. Find/create the year folder under Projects ---
$year = (Get-Date).Year
$projectsFolder = Join-Path $ClientFolder "Projects"
$yearFolder = Join-Path $projectsFolder $year

if (-not (Test-Path $projectsFolder)) {
    New-Item -ItemType Directory -Path $projectsFolder | Out-Null
    Write-Host "Created folder: $projectsFolder"
}

if (-not (Test-Path $yearFolder)) {
    New-Item -ItemType Directory -Path $yearFolder | Out-Null
    Write-Host "Created folder: $yearFolder"
}

# --- 2. Create the project folder ---
# Format: 12345 EVALCO Server Migration
$safeTitle = $ProjectTitle -replace '[\\/:*?"<>|]', ''
$projectFolderName = "$ProjectNumber $ClientAbbreviation $safeTitle"
$projectFolder = Join-Path $yearFolder $projectFolderName

if (Test-Path $projectFolder) {
    Write-Host "Project folder already exists: $projectFolder" -ForegroundColor Red
    Write-Host "Exiting to avoid overwriting existing files." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $projectFolder | Out-Null
Write-Host "Created project folder: $projectFolder" -ForegroundColor Green

# --- 3. Copy and rename the template files ---
# "Brainstorm Template.docx"     -> "12345 EVALCO Server Migration - Brainstorm.docx"
# "Stages & Steps Template.docx" -> "12345 EVALCO Server Migration - Stages & Steps.docx"
# "PO Template.xlsx"             -> "12345 EVALCO Server Migration - PO.xlsx"
$templateFiles = Get-ChildItem -Path $TemplateFolder -File

foreach ($file in $templateFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $extension = $file.Extension

    # Strip "Template" (and any trailing/leading space) from the base name
    $shortName = ($baseName -replace '\s*Template\s*$', '').Trim()

    $newFileName = "$projectFolderName - $shortName$extension"
    $destPath = Join-Path $projectFolder $newFileName

    Copy-Item -Path $file.FullName -Destination $destPath
    Write-Host "Copied: $($file.Name) -> $newFileName"
}

# --- 4. Replace placeholders inside Word files ---
$wordFiles = Get-ChildItem -Path $projectFolder -Filter *.docx

if ($wordFiles.Count -gt 0) {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false

    foreach ($file in $wordFiles) {
        Write-Host "Updating Word file: $($file.Name)"
        $doc = $word.Documents.Open($file.FullName)

        $replacements = @{
            "[[CLIENT_NAME]]"    = $ClientName
            "[[PROJECT_TITLE]]"  = $ProjectTitle
            "[[PROJECT_NUMBER]]" = $ProjectNumber
        }

        # Replace in main body, headers, and footers of every section
        foreach ($story in $doc.StoryRanges) {
            $range = $story
            while ($null -ne $range) {
                foreach ($key in $replacements.Keys) {
                    $find = $range.Find
                    $find.ClearFormatting()
                    $find.Replacement.ClearFormatting()
                    # Pass FindText/ReplaceWith directly as arguments rather than
                    # relying on $find.Text / $find.Replacement.Text + $null args -
                    # passing $null here overrides those and searches for "".
                    $find.Execute($key, $false, $false, $false, $false, $false, $true, 1, $false, $replacements[$key], 2) | Out-Null
                }
                $range = $range.NextStoryRange
            }
        }

        $doc.Save()
        $doc.Close()
    }

    $word.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
}

# --- 5. Replace placeholders inside Excel files ---
$excelFiles = Get-ChildItem -Path $projectFolder -Filter *.xlsx

if ($excelFiles.Count -gt 0) {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    foreach ($file in $excelFiles) {
        Write-Host "Updating Excel file: $($file.Name)"
        $wb = $excel.Workbooks.Open($file.FullName)

        foreach ($ws in $wb.Worksheets) {
            $usedRange = $ws.UsedRange
            $usedRange.Replace("[[CLIENT_NAME]]", $ClientName) | Out-Null
            $usedRange.Replace("[[PROJECT_TITLE]]", $ProjectTitle) | Out-Null
            $usedRange.Replace("[[PROJECT_NUMBER]]", $ProjectNumber) | Out-Null
        }

        $wb.Save()
        $wb.Close()
    }

    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}

Write-Host ""
Write-Host "Done! New project files are ready in:" -ForegroundColor Cyan
Write-Host $projectFolder -ForegroundColor Cyan