<#
  Uninstall-Connectwise.ps1
  
  Uninstalls Connectwise Automate Agent, a.k.a. Labtech
  
  All credit to original source: https://gist.github.com/ak9999/e68da02d7957bd7db2a2a647f76d50be#file-uninstalllabtechagent-ps1
  
#>

$url = "https://s3.amazonaws.com/assets-cp/assets/Agent_Uninstaller.zip"
$destination = "C:\Windows\Temp\Agent_Uninstaller.zip"
$extractDir = "C:\Windows\Temp\LTAgentUninstaller"

# Clean up if file already exists
if (Test-Path $destination) {
  Remove-Item $destination -Force
}

if (Test-Path $extractDir) {
  Remove-Item $extractDir -Force -Recurse
}

(New-Object System.Net.WebClient).DownloadFile($url, $destination)
# The below usage of Expand-Archive is only possible with PowerShell 5.0+
# Expand-Archive -LiteralPath C:\Windows\Temp\Agent_Uninstaller.zip -DestinationPath C:\Windows\Temp\LTAgentUninstaller -Force
# Use .NET instead
[System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
# Now we can expand the archive
[System.IO.Compression.ZipFile]::ExtractToDirectory($destination, $extractDir)
Start-Process -FilePath "$extractDir\Agent_Uninstall.exe"