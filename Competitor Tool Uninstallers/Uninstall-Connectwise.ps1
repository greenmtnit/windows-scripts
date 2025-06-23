<#
  Uninstall-Connectwise.ps1
  
  Uninstalls Connectwise Automate Agent, a.k.a. Labtech
  
  All credit to original source: https://gist.github.com/ak9999/e68da02d7957bd7db2a2a647f76d50be#file-uninstalllabtechagent-ps1
  
#>

$url = "https://s3.amazonaws.com/assets-cp/assets/Agent_Uninstaller.zip"
$output = "C:\Windows\Temp\Agent_Uninstaller.zip"
(New-Object System.Net.WebClient).DownloadFile($url, $output)
# The below usage of Expand-Archive is only possible with PowerShell 5.0+
# Expand-Archive -LiteralPath C:\Windows\Temp\Agent_Uninstaller.zip -DestinationPath C:\Windows\Temp\LTAgentUninstaller -Force
# Use .NET instead
[System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
# Now we can expand the archive
[System.IO.Compression.ZipFile]::ExtractToDirectory('C:\Windows\Temp\Agent_Uninstaller.zip', 'C:\Windows\Temp\LTAgentUninstaller')
Start-Process -FilePath "C:\Windows\Temp\LTAgentUninstaller\Agent_Uninstall.exe"