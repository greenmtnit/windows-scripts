<#
.SYNOPSIS
    This PowerShell script performs basic and SMART disk checks for monitoring disk health.

.DESCRIPTION
    This script checks the health status of disks attached to the system. It perform both basic checks using native PowerShell commands and SMART data analysis. It identifies potential issues such as failed self tests and read errors. The script also initiates SMART tests and generates Syncro RMM alerts if problems are detected.

.NOTES
    - This script requires administrative privileges to run.
    - The script uses Chocolatey to install the Smartmontools package. It will install both Chocolately and Smartmontools.

.EXAMPLE
    .\DiskHealthCheck.ps1
    Runs the script to perform disk health checks.

#>

# VARIABLES
function ConvertTo-Boolean {
    param (
        [string]$value
    )
    switch ($value.ToLower()) {
        'true' { return $true }
        '1' { return $true }
        't' { return $true }
        'y' { return $true }
        'yes' { return $true }
        'false' { return $false }
        '0' { return $false }
        'f' { return $false }
        'n' { return $false }
        'no' { return $false }
        default { throw "Invalid boolean string: $value" }
    }
}

# Import the Syncro module, if it exists, and handle Syncro variables
if ($null -ne $env:SyncroModule) { 
    Import-Module $env:SyncroModule -DisableNameChecking
    # Convert Syncro's string variables to boolean
    $TestingMode = ConvertTo-Boolean $TestingMode
    $SuppressRMMAlerts = ConvertTo-Boolean $SuppressRMMAlerts
    $DebugSMART = ConvertTo-Boolean $DebugSMART
    $DelaySmartctlInstall = ConvertTo-Boolean $DelaySmartctlInstall
    $ForceSelfTest = ConvertTo-Boolean $ForceSelfTest
    $ForceSmartctlInstall = ConvertTo-Boolean $ForceSmartctlInstall
    $LogOutput = ConvertTo-Boolean $LogOutput    
}
# If not running in Syncro, handle variables here. You can change these as needed.
else {
    $TestingMode = $false # Set to $true to set values that will be sure to generate alerts, for testing purposes
    $SuppressRMMAlerts = $false  # Included here for completeness only (no need for Syncro RMM alerts if not running in Syncro!
    $DebugSMART = $false # Set to $true to generate verbose output of SMART info
    $DelaySmartctlInstall = $true # Delay smartmontools install by up to 5 minutes to avoid excessive downloads when running on multiple machines. Default is $true
    $ForceSelfTest = $false # Force a SMART self-test to run for supported disks, regardless of when the last self-test ran (i.e. ignore MaxTestInterval)
    $ForceSmartctlInstall = $false #Force installation of Smartctl even script detects it's already installed
    $LogOutput = $false # Log output to a file
}

# Testing thresholds
# We don't often need to change these ad-hoc, so we don't pass these in as Syncro variables.
$MaxTemperature = 70 # Maximum disk temperature in Celsius. Default is 70.
$MaxPowerCycles = 4000 # How many times the drive was turned off and on. Default is 4000.
$MaxPowerOnTime = 35063 # How many hours the drive has been on. Default is 35063 (about 4 years).
$MaxTestInterval = 168 # Max hours between SMART tests. Default is 168 hours (1 week).

# Enable logging, if requested
if ($LogOutput -eq "true") {
    ## Define the log directory and log file path
    $logDirectory = "C:\!TECH\DiskScriptLogs"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "$logDirectory\Check-DiskHealthLog_$timestamp.txt"

    # Create the log directory if it does not exist
    if (-not (Test-Path -Path $logDirectory -ErrorAction SilentlyContinue)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    # Start logging to a transcript
    Start-Transcript -Path $logFile -Append
    Write-Host "Logging output to: $logFile"
}


# Testing Mode
if ($TestingMode) {
    # Check if user supplied values that conflict with Testing Mode
    if ($PSBoundParameters.ContainsKey('MaxPowerOnTime') -or $PSBoundParameters.ContainsKey('MaxTemperature')) {
        Write-Output "NOTICE: TestingMode is set, but custom values for MaxPowerOnTime and/or MaxTemperature were provided. These values will be ignored in testing mode."
    }
    # Set testing mode values
    $MaxPowerOnTime = 0
    $MaxTemperature = 0
}


if ($ForceSelfTest) {
    Write-Host "Forcing a self-test"
    $MaxTestInterval = -1
}


# FUNCTION DEFINITIONS

# Function to check if script is running on a virtual machine
function Check-VM {
    $model = Get-CimInstance win32_computersystem | select Model
    if ($model -match "virtual") {
        return $true
    }
    return $false
}

# Function to print a custom PowerShell object with nested properties in a readable format. Used for printing verbose SMART data.
function Print-ObjectProperties {
    param (
        [Parameter(Mandatory = $true)]
        $Object,
        [string]$Indent = ""
    )

    $Object.PSObject.Properties | ForEach-Object {
        Write-Host "$Indent$($_.Name):"
        $Value = $_.Value
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            Print-ObjectProperties -Object $Value -Indent "$Indent    "
        } elseif ($Value -is [System.Object[]]) {
            $Value | ForEach-Object {
                Print-ObjectProperties -Object $_ -Indent "$Indent    "
            }
        } else {
            Write-Host "$Indent    $Value"
        }
    }
}

#Function to check SMART values against a provided threshold value
function Check-Threshold {
    param (
        [int]$Value,
        [int]$Threshold,
        [string]$ParameterName
    )
    if (-not $Value) {
        Write-IndentedHost "Unable to obtain $ParameterName."
        return $false
    }
    
    if ($Value -ge $Threshold) {
        Write-IndentedHost "WARNING! Disk has exceeded $ParameterName threshold of $Threshold. Value: $Value"
        return $false
    } else {
        Write-IndentedHost "$ParameterName`: $Value. Max is set to $Threshold."
        return $true
    }
}

# Function to write a message like Write-Host, but with 4 spaces as an indent
function Write-IndentedHost {
    param (
        [string]$Message
    )

    # Add four spaces to the beginning of each line
    $IndentedMessage = $Message -replace '^', '    '

    # Write the indented message to the console
    Write-Host $IndentedMessage
}

# Function to install smartmontools, if not already installed
function Install-Smartmontools {
    param (
        [string]$ProgramPath
    )

    if ((Test-Path $ProgramPath) -and (! $ForceSmartctlInstall)) {
        Write-Host "Found smartctl at $ProgramPath, using it"
    }
    else {
        if ($ForceSmartctlInstall) {
            Write-Host "ForceSmartctlInstall, running smartctl install regardless of current install status"
        }
        else {
            Write-Host "smartctl not found, installing it"
        }

        # Check for delay
        if ($DelaySmartctlInstall) {
            $randomDelay = Get-Random -Maximum 300
            if ($TestingMode) {
                Write-Host "Testing mode detected. Skipping delay. Would have delayed $randomDelay seconds."
            }
            else {
                Write-Host "Delaying for $randomDelay seconds"
                Start-Sleep -Seconds $randomDelay
            }
        }

        $syncroPath = "$env:ProgramFiles\RepairTech\Syncro\kabuto_app_manager\choco.exe"
        $chocoPath = "$env:ProgramData\chocolatey\choco.exe"
        $packageName = "smartmontools"

        # First check for Chocolatey, and install it if it's not available
        try {
            # Check for Chocolatey in Syncro path
            if (Test-Path -Path $syncroPath) {
                Write-Host "Found Chocolatey from Syncro, using it."
                $choco = $syncroPath
            }
            # Check for Chocolatey in its default location
            elseif (Test-Path -Path $chocoPath) {
                Write-Host "Found Chocolatey in its default location, using it."
                $choco = $chocoPath
            }
            else {
                Write-Host "Chocolatey not found, installing it..."
                
                # Install Chocolatey
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

                $choco = $chocoPath
            }

            Write-Host "Installing $packageName"
            
            # Use the "upgrade" command, which will either install or upgrade the package
            & $choco upgrade $packageName -y --no-progress --limit-output
        }
        catch {
            Write-Host "Error installing $packageName : $_"
        }
    }
}

# MAIN SCRIPT LOGIC

# Actual script code starts here

# Check if Syncro asset custom field $ignoreAllDiskErrors is set. If so, exit
if ($ignoreAllDiskErrors) {
    Write-Host "`$ignoreAllDiskErrors is set. Exiting."
    exit 0
} 

# Check if running in a VM. If so, no need to check disks. Exit.
if (Check-VM) {
    Write-Host "Detected script is running in a VM. No need to check disks. Exiting!"
    exit 0
}

# Initialize an empty array to store disk errors
$diskErrors = @()

# Detect testing mode
if ($TestingMode) {
    Write-Host "NOTICE: RUNNING IN TESTING MODE.`n"
    $diskErrors += "Script ran in test mode."
}

# BASIC TESTS 
# These use native PowerShell commands
# These need to run entirely separate from the later SMART checks. 
# We can't do a single loop through the disks all at once, because SMART uses its own disk format - /dev/sda, sdb, etc.
Write-Host "Performing basic checks..."

$disks = Get-PhysicalDisk
foreach ($disk in $disks) {
    Write-Host "`nPerforming basic checks for disk", $disk.FriendlyName "(Physical Disk", $disk.DeviceId, ")"
    # The most basic check - does Windows report the disk status as healthy?
    if (!($disk.HealthStatus -eq "Healthy")) {
        Write-IndentedHost "WARNING! Disk is NOT healthy!"
        $diskErrors += "Disk $disk.FriendlyName health status failed!"
        $diskHealth = $false
    }

    # Check values from Get-StorageReliabilityCounter
    $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk

    # Check if any error counters are greater than 0
    $reliabilityErrors = @(
        @{Name = 'Total Read Errors'; Value = $reliability.ReadErrorsTotal},
        @{Name = 'Uncorrected Read Errors'; Value = $reliability.ReadErrorsUncorrected},
        @{Name = 'Total Write Errors'; Value = $reliability.WriteErrorsTotal},
        @{Name = 'Uncorrected Write Errors'; Value = $reliability.WriteErrorsUncorrected}
    )
    
    $hasReliabilityErrors = $false
    
    foreach ($reliabilityError in $reliabilityErrors) {        
        if ($reliabilityError.Value -gt 0) {
            $hasErrors = $true
            Write-IndentedHost "Disk $($disk.FriendlyName) has $($reliabilityError.Name): $($reliabilityError.Value)"
            $diskErrors += "Disk $($disk.FriendlyName) has $($reliabilityError.Name): $($reliabilityError.Value)"
        }
        else {
            Write-IndentedHost $reliabilityError.Name, ": none"
        }
    }
    
    if ($hasReliabilityErrors) {
        Write-IndentedHost "WARNING! $($disk.FriendlyName) HAS ERRORS!"
        $diskHealth = $false
    }
    else {
        Write-IndentedHost "Disk passed basic checks."
    }
    
}

# SMART CHECKS
# The second set of tests, using smartmontools
Write-Host "`nPerforming SMART checks..."

# Make sure smartmontools is installed and get path to smartctl.exe
$smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"
Install-Smartmontools -ProgramPath $smartctlPath

# Get a list of all disks
$smartDisks = (& "$smartctlPath" --scan -j | ConvertFrom-Json).devices

# Initialize an array of serial numbers. Helps handle issue where duplicate disks are detected by SMART.
# Sometimes the same disk will appear twice, e.g. as both /dev/sda and /dev/csmi0,1 . By checking the SN, we avoid duplicate disks. 
$diskSerials = @()

# Loop through the disks and analyze SMART data
foreach ($smartDisk in $smartDisks){
    # This is what actually gets the SMART data
    # $smartData will be a custom PowerShell object with nested properties
    $smartData = (& "C:\Program Files\smartmontools\bin\smartctl.exe" -a -j $smartDisk.name) | ConvertFrom-Json

    # Fix a bug with smartctl returning exit code 4. See here: https://github.com/prometheus-community/smartctl_exporter/issues/152
    if ($LASTEXITCODE = 4) {
        $LASTEXITCODE = 0
    }
    
    # Assign variables for basic disk info
    $name = $smartDisk.name
    $model = $smartData.model_name
    $serial = $smartData.serial_number

    # Check for serial in $diskSerials array to handle duplicate disk issue
    if ($diskSerials.Contains($serial)) {
        Write-Host "`n$name : Duplicate serial number detected, skipping."
        continue
    }
    
    # Add serial to $diskSerials array to help with duplicate check
    if ($serial) {
        $diskSerials += $serial
    }
    
    # Print header    
    Write-Host "`nChecking SMART data for $name"

    # Check if the disk is supported
    $messages = $smartData.smartctl.messages.string
    $smartSupport = $smartData.smart_support.available
    
    if ($messages -match "Unknown USB|Open Failed" -or !$smartSupport) {

        Write-IndentedHost "WARNING: Unsupported disk! This may be a USB drive or similar. Skipping SMART checks."
        if ($messages) {
            Write-IndentedHost "Message: $messages"
        }
        else {
            Write-IndentedHost "No error message was provided."
        }
    }
    else {
        # Supported disk, proceed to tests

        # Print basic info
        if ($model) {
            Write-IndentedHost "Model: $model"
        }
        else {
            Write-IndentedHost "Model: unknown"
        }
        if ($serial) {
            Write-IndentedHost "Serial number: $serial"
        }
        else {
            Write-IndentedHost "Serial: unknown"
        }
 
        # Check for SMART debug mode and if set, print full SMART data
        if ($DebugSMART) {
             Print-ObjectProperties -Object $smartData
        }
 
        # Initialize $diskHealth
        $diskHealth = "True"

        # Check basic SMART status
        $smartStatus = $smartData.smart_status.passed
        if (! $smartStatus) {
            Write-IndentedHost "WARNING! SMART STATUS FAILED!"
            $diskErrors += "SMART status failed for $name"
            $diskHealth = $false
        }
        else {
            Write-IndentedHost "SMART status: PASSED. Note: this does not always mean the disk is healthy."
        }
        
        # SMART DATA VALUE CHECKS

        # POWER CHECKS
        # These aren't as serious. They're only thresholds past which the disk is more likely to fail.
        # You can set $ignoreDiskPowerErrors in Syncro to ignore these checks 

        # Check Power Cycle Count
        $parameterName = "Power cycle count"
        if (! $smartData.power_cycle_count) {
            Write-IndentedHost "ERROR: failed to retrieve $parameterName"
        }
        else {
            $powerCycleCount = $smartData.power_cycle_count
            $diskHealth = Check-Threshold -Value $powerCycleCount -Threshold $MaxPowerCycles -ParameterName $parameterName
            if (! $diskHealth) {
                if ($ignoreDiskPowerErrors) {
                    Write-IndentedHost "A power error was detected, but `$ignoreDiskPowerErrors is set. Supressing alert."
                    $diskHealth = $true
                }
                else {
                    $diskErrors += "Disk $model has exceed the max $parameterName."
                }
            }
        }

        # Check Power On Time
        $parameterName = "Power on time"
        if (! $smartData.power_on_time.hours) {
            Write-IndentedHost "ERROR: failed to retrieve $parameterName"
        }
        else {
            $powerOnTime = $smartData.power_on_time.hours
            $diskHealth = Check-Threshold -Value $powerOnTime -Threshold $MaxPowerOnTime -ParameterName $parameterName
            if (! $diskHealth) {
                if ($ignoreDiskPowerErrors) {
                    Write-IndentedHost "A power error was detected, but `$ignoreDiskPowerErrors is set. Supressing alert."
                    $diskHealth = $true
                }
                else {
                    $diskErrors += "Disk $model has exceed the max $parameterName."
                }
            }
        }

        # Check Temperature
        $parameterName = "Temperature"
        if (! $smartData.temperature.current) {
            Write-IndentedHost "ERROR: failed to retrieve $parameterName"
        }
        else {
            $temperature = $smartData.temperature.current
            $diskHealth = Check-Threshold -Value $temperature -Threshold $MaxTemperature -ParameterName $parameterName
            if (! $diskHealth) {
                $diskErrors += "Disk $model has exceeded the max $parameterName."
            }
        }      
        
         # Check for Reallocated Sectors. This is a little different, so won't work with the Check-Threshold function
        if (! $smartData.ata_smart_attributes.table  ) {
            Write-IndentedHost "Could not retrieve ATA SMART Attributes table. This is normal for some disks, such as NVMe drives."
        }
        else {
            $reallocatedSectors = ($smartData.ata_smart_attributes.table | Where-Object { $_.name -eq "Reallocated_Sector_Ct" }| Select-Object -ExpandProperty raw).value
            if ($reallocatedSectors -gt 0) {
                Write-IndentedHost "WARNING! Disk has $reallocatedSectors reallocated sectors and is likely failing."
                $diskErrors += "Disk $model has $reallocatedSectors reallocated sectors."
            }
            elseif (! ($reallocatedSectors -eq $null )) {
                Write-IndentedHost "Reallocated sectors: $reallocatedSectors"
            }
        }

        # Check for recent self test results, and also run one if not run recently
        if (! $smartData.ata_smart_data.capabilities.self_tests_supported) {
            Write-IndentedHost "Drive is not capable of self-tests. This is normal for some disks, such as NVMe drives."
        }
        else {
            #Check if a SMART test took place within the test interval
            if ($smartData.ata_smart_self_test_log.standard.table) {
                $lastTest = $smartData.ata_smart_self_test_log.standard.table[0].lifetime_hours
                $difference = [Math]::Abs($powerOnTime - $lastTest)
    
                # Check if the difference is more than the max interval
                if ($difference -gt $MaxTestInterval) {
                    Write-IndentedHost "No SMART test has run in the past $MaxTestInterval hours. Starting short test now."
                    & "$smartctlPath" -t short $name --quietmode=errorsonly
                }
    
                else {
                    Write-IndentedHost "Disk supports self-tests and has a recent self-test logged."
                }
    
                # Check for selftests that ended in read failure
                $readFailureFound = $false
    
                foreach ($testLog in $smartData.ata_smart_self_test_log.standard.table) {
                    $status = $testLog.status.string
                    if ($status -match "failure") {
                        $readFailureFound = $true
                        break  # No need to continue once a failure is found
                    }
                }
                if ($readFailureFound) {
                    Write-IndentedHost "WARNING: found failed SMART tests!"
                    $diskErrors += "Disk $model has failed self tests"
                    $diskHealth = $false
                }    
            }

            # Handle the case where no SMART test has run yet
            else {
                Write-IndentedHost "No SMART test have ever been logged. Initiating short test."
                & "$smartctlPath" -t short $name --quietmode=errorsonly
            }

        }

        # Final ruling on disk health
        if ($diskHealth) {
            Write-IndentedHost "Disk appears to be healthy."
        }
        else {
            Write-IndentedHost "WARNING! THIS DISK HAS PROBLEMS!"
        }

    } 
}

# Final check for issues
if ($diskErrors) {
    Write-Host "`nWARNING! WARNING! FOUND DISK(S) WITH PROBLEMS!"
    Write-Host "Errors: $diskErrors"
    if ($SuppressRMMAlerts) {
        Write-Host "An RMM alert would have been generated, but `$supressRMMAlerts is set to true."
    }
    else{
        if (Get-Module | Where-Object { $_.ModuleBase -match 'Syncro' }) {
            RMM-Alert -Category "Disk Health Alert" -Body "Warning! Disk health script found problems: $diskErrors"
        }
        else {
            Write-Host "Syncro module not found, no RMM alert can be created"
        }
    }
}

if ($LogOutput -eq "true") {
    Stop-Transcript
}

#Fix bug with script exiting incorrectly
if ($LASTEXITCODE -eq 0) {
    exit 0
}

