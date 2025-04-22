<# Sets User Account Control to its default settings.
 - User Account Control is on
 - Dimming is on (shows UAC prompt on a separate, secure desktop)
 - Admin users setting is Level 3: Notify me only when apps try to make changes to my computer (default)
 - Standard user setting is Level 4: Default - Always notify me when Apps try to install software or make changes to my computer; I make changes to Windows settings
#>

# Check if server and exit if yes
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
If ($osInfo.ProductType -ne 1) {
  Write-Host "This is a server. Not running on servers. Exiting."
  exit 0
}


# Define the registry path
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Set the desired values
Set-ItemProperty -Path $RegPath -Name "EnableLUA" -Value 1 -Type DWord
Set-ItemProperty -Path $RegPath -Name "PromptOnSecureDesktop" -Value 1 -Type DWord
Set-ItemProperty -Path $RegPath -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord
Set-ItemProperty -Path $RegPath -Name "ConsentPromptBehaviorUser" -Value 3 -Type DWord


Write-Output "UAC settings updated successfully."