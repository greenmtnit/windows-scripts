#TESTING
#Import-Module $env:SyncroModule

$suppressRMMAlerts = $true

# Function to print a custom PowerShell object with nested properties in a readable format
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
    $smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"
    if (Test-Path $smartctlPath) {
        Write-Host "Found smartctl at $smartctlPath, using it"
    }
    else {
        # We need to install smartctl, it wasn't found
        Write-Host "smartctl not found, installing it"

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
    return $smartctlPath
}

# Initialize an empty array to store disk errors
$diskErrors = @()

# BASIC TESTS - using native PowerShell commands
# These need to run entirely separate from the later SMART checks. 
# Probably can't do a single loop through the disks all at once, because SMART uses its own disk format - /dev/sda, sdb, etc.
Write-Host "Performing basic checks..."

$disks = Get-PhysicalDisk
foreach ($disk in $disks) {
    Write-Host "`nPerforming basic checks for disk", $disk.FriendlyName "(Physical Disk", $disk.DeviceId, ")"
    if (!($disk.HealthStatus -eq "Healthy")) {
        Write-IndentedHost "WARNING! Disk is NOT healthy!"
        $diskErrors += "Disk $disk.FriendlyName health status failed!"
        $diskHealth = $false
    }

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

    if (! $diskHealth) {
        $Issues = $true
    }
    
}

# SMART CHECKS

# Define thresholds for SMART values
$maxPowerCycles = 4000 # 4000 times of turning drive on and off
#$maxPowerOnTime = 35063 # about 4 years constant runtime.
#TESTING
$maxPowerOnTime = 100
#TESTING
$maxTemperature = 50
#$maxTemperature = 70 # 70 degrees Celsius
$maxTestInterval = 168 # Max hours between SMART tests. Default = 168 hours (1 week)

Write-Host "`nPerforming SMART checks..."

#Make sure smartmontools is installed and get path to smartctl.exe
$smartctlPath = Install-Smartmontools

#Get a list of all disks
$HDDs = (& "$smartctlPath" --scan -j | ConvertFrom-Json).devices

foreach ($HDD in $HDDs){
    # This is what actually gets the SMART data
    # $HDDInfo will be a custom PowerShell object with nested properties
    $HDDInfo = (& "C:\Program Files\smartmontools\bin\smartctl.exe" -a -j $HDD.name) | ConvertFrom-Json

    # Fix a bug with smartctl returning exit code 4. See here: https://github.com/prometheus-community/smartctl_exporter/issues/152
    if ($LASTEXITCODE = 4) {
        $LASTEXITCODE = 0
    }
    
    # Print basic disk info
    $name = $HDD.name
    $model = $HDDInfo.model_name
    $serial = $HDDInfo.serial_number
    
    # Print header    
    Write-Host "`nChecking SMART data for $name"

    # Check if the disk is supported
    $messages = $HDDInfo.smartctl.messages.string
    $smartSupport = $HDDInfo.smart_support.available
    
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
 
        # UNCOMMENT FOR TESTING - Print HDDInfo
        #Print-ObjectProperties -Object $HDDInfo
 
        $diskHealth = "True"

        # Check basic SMART status
        $smartStatus = $HDDInfo.smart_status.passed
        if (! $smartStatus) {
            Write-IndentedHost "WARNING! SMART STATUS FAILED. Back up data and replace ASAP!"
            $diskErrors += "SMART status failed for $name"
            $diskHealth = $false
        }
        else {
            Write-IndentedHost "SMART status: PASSED. Note: this does not always mean the disk is healthy."
        }
        
        # SMART DATA CHECKS

        # Check Power Cycle Count
        $parameterName = "Power cycle count"
        if (! $HDDInfo.power_cycle_count) {
            Write-IndentedHost "ERROR: failed to retrieve $parameterName"
        }
        else {
            $powerCycleCount = $HDDInfo.power_cycle_count
            $diskHealth = Check-Threshold -Value $powerCycleCount -Threshold $maxPowerCycles -ParameterName $parameterName
            if (! $diskHealth) {
                $diskErrors += "Disk $name has exceed the max $parameterName."
            }    
        }

        # Check Power On Time
        $parameterName = "Power on time"
        if (! $HDDInfo.power_on_time.hours) {
            Write-IndentedHost "ERROR: failed to retrieve $parameterName"
        }
        else {
            $powerOnTime = $HDDInfo.power_on_time.hours
            $diskHealth = Check-Threshold -Value $powerOnTime -Threshold $maxPowerOnTime -ParameterName $parameterName
            if (! $diskHealth) {
                $diskErrors += "Disk $name has exceed the max $parameterName."
            }
        }

        # Check Temperature
        $parameterName = "Temperature"
        if (! $HDDInfo.temperature.current) {
            Write-IndentedHost "ERROR: failed to retrive $parameterName"
        }
        else {
            $temperature = $HDDInfo.temperature.current
            $diskHealth = Check-Threshold -Value $temperature -Threshold $maxTemperature -ParameterName $parameterName
            if (! $diskHealth) {
                $diskErrors += "Disk $name has exceed the max $parameterName."
            }
        }      
        
         # Check for Reallocated Sectors. This is a little different, so won't work with the Check-Threshold function
        if (! $HDDInfo.ata_smart_attributes.table  ) {
            Write-IndentedHost "Could not retrieve ATA SMART Attributes table. This is normal for some disks, such as NVMe drives."
        }
        else {
            $reallocatedSectors = ($HDDInfo.ata_smart_attributes.table | Where-Object { $_.name -eq "Reallocated_Sector_Ct" }| Select-Object -ExpandProperty raw).value
            if ($reallocatedSectors -gt 0) {
                Write-IndentedHost "WARNING! Disk has $reallocatedSectors reallocated sectors and is likely failing."
                $diskErrors += "Disk $name has $reallocatedSectors reallocated sectors."
            }
            elseif (! ($reallocatedSectors -eq $null )) {
                Write-IndentedHost "Reallocated sectors: $reallocatedSectors"
            }
        }

        # Check for recent self test results, and also run one if not run recently
        if (! $HDDInfo.ata_smart_data.capabilities.self_tests_supported) {
            Write-IndentedHost "Drive is not capable of self-tests. This is normal for some disks, such as NVMe drives."
        }
        else {
            #Check if a SMART test that took place within the test interval
            $lastTest = $HDDInfo.ata_smart_self_test_log.standard.table[0].lifetime_hours
            $difference = [Math]::Abs($powerOnTime - $lastTest)

            # Check if the difference is more than the max interval
            if ($difference -gt $maxTestInterval) {
                Write-IndentedHost "No SMART test has run in the past $maxTestInterval hours. Starting short test now."
                & "$smartctlPath" -t short $name --quietmode=errorsonly
            }

            else {
                Write-IndentedHost "Disk supports self-tests and has a recent self-test logged."
            }

            # Check for selftests that ended in read failure
            $readFailureFound = $false

            foreach ($testLog in $HDDInfo.ata_smart_self_test_log.standard.table) {
                $status = $testLog.status.string
                if ($status -match "failure") {
                    $readFailureFound = $true
                    break  # No need to continue once a failure is found
                }
            }
            if ($readFailureFound) {
                Write-IndentedHost "WARNING: found failed SMART tests!"
                $diskErrors += "Disk $name has failed self tests."
                $diskHealth = $false
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
    if ($suppressRMMAlerts) {
        Write-Host "An RMM alert would have been generated, but `$supressRMMAlerts is set to true."
    }
    else{
        RMM-Alert -Category "Disk Health Alert" -Body "Warning! Disk health script found problems: $diskErrors."
    }
}

#Fix bug with script exiting incorrectly
if ($LASTEXITCODE -eq 0) {
    exit 0
}