<#
  Check-CompatDataFiles.ps1
  
  Searches all CompataData.xml files from C:\$WINDOWS.~BT\Sources\Panther for possible blocks,
  then attempts to identify problematic drivers that may be blocking a Windows upgrade.
  Also collects the files into a .ZIP archive, then uploads it to Syncro asset page.
  
#>

Import-Module $env:SyncroModule

# Create target output folder if it doesn't exist
$destFolder = 'C:\!TECH'
if (!(Test-Path $destFolder)) {
    New-Item -Path $destFolder -ItemType Directory | Out-Null
}

# Get current timestamp in required format
$timestamp = Get-Date -Format 'yyyyMMdd_HHmm'

# Define output ZIP file path
$zipFile = Join-Path $destFolder ("CompatData$timestamp.zip")

# Source folder with ?\ prefix for long paths
$sourcePath = 'C:\$WINDOWS.~BT\Sources\Panther'

# Get matching files
$files = Get-ChildItem -Path $sourcePath -Filter 'CompatData*.xml' -ErrorAction SilentlyContinue

if ($files.Count -eq 0) {
    Write-Host "No CompatData*.xml files found." -ForegroundColor Yellow
} else {
    Write-Host "Searching CompataData files for blocks..."
    
    $results = $files | Select-String -Pattern 'BlockMigration="True"|BlockingType="Hard"'

    if (-not $results) {
        Write-Host "No blocks found."
    } else {
        Write-Host "Found blocks:"
        $results | Select-Object Path, LineNumber, Line | Format-Table -AutoSize
        
        Write-Host "Trying to identify problematic drivers..."
        
        # Parse driver names from matching lines
        $driverNames = $results | ForEach-Object {
            if ($_.Line -match 'Inf="([^"]+)"') {
                $matches[1]
            }
        } | Sort-Object -Unique

        # Get all drivers from pnputil once (faster than calling it per driver)
        $pnpOutput = pnputil /enum-drivers

        # Parse pnputil output into driver objects
        $drivers = @()
        $current = @{}
        foreach ($line in $pnpOutput) {
            if ($line -match '^\s*Published Name:\s+(.+)') {
                $current = @{ PublishedName = $matches[1].Trim() }
            } elseif ($line -match '^\s*Original Name:\s+(.+)') {
                $current['OriginalName'] = $matches[1].Trim()
            } elseif ($line -match '^\s*Provider Name:\s+(.+)') {
                $current['ProviderName'] = $matches[1].Trim()
            } elseif ($line -match '^\s*Class Name:\s+(.+)') {
                $current['ClassName'] = $matches[1].Trim()
            } elseif ($line -eq '' -and $current.Count -gt 0) {
                $drivers += [PSCustomObject]$current
                $current = @{}
            }
        }

        # Match and output
        foreach ($inf in $driverNames) {
            $match = $drivers | Where-Object { $_.OriginalName -eq $inf -or $_.PublishedName -eq $inf }
            if ($match) {
                Write-Host "`nFound: $inf"
                $match | Select-Object PublishedName, OriginalName, ProviderName, ClassName | Format-Table -AutoSize
            } else {
                Write-Host "`nNo pnputil match found for: $inf"
            }
        }


    }
    
    # Create temporary staging folder
    $tempFolder = Join-Path $env:TEMP ("CompatData_" + [guid]::NewGuid().ToString())
    New-Item -Path $tempFolder -ItemType Directory | Out-Null

    # Copy files to staging folder (so Compress-Archive can work without ?\ prefix)
    foreach ($file in $files) {
        Copy-Item -LiteralPath $file.FullName -Destination $tempFolder
    }

    # Compress into ZIP
    Compress-Archive -Path (Join-Path $tempFolder '*') -DestinationPath $zipFile -Force

    # Remove temp folder
    Remove-Item -Path $tempFolder -Recurse -Force

    Write-Host "ZIP created at: $zipFile and uploaded to Syncro asset" -ForegroundColor Green
    
    Upload-File -FilePath $zipFile
}

