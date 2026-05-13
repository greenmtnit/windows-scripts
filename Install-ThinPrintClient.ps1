<#
    Install-ThinPrintClient.ps1
    Download and Install ThinPrint Client Windows 13.1.7 x64
    The script may be updated when a new version of Thinprint is released.
    
    If Thinprint is already installed, it will be upgraded.
    
    Sources: 
    https://download.thinprint.com/wp-content/uploads/TPCLWin13x64MSI.zip
    https://support.thinprint.com/en/support/solutions/articles/43000707717-unattended-installation#Unpacking-the-.msi-file
#>
 
$newVersion = "13.1.7"
$DownloadUrl = "https://download.thinprint.com/wp-content/uploads/TPCLWin13x64MSI.zip"
$ZipFile     = "$env:TEMP\TPCLWin13x64MSI.zip"
$ExtractPath = "$env:TEMP\TPCLWin13x64MSI"
$MsiPath     = "$ExtractPath\ThinPrint\ThinPrint Client Windows 13.1.7 x64 MSI\ThinPrintClientWindows.msi"

Write-Host "Listing installed Thinprint versions"
$installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq "ThinPrint Client Windows" }
if ($installed) {
    $installed | Select-Object DisplayName, DisplayVersion | Format-Table -AutoSize
    if ($installed.DisplayVersion -ge $newVersion) {
        Write-Host "Thinprint is already at the latest version. No update needed! Exiting."
        Exit 0
    }
}
else {
    Write-Host "No exisitng Thinprint install detected. Thinprint will be installed."
}

# Download
Write-Host "Downloading ThinPrint..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing

# Extract
Write-Host "Extracting ZIP..."
Expand-Archive -Path $ZipFile -DestinationPath $ExtractPath -Force

# Install
Write-Host "Installing: $($MsiPath.Name)"
$Process = Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn" -Wait -PassThru


if ($Process.ExitCode -eq 0) {
} else {
    Write-Host "Installation completed successfully."
    Write-Warning "Installer exited with code: $($Process.ExitCode)"
}

Write-Host "Confirm upgrade - listing installed Thinprint versions"
$installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*thinprint*" }
if ($installed) {
    $installed | Select-Object DisplayName, DisplayVersion | Format-Table -AutoSize
}
else {
    Write-Host "No exisitng Thinprint install detected."
}