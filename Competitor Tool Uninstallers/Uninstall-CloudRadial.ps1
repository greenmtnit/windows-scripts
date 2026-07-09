<#
    Uninstall-CloudRadial.ps1

    Silently uninstalls the CloudRadial Agent.

    Runs the CloudRadial Agent uninstaller.
    Checks for its default path (C:\Program Files (x86)\CloudRadial Agent) and also white-label path for outgoing MSP (C:\Program Files (x86)\simpleroute Support Portal)
    
    Finally, checks for the white-label desktop shortcut "simpleroute Support Portal.lnk" on all users' desktops and deletes it, if present.

#>


function Invoke-Uninstall {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$UninstallerPath
    )

    if (-not (Test-Path $UninstallerPath)) {
        Write-Host "$Name not found at '$UninstallerPath'. Skipping (not installed, or path/filename differs)."
        return $null
    }

    Write-Host "Uninstalling $Name from '$UninstallerPath'..."

    try {
        $process = Start-Process -FilePath $UninstallerPath `
            -ArgumentList "/norestart", "/verysilent" `
            -Wait `
            -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "$Name uninstalled successfully."
        }
        else {
            Write-Warning "$Name uninstaller exited with code $($process.ExitCode)."
        }

        return $process.ExitCode
    }
    catch {
        Write-Error "Failed to run uninstaller for $Name`: $_"
        return 1
    }
}

$Targets = @(
    @{ Name = "CloudRadial Agent";          Path = "C:\Program Files (x86)\CloudRadial Agent\unins000.exe" }
    @{ Name = "simpleroute Support Portal 1"; Path = "C:\Program Files (x86)\simpleroute Support Portal\unins000.exe" }
    @{ Name = "simpleroute Support Portal 2"; Path = "C:\Program Files (x86)\simpleroute Support Portal\unins001.exe" }

)

$exitCodes = foreach ($target in $Targets) {
    Invoke-Uninstall -Name $target.Name -UninstallerPath $target.Path
}

# Delete "simpleroute Support Portal.lnk" from all user Desktop folders
$fileName = "simpleroute Support Portal.lnk"
$usersRoot = "C:\Users"
Get-ChildItem -Path $usersRoot -Directory | ForEach-Object {
    $desktopPath = Join-Path $_.FullName "Desktop"
    $targetFile  = Join-Path $desktopPath $fileName
    if (Test-Path $targetFile) {
        try {
            Remove-Item -Path $targetFile -Force
            Write-Host "Deleted: $targetFile"
        } catch {
            Write-Warning "Failed to delete '$targetFile': $_"
        }
    }
}

# Exit non-zero if any uninstaller that actually ran returned a non-zero code
$failures = $exitCodes | Where-Object { $_ -ne $null -and $_ -ne 0 }
if ($failures) {
    exit 1
}
else {
    exit 0
}