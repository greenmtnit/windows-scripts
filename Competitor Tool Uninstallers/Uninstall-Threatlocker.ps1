<#
  Uninstall-Threatlocker.ps1
    
  Uninstalls Threatlocker.
  
  Tamper Protection must be disabled first.
  
  Original source: https://static.threatlocker.com/kb-articles/deployment/uninstall/ThreatLockerUninstall.ps1
  
  More Info: 
      Hudu: Uninstalling Threatlocker | https://hudu.greenmtnit.com/shared_article/2X69uEH2DYx2kPYC7C8LKphM
  
#>

if (!(Test-Path "C:\Temp")) {
    mkdir "C:\Temp";
}
if ([Environment]::Is64BitOperatingSystem) {
    $downloadURL = "https://api.threatlocker.com/installers/threatlockerstubx64.exe";
}
else {
    $downloadURL = "https://api.threatlocker.com/installers/threatlockerstubx86.exe";
}
$localInstaller = "C:\Temp\ThreatLockerStub.exe";
Invoke-WebRequest -Uri $downloadURL -OutFile $localInstaller;
& C:\Temp\ThreatLockerStub.exe uninstall