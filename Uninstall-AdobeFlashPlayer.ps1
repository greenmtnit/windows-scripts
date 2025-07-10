<#
  Uninstall-AdobeFlashPlayer.ps1
    
  Uninstalls Adobe Flash Player using Adobe's uninstaller.
  https://helpx.adobe.com/flash-player/kb/uninstall-flash-player-windows.html
  Archive link: http://web.archive.org/web/20250624110751if_/https://fpdownload.macromedia.com/get/flashplayer/current/support/uninstall_flash_player.exe
      
#>

$Url = "https://fpdownload.macromedia.com/get/flashplayer/current/support/uninstall_flash_player.exe"
$Uninstaller = "$env:TEMP\uninstall_flash_player.exe"

Write-Host "Downloading Adobe Flash Player uninstaller..."
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest -Uri $Url -OutFile $Uninstaller -UseBasicParsing

if (-not (Test-Path $Uninstaller)) {
    Write-Host "Download failed. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Running Flash Player uninstaller..."
Start-Process -FilePath $Uninstaller -ArgumentList "-uninstall" -Wait -NoNewWindow

Write-Host "Adobe Flash Player removal complete."