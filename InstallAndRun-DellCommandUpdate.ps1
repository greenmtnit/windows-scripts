<#
.NOTE
YOU MAY NEED TO RUN THIS SCRIPT TWICE FOR IT TO WORK
(and run it one more time after first reboot, so three times total)
#>
#
#Check for chocolatey and install if missing
$syncroPath = "$env:ProgramFiles\RepairTech\Syncro\kabuto_app_manager\choco.exe"
$chocoPath = "$env:ProgramData\chocolatey\choco.exe"
 
if (Test-Path -Path $syncroPath) {
  Write-Host "Found chocolatey from Syncro, using it"
  $choco = $syncroPath
}
elseif (Test-Path -Path $chocoPath) {
  Write-Host "Found chocolatey in its default location, using it"
  $choco = $chocoPath
}
else {
  Write-Host "Chocolatey not found, installing it"
  Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  $choco = $chocoPath
}
 
#Install Dell CommandUpdate
Start-Process "$choco" -ArgumentList "install DellCommandUpdate -y" -Wait
 
#Run DCU
$dcu = "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
 
& "$dcu" /scan -outputLog=C:\temp\dell\logs\scan.log
& "$dcu" /applyUpdates -reboot=disable -outputLog=C:\temp\dell\logs\applyUpdates.log
