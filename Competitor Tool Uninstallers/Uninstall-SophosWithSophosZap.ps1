<#
  Uninstall-SophosWithSophosZap.ps1
    
  Uninstalls Sophos Antivirus using the SophosZap tool.
  
  Tamper Protection must be disabled first for any Sophos uninstall to succeed.
  
  Expect to run this script multiple times with reboots between each to finish the install.
  Use the normal Sophos uninstaller instead if possible. See UninstallSophosNormal.bat
  Logging: check C:\Windows\Temp\SophosZap log.txt or C:\Users\[user]\AppData\Local\Temp\Sophos\SophosZap log.txt
  

  More info:
      Hudu: How to Uninstall Sophos Antivirus | https://hudu.greenmtnit.com/shared_article/fMoZjmBx6EQiWxsuL3qWHYgv
      SophosZap: Frequently asked questions | https://support.sophos.com/support/s/article/KBA-000006929?language=en_US
    
#>

$SophosZap = "C:\Windows\Temp\SophosZap.exe"

Invoke-WebRequest -Uri "https://download.sophos.com/tools/SophosZap.exe" -OutFile $SophosZap -UseBasicParsing

& $SophosZap "--confirm"