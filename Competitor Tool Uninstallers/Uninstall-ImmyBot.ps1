<#
  Uninstall-ImmyBot.ps1
    
  Uninstalls ImmyBot.
  Original source:
  https://www.immy.bot/documentation/frequently-asked-questions/faq/#how-do-i-uninstall-the-immyagent
  
#>

$paths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$product = Get-ItemProperty $paths |
  Where-Object { $_.DisplayName -eq 'ImmyBot Agent' } |
  Select-Object -First 1
  
if (-not $product) {
    Write-Host "ImmyBot Agent is not installed."
    exit 1
}

$Arguments = "/x $($product.PSChildName) /quiet /noreboot"

Write-Host "Running: msiexec $Arguments"

Start-Process -FilePath msiexec -ArgumentList $Arguments -Wait -Passthru
