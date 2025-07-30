<#
  Set-SplashtopAutoMute.ps1
  
  Sets Splashtop Streamer sound settings to "Outpout sound on this computer only"
    
#>

$AutoMuteValue = 2

if (Test-Path -Path "HKLM:\SOFTWARE\WOW6432Node\Splashtop Inc.\Splashtop Remote Server") {
    New-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Splashtop Inc.\Splashtop Remote Server" `
        -Name AutoMute -PropertyType DWord -Value $AutoMuteValue -Force
} else {
    New-ItemProperty -Path "HKLM:\SOFTWARE\Splashtop Inc.\Splashtop Remote Server" `
        -Name AutoMute -PropertyType DWord -Value $AutoMuteValue -Force
}
Restart-Service -Name SplashtopRemoteService
