<#
  Disable-RDPSecurityWarning.ps1
  
  Disables the new (April 2026) RDP warning popup when using unsigned RDP files.
  
  https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/understanding-security-warnings
  
#>

$RegistryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client"
$ValueName    = "RedirectionWarningDialogVersion"
$ValueData    = 1
$ValueType    = "DWord"

# Create the key if it doesn't exist
if (-not (Test-Path -Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
    Write-Host "Created key: $RegistryPath"
}

# Create or update the DWORD value
Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $ValueData -Type $ValueType
Write-Host "Set value $RegistryPath > $ValueName to $ValueData"