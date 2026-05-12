<# 
    Get-SecureBoot2023Status.ps1
    
    Wrapper script to download and run this script:
    https://github.com/SunshineSam/Scripts/blob/main/NinjaRMM/Windows/SecureBoot%20Management/SecureBoot-Management-CA2023.ps1
    
    Script was originally meant for NinjaOne (NinjaRMM).
    This wrapper script makes it work in SyncroRMM.
    
    The Secure Boot status will be written to an asset custom field named SecureBoot2023Status.
    
    Syncro Script Variables
        $Verbose
        Name: Verbose
        Type: Dropdown
        Values: "true", "false"
        Default: "false"
        Description: Set to "true" to print the full output of the source script. Set to "false" to suppress.
#>

Import-Module $env:SyncroModule

# Vars
$scriptUrl = "https://raw.githubusercontent.com/SunshineSam/Scripts/main/NinjaRMM/Windows/SecureBoot%20Management/SecureBoot-Management-CA2023.ps1"
$localPath = "$env:TEMP\SecureBoot-Management-CA2023.ps1"
$textFile = "C:\Logs\SecureBoot\SecureBootStatus.txt" # Source script always writes to this path
$expectedScriptHash = "ECD4E0347D8AD7B10115EB6BE32F643BEDFD09425DC61F8035369E4E2C011E49"

# Download source script as UTF-8 explicitly to avoid encoding issues.
$scriptContent = Invoke-RestMethod -Uri $scriptUrl
[System.IO.File]::WriteAllText($localPath, $scriptContent, [System.Text.Encoding]::UTF8)

# Verify Script Hash
$fileHash = (Get-FileHash -Path $localPath -Algorithm SHA256).Hash
if ($fileHash -ne $expectedScriptHash) {
    throw "Hash mismatch! Script may have changed or been tampered with."
    exit 1
}

# Execute script
if ($verbose -eq "true") {
    & $localPath -SaveStatusLocal
}
else {
    & $localPath -SaveStatusLocal *>&1 | Out-Null # Supress script output
}
    

# Read status from output file
$SecureBoot2023Status = Get-Content $textFile

# Print output
Write-Host "STATUS SUMMARY: $SecureBoot2023Status"

# Set asset custom field
Set-Asset-Field -Name "SecureBoot2023Status" -Value $SecureBoot2023Status

