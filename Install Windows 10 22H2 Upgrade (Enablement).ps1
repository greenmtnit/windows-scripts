#SOURCE
#https://community.syncromsp.com/t/windows-patching-questions/8377/12

# Set up constants for better readability throughout the scripts
$CABfile = 'windows10.0-kb5015684-x64_d2721bd1ef215f013063c416233e2343b93ab8c1.cab'
$CABfileURL = "https://catalog.s.download.windowsupdate.com/c/upgr/2022/07/$($CABfile)"
$TargetFolder = $Env:Temp
$TargetFile = $TargetFolder + '\\' + $CABfile
$OSKernelFile = Get-Item "$env:SystemRoot\System32\ntoskrnl.exe"

# Check host is running Windows 10
$OS = (Get-WmiObject Win32_OperatingSystem).Name
if (! $OS.Contains("Windows 10")) {
  Write-Host "This host is not running Windows 10, exiting"
  exit
}

# Do checks to make sure target system is both eligible for and needs the upgrade
# Are we at 22H2 already? If so, bail from script.
If ((Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion').DisplayVersion -eq '22H2') {
    Write-Output 'Host is already running version 22H2; no Feature Update required - exiting.'
    exit
}

# If not at 22H2, are we running an eligible Windows 10 kernel version?
If ((($OSKernelFile).VersionInfo.FileVersionRaw).Build -ge 19041 -and (($OSKernelFile).VersionInfo.FileVersionRaw).Revision -ge 1237) { 
    Write-Output 'Host OS build is adequate for enablement package - proceeding with upgrade.'
} Else {
    Write-Output 'Host OS build is too old to be updated with this enablement package -- exiting.'
    exit
}

#Sleep for a random amount of time, up to three minutes, to avoid all clients hammering the download all at once:
$RandomSleep = Get-Random -Maximum 200
Write-Host "Sleeping for $RandomSleep seconds"
Start-Sleep -Seconds $RandomSleep

# Download the CAB file for install
Invoke-WebRequest -Uri $CABfileURL -OutFile $TargetFile

# Invoke DISM to install the Enablement Package
DISM /Online /Add-Package /PackagePath:$TargetFile /Quiet /NoRestart
$DismResult = $LASTEXITCODE

if ($DismResult -eq "3010") {
  Write-Host "DISM completed successfully, but a reboot is required to finish installing the upgrade."
  exit
}
elseif ($DismResult -eq "0") {
  Write-Host "DISM completed successfully"
  exit
}
else {
  Write-Host "DISM finished with errors. Exit code: $DismResult"
}
