<#
    Check-BSODs.ps1
  
    Monitors Windows systems for new blue screen of death (BSOD) crahses. When a new crash occurs, it uploads the latest dump file, analyzes it using BlueScreenView, and automatically creates a SyncroRMM ticket with detailed notes.

    The script uses a marker file to keep track of the last run to avoid processing old dumps.

    First execution only initializes the tracking marker and does not process anything.

    Recommend scheduling the script to run hourly using a Remote Monitoring and Management (RMM) tool.
#>

# Import the SyncroRMM Module
Import-Module $env:SyncroModule

# Check if IgnoreBSODs asset custom field is set

if ($IgnoreBSODs -eq "true") {
    Write-Host "`$IgnoreBSODs is set. Script will exit."
    exit 0
}

# Marker file path
$markerFile = "C:\Program Files\Green Mountain IT Solutions\Scripts\bsod_script_last_run.txt"

# Check for an existing marker file (or other marker method) with a timestamp for the last script run time.
if (!(Test-Path $markerFile)) {
    # If this marker does not exist, this is the first run. In that case, just initialize the marker, then exit.
    Write-Host "Marker file not found. This is likely the first script run. Initializing marker file and exiting."
    Get-Date | Out-File $markerFile
    exit 0
}

# Save the last run timestamp in a variable.
$lastRunTimestamp = [datetime]::Parse((Get-Content $markerFile))

# Update the marker file with the current timestamp.
Get-Date | Out-File $markerFile

# Check the minidump folder for any minidump files with timestamp newer than the last run timestamp.
$minidumpFolder = "C:\Windows\Minidump"
$files = Get-ChildItem $minidumpFolder -Filter "*.dmp" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $lastRunTimestamp }

# If no new minidumps are found, exit cleanly with code 0.
if (!$files) {
    Write-Host "No new minidump files found since last script run. Exiting."
    exit 0
}

# If new minidumps ARE found, proceed.

# Create a ticket using the SyncroRMM Create-Syncro-Ticket cmdlet.
$value = Create-Syncro-Ticket -Subject "$env:COMPUTERNAME - BSOD Crash" -IssueType "Maintenance" -Status "New"

# The ticket ID of the created ticket will be $value.ticket.id
$ticketID = $value.ticket.id

# Number is different from ID. Number is the public-facing number; value is in the URL.
$ticketNumber = $value.ticket.number

Write-Host "Created Syncro ticket number $ticketNumber"

# Initialize the ticket notes
$ticketNotes = "Remember to follow process: https://app.process.st/workflows/How-to-handle-a-BSOD-Blue-Screen-RMM-Alert-nwiGLI0_WuVIpyeIgwZAsw/dashboard `n`n"

# Run BSOD analysis
# Get the latest minidump file.
$latestDump = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1

###########################################################
# Perform an action on each file
Write-Output "Uploading lastest dump file to Syncro asset: $($latestDump.FullName)"
Upload-File -FilePath $($latestDump.FullName)

# Analyze BSOD

# Download and run BlueScreenView
try {
    Invoke-WebRequest -Uri "https://www.nirsoft.net/utils/bluescreenview.zip" -OutFile "$($ENV:Temp)\bluescreenview.zip"
    Expand-Archive "$($ENV:Temp)\bluescreenview.zip" -DestinationPath "$($ENV:Temp)" -Force

    Start-Process -FilePath "$($ENV:Temp)\BlueScreenView.exe" `
        -ArgumentList "/LoadFrom 3 /SingleDumpFile `"$($latestDump.FullName)`" /scomma `"$($ENV:Temp)\Export.csv`"" `
        -Wait
}
catch {
    Write-Host "BSODView Command has Failed: $($_.Exception.Message)"
    exit 1
}

$BSODs = Get-Content "$($ENV:Temp)\Export.csv" |
ConvertFrom-Csv -Delimiter ',' -Header Dumpfile, Timestamp, Reason, Errorcode, Parameter1, Parameter2, Parameter3, Parameter4, CausedByDriver |
ForEach-Object {
    $_.Timestamp = [datetime]::Parse($_.Timestamp, [System.Globalization.CultureInfo]::CurrentCulture)
    $_
}

Remove-Item "$($ENV:Temp)\Export.csv" -Force

$BSODFilter = $BSODs | Select-Object -First 1 # Filter to get most recent BSOD

if ($BSODFilter) {

    $bsodTime = $BSODFilter.Timestamp

    $message = "BSOD Found. Crash time:`n$bsodTime`n`nBlueScreenView Analysis`nDriver: $($BSODFilter.CausedByDriver)`nError code: $($BSODFilter.Errorcode)`nReason: $($BSODFilter.Reason)`n"

    # Add the log message to the Syncro asset activity log
    Log-Activity -Message "$message" -EventName "BSOD Analysis"
    
    # Add the log message to the ticket notes
    $ticketNotes += $message
}

# Check if the BSOD is the only BSOD to occur in the last 60 days
$sixtyDaysAgo = (Get-Date).AddDays(-60)

# Get all minidump files modified in the last 60 days
$recentDumps = Get-ChildItem "C:\Windows\Minidump" -Filter "*.dmp" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $sixtyDaysAgo }

if ($recentDumps.Count -le 1) {
    $ticketNotes += "`nFrequency:`nThis IS the only BSOD in the last 60 days.`nNotify client per our process and close ticket.`n"
} else {
    $ticketNotes += "`nFrequency:`nThis is NOT the only BSOD in the last 60 days.`nFurther investigation is needed.`n"

    # List up to 10 previous BSODs
    $previous = $recentDumps |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    $ticketNotes += "Previous BSODs:`n"
    foreach ($dump in $previous) {
        $ticketNotes += "$($dump.LastWriteTime) - File: $($dump.Name)`n"
    }
    $ticketNotes += "Note: these times are based on the Mimidump file write time and may not exactly match the actual crash time.`n"
}

# If the var $AssetBirthDate is set (this will be set elsewhere), use it to determine age of the computer asset.
if ($AssetBirthDate) {

    # Strip "(Estimated)" if present
    $cleanBirthDate = $AssetBirthDate -replace "\s*\(Estimated\)", ""

    try {
        $birthDate = [datetime]::Parse($cleanBirthDate)
        $ageYears = ((Get-Date) - $birthDate).TotalDays / 365
    }
    catch {
        $ticketNotes += "`nError: Unable to parse AssetBirthDate value: $AssetBirthDate`n"
    }
}

# Get asset info
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$bios = Get-CimInstance -ClassName Win32_BIOS

$model = $computerSystem.Model
$manufacturer = $computerSystem.Manufacturer
$serialNumber = $bios.SerialNumber
$cpu = Get-CimInstance Win32_Processor
$memoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
# Get physical disk information
$physicalDisks = Get-CimInstance Win32_DiskDrive

$diskSummary = ""
foreach ($disk in $physicalDisks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 1)
    $diskSummary += "$($disk.Model) - $sizeGB GB ($($disk.InterfaceType))`n"
}

$ticketNotes += "`nAsset`nModel: $manufacturer $model`nSerial: $serialNumber`nAge: $([math]::Round($ageYears,2)) years`n"
$ticketNotes += "`nHardware`nCPU: $($cpu.Name)`nMemory: $memoryGB GB`nDisks: $diskSummary"

# Finally, add ticket notes to the ticket
Create-Syncro-Ticket-Comment -TicketIdOrNumber $ticketID -Subject "Diagnosis" -Body $ticketNotes -Hidden "false" -DoNotEmail "true"