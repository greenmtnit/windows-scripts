# Functions
<#
	.SYNOPSIS
		Install-Smartmontools checks if smartctl.exe is present at C:\Program Files\smartmontools\bin\smartctl.exe
		If not, it installs smartmontools using chocolatey
		It returns nothing
#>
function Install-Smartmontools {
	$smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"
	if (!(Test-Path $smartctlPath)) {
		#We need to install smartctl, it wasn't found
		Write-Host "smartctl not found, installing it"
		# Here we incorporate the chocolatey script from here: https://greenmtnit.syncromsp.com/scripts/611809/edit

		$syncroPath = "$env:ProgramFiles\RepairTech\Syncro\kabuto_app_manager\choco.exe"
		$chocoPath = "$env:ProgramData\chocolatey\choco.exe"
		$packageName = "smartmontools"

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
			
			# Use the "upgrade" command, which will either  install or upgrade the package
			& "$choco" upgrade $packageName -y
		}
		catch {
			Write-Host "Error: $_"
		}
	}
}
<#
	.SYNOPSIS
		Invoke-Smartmontools checks every compatible disk on the computer and runs checks 
		It returns "Healthy" if all tests passed; otherwise, it returns details of the error
#>
function Invoke-Smartmontools {
	# This code was adapted from https://www.cyberdrain.com/monitoring-with-powershell-monitoring-smart-status-using-smartctl/
	# Credit to Kevin Tegelaar from CyberDrain
	# This code is covered under AGPL3.0

	############ Thresholds #############
	$PowerOnTime = 35063 #about 4 years constant runtime.
	$PowerCycles = 4000 #4000 times of turning drive on and off
	$Temperature = 60 #60 degrees celcius
	############ End Thresholds #########

	# Find all connected HDDs
	$HDDs = (& "C:\Program Files\smartmontools\bin\smartctl.exe" --scan -j | ConvertFrom-Json).devices
	$HDDInfo = foreach ($HDD in $HDDs) {
		(& "C:\Program Files\smartmontools\bin\smartctl.exe" -t short -a -j $HDD.name) | convertfrom-json
	}
	$DiskHealth = @{}
	# Checking SMART status
	$SmartFailed = $HDDInfo | Where-Object { $_.Smart_Status.Passed -ne $true }
	if ($SmartFailed) { $DiskHealth.add('SmartErrors',"Smart Failed for disks: $($SmartFailed.serial_number)") }
	# Checking Temp Status
	$TempFailed = $HDDInfo | Where-Object { $_.temperature.current -ge $Temperature }
	if ($TempFailed) { $DiskHealth.add('TempErrors',"Temperature failed for disks: $($TempFailed.serial_number)") }
	# Checking Power Cycle Count status
	$PCCFailed = $HDDInfo | Where-Object { $_.Power_Cycle_Count -ge $PowerCycles }
	if ($PCCFailed ) { $DiskHealth.add('PCCErrors',"Power Cycle Count Failed for disks: $($PCCFailed.serial_number)") }
	# Checking Power on Time Status
	$POTFailed = $HDDInfo | Where-Object { $_.Power_on_time.hours -ge $PowerOnTime }
	if ($POTFailed) { $DiskHealth.add('POTErrors',"Power on Time for disks failed : $($POTFailed.serial_number)") }

	if (!$DiskHealth) { $DiskHealth = "Healthy" }

	return $DiskHealth
}

# Start with two easy checks using built-in functions: Get-PhysicalDisk Health and Get-StorageReliabilityCounter
$disks = Get-PhysicalDisk

foreach ($disk in $disks) {
	$readErrors = Get-PhysicalDisk | Get-StorageReliabilityCounter
	if (!($disk.HealthStatus -eq "Healthy")) {
		Write-Host "Problem! Disk not healthy!"
		# RMM-Alert "Problem! Disk not healthy!"
		exit 1 # Can exit the script here. If there's a problem, that's all you need to know.
	}
	elseif ($readErrors.ReadErrorsUncorrected -gt "0") {
		Write-Host "Problem! Read errors!"
		# RMM-Alert "Problem - read errors!"
		exit 1 # Can exit the script here. If there's a problem, that's all you need to know.	 
	}
	else {
		Write-Host "Basic checks passed, moving onto complex checks!"
	}
}

# Easy checks didn't find anything
# Run deeper checks on every disk

# Install Smartmontools, if not already installed
Install-Smartmontools

# Run a SMART test with smartmontools
$smartmonDiskHealth = Invoke-Smartmontools
if (!($smartmonDiskHealth -eq "Healthy")) {
	# The drive is unhealthy
	Write-Host "Problem - smartmontools health test found problems on drive $diskName !"
	Write-Host "Details: $smartmonDiskHealth"
	# RMM-Alert "Problem - smartmontools health test found problems on drive $diskName !"
	exit 1
}

<#
	Additional notes/ todo/ problems:


#>