# Function to remove special characters from a string
function Remove-StringSpecialCharacter {
<#
.SYNOPSIS
  This function will remove the special character from a string.
  
.DESCRIPTION
  This function will remove the special character from a string.
  I'm using Unicode Regular Expressions with the following categories
  \p{L} : any kind of letter from any language.
  \p{Nd} : a digit zero through nine in any script except ideographic 
  
  http://www.regular-expressions.info/unicode.html
  http://unicode.org/reports/tr18/

.PARAMETER String
  Specifies the String on which the special character will be removed

.SpecialCharacterToKeep
  Specifies the special character to keep in the output

.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "^&*@wow*(&(*&@"
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*"
  
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*" -SpecialCharacterToKeep "*","_","-"
  wow-_*

.NOTES
  Francois-Xavier Cat
  @lazywinadmin
  www.lazywinadmin.com
  github.com/lazywinadmin
#>
  [CmdletBinding()]
  param (
    [Parameter(ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [Alias('Text')]
    [System.String[]]$String,
    
    [Alias("Keep")]
    #[ValidateNotNullOrEmpty()]
    [String[]]$SpecialCharacterToKeep
  )
  PROCESS {
    if ($PSBoundParameters["SpecialCharacterToKeep"]) {
      $Regex = "[^\p{L}\p{Nd}"
      foreach ($Character in $SpecialCharacterToKeep) {
        if ($Character -eq "-") {
          $Regex += "-"
        } else {
          $Regex += [Regex]::Escape($Character)
        }
      }
      $Regex += "]+"
    } else {
      $Regex = "[^\p{L}\p{Nd}]+"
    }
    
    foreach ($Str in $String) {
      Write-Verbose -Message "Original String: $Str"
      $Str -replace $Regex, ""
    }
  }
}

# Check if running old version of Altaro (V8)
# It's possible for both to be installed, as in an upgrade scenario. If that's the case, use 9 by default.

# First, validate and use $ManuallySpecifiedVersion if supplied
if ($ManuallySpecifiedVersion -and ($ManuallySpecifiedVersion -eq "8" -or $ManuallySpecifiedVersion -eq "9")) {
    if ($ManuallySpecifiedVersion -eq "8") {
        $ProviderName = "Altaro VM Backup"
        $UsedVersion = "8"
    } else {
        $ProviderName = "VM Backup"
        $UsedVersion = "9"
    }
    Write-Host "NOTICE: User manually specified version $UsedVersion. Using verson $UsedVersion provider name: $ProviderName"
} else {
    # Detect installed versions
    $software = Get-CimInstance -Class Win32_Product | Where-Object { $_.Name -match "(?i)Altaro VM Backup|Hornetsecurity VM Backup" }

    $hasV8 = $false
    $hasV9 = $false

    foreach ($item in $software) {
        if ($item.Version -match "^8") { $hasV8 = $true }
        elseif ($item.Version -match "^9") { $hasV9 = $true }
    }

    if ($hasV9) {
        $UsedVersion = "9"
        if ($hasV8) {
            Write-Host "NOTICE: Both version 8 and version 9 detected. Will use version 9 provider name by default. Use `$ManuallySpecifiedVersion to override to older versions if needed."
        }
        $ProviderName = "VM Backup"
    } elseif ($hasV8) {
        $UsedVersion = "8"
        $ProviderName = "Altaro VM Backup"
    } else {
        $UsedVersion = "9 (default)"
        $ProviderName = "VM Backup"
    }
}

Write-Host "Using version $UsedVersion Provider Name: $ProviderName"

# Define event log IDs
$EventIDs = @(
    5000, 5001, 5002, 5003, 5004, 5005, 5007
)

# Collect all relevant events using FilterHashtable
$events = @()
foreach ($EventID in $EventIDs) {
    $events += Get-WinEvent -FilterHashtable @{ProviderName = $ProviderName; Id = $EventID} -ErrorAction SilentlyContinue
}

if ($IssuesOnly -eq "true") {
    # Filter events for messages containing "fail" or "warn"
    $filteredEvents = $events | Where-Object { $_.Message -match "fail|warn" }

    # Sort filtered events by TimeCreated and select the last $RecordsCount
    $latestEvents = $filteredEvents | Sort-Object -Property TimeCreated -Descending | Select-Object -First $RecordsCount
} else {
    # Sort all events by TimeCreated and select the last $RecordsCount
    $latestEvents = $events | Sort-Object -Property TimeCreated -Descending | Select-Object -First $RecordsCount
}

# Output the event ID, time, and formatted message in a table
$eventDetails = $latestEvents | ForEach-Object {
    $formattedMessage = Remove-StringSpecialCharacter -SpecialCharacterToKeep "/",":"," ","-" ($_.Message -replace "`r`n", " ")
    [PSCustomObject]@{
        EventID = $_.Id
        TimeCreated = $_.TimeCreated
        Message = $formattedMessage
    }
}

# Syncro script variable to toggle logging
if ($LogOutput -eq "true") {
    ## Define the log directory and log file path
    $logDirectory = "C:\!TECH\HornetsecurityBackupLogs"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$logDirectory\HornetsecurityEvents_$timestamp.csv"

    # Create the log directory if it does not exist
    if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    # Start logging to a transcript
    $eventDetails | Export-Csv -Path $logFile -NoTypeInformation
    Write-Host "Saved out output to: $logFile"
}

# Print the output
$eventDetails | Format-Table -AutoSize
