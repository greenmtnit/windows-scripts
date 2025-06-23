<#
  Uninstall-Kaseya.ps1
  
  Uninstalls Kaseya RMM Agent
  
  Tested working to remove Kaseya from multiple different IT providers.
    
#>


# Check for Kaseya directory in Program Files (x86) and uninstall if present
$programFiles86Path = "C:\Program Files (x86)\Kaseya"
if (Test-Path $programFiles86Path) {
    $dir = Get-ChildItem $programFiles86Path
    foreach ($line in $dir) {
        $name = $line.Name
        Set-Location "$programFiles86Path\$name"
        if (Test-Path ".\KASetup.exe") {
            cmd /c "KASetup.exe /r /g $name /l %TEMP%\kasetup.log /s"
        }
    }
}

# Check for Kaseya directory in Program Files and uninstall if present
$programFilesPath = "C:\Program Files\Kaseya"
if (Test-Path $programFilesPath) {
    $dir = Get-ChildItem $programFilesPath
    foreach ($line in $dir) {
        $name = $line.Name
        Set-Location "$programFilesPath\$name"
		if (Test-Path ".\KASetup.exe") {
            cmd /c "KASetup.exe /r /g $name /l %TEMP%\kasetup.log /s"
		}
        cmd /c "KASetup.exe /r /g $name /l %TEMP%\kasetup.log /s"
    }
}

# Wait for Kaseya uninstall to finish
Start-Sleep -Seconds 30

# Function to check if a directory contains anything other than empty subfolders
function HasFiles($path) {
    $items = Get-ChildItem $path -Recurse -File
    return $items.Count -gt 0
}

# Check if the directories contain anything other than empty subfolders
if (HasFiles $programFiles86Path) {
    Write-Host "The directory $programFiles86Path contains files or non-empty subfolders. Kaseya may still be installed."
}

elseif (HasFiles $programFilesPath) {
    Write-Host "The directory $programFilesPath contains files or non-empty subfolders. Kaseya may still be installed."
}

else {
    Write-Host "No Kaseya files found. Kaseya has been uninstalled or was not present."
}
