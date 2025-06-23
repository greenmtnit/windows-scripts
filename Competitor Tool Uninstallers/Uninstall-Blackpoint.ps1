<#
  Uninstall-Blackpoint.ps1
  
  Uninstalls Blackpoint MDR https://blackpointcyber.com/
  The installed app may show as "SnapAgent" and/or "ZTAC"
  
#>


try {
    # Specify the application names
    $ztacApplicationName = "ZTAC"
    $snapAgentApplicationName = "SnapAgent"

    # Function to uninstall an application by name
    function Uninstall-Application($appName) {
        $identifyingNumber = (Get-WmiObject Win32_Product | Where-Object {$_.Name -eq $appName}).IdentifyingNumber
        if (-not [string]::IsNullOrEmpty($identifyingNumber)) {
            Start-Process -FilePath "MsiExec.exe" -ArgumentList "/X $identifyingNumber /quiet /qn /norestart" -Wait -ErrorAction SilentlyContinue
        } else {
            # Write-Host "$appName IdentifyingNumber not found or is empty. Please check the application installation."
        }
    }

# snapw and snap services
# Check if the snapw process exists
if (Get-Process -Name "snapw" -ErrorAction SilentlyContinue) {
    # If it exists, stop the process
    Stop-Process -Name "snapw" -Force -ErrorAction SilentlyContinue
    # Write-Host "Stopped process: snapw"
} else {
    # Write-Host "Process 'snapw' not found."
}

# Check if the snap service exists
if (Get-Process -Name "snap" -ErrorAction SilentlyContinue) {
    # If it exists, stop the process
    Stop-Service -Name "snap" -ErrorAction SilentlyContinue
    # Write-Host "Stopped service: snap"
} else {
    # Write-Host "Service 'snap' not found."
}

# Wait for 5 seconds
Start-Sleep -Seconds 5

# Uninstall SnapAgent
Uninstall-Application -appName $snapAgentApplicationName -ErrorAction SilentlyContinue

# Wait for 5 seconds
Start-Sleep -Seconds 5

# ztac service
# Check if the ztac service exists
if (Get-Process -Name "ztac" -ErrorAction SilentlyContinue) {
    # If it exists, stop the process
    Stop-Service -Name "ztac" -ErrorAction SilentlyContinue
    # Write-Host "Stopped service: ztac"
} else {
    # Write-Host "Service 'ztac' not found."
}
# Wait for 5 seconds
Start-Sleep -Seconds 5

# Uninstall ZTAC
Uninstall-Application -appName $ztacApplicationName -ErrorAction SilentlyContinue

# Wait for 5 seconds
Start-Sleep -Seconds 5

# Remove entire "C:\Program Files (x86)\Blackpoint\" directory
Remove-Item -Path "C:\Program Files (x86)\Blackpoint\" -Force -Recurse -ErrorAction SilentlyContinue

# Define an array of registry keys to delete
$registryKeys = @(
    "HKLM:\SOFTWARE\Classes\Installer\Features\0E1D3F0C2B974FA4AA0418F12B055384",
    "HKLM:\SOFTWARE\Classes\Installer\Products\0E1D3F0C2B974FA4AA0418F12B055384",
    "HKLM:\SOFTWARE\Classes\Installer\Products\0E1D3F0C2B974FA4AA0418F12B055384\SourceList",
    "HKLM:\SOFTWARE\Classes\Installer\Products\0E1D3F0C2B974FA4AA0418F12B055384\SourceList\Media",
    "HKLM:\SOFTWARE\Classes\Installer\Products\0E1D3F0C2B974FA4AA0418F12B055384\SourceList\Net",
    "HKLM:\SOFTWARE\Classes\Installer\UpgradeCodes\7CF0653F8B24F2647B3A70510A96BEE6",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes\7CF0653F8B24F2647B3A70510A96BEE6",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\08C8C87010175A141912F6695F06EB95",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\5E3D36BBC4ADCA749AC6CC3774478B04",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\74A044CACC826754BB48542EA5681E4C",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\A3129D8FE202CCF47B233E82C70367D2",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\A73F059633BC8314597EE7F81A662796",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\C0016A60CBED93E41900FCBD4BC10AB4",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\DB4ABEA1DA4832048BCCF78860ADA944",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\F1AB931B4E8A02A4F8E5F828409E4DD1",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\F81ECEA5C9A7CA3409D05D38A602B11C",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\0E1D3F0C2B974FA4AA0418F12B055384",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\0E1D3F0C2B974FA4AA0418F12B055384\Features",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\0E1D3F0C2B974FA4AA0418F12B055384\InstallProperties",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\0E1D3F0C2B974FA4AA0418F12B055384\Patches",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\0E1D3F0C2B974FA4AA0418F12B055384\Usage",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C0F3D1E0-79B2-4AF4-AA40-811FB2503548}",
    "HKLM:\SYSTEM\CurrentControlSet\Services\ZTAC",
    "HKLM:\SYSTEM\CurrentControlSet\Services\ZtacFltr"
)

# Loop through each registry key and delete it
foreach ($key in $registryKeys) {
    try {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            # Write-Host "Deleted registry key: $key"
        } else {
            # Write-Host "Registry key not found: $key"
        }
    } catch {
        # Write-Host "Error deleting registry key: $key"
        # Write-Host "Error message: $_"
    }
}

# Remove the services
Remove-Service -Name "ZTAC"
Remove-Service -Name "ZtacFltr"

$ZTACProgramData = "C:\ProgramData\Blackpoint\ZTAC"

# Check if the folder exists
if (Test-Path -Path $ZTACProgramData) {
    # Delete the folder and all its contents recursively
    Remove-Item -Path $ZTACProgramData -Recurse -Force -ErrorAction SilentlyContinue
    # Write-Output "Folder '$ZTACProgramData' deleted successfully."
} else {
    # Write-Output "Folder '$ZTACProgramData' not found."
}
} catch {
    # Silently handle the error without displaying any message
}
