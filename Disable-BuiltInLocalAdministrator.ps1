<#
    Disable-BuiltInLocalAdministrator.ps1

    This script identifies and disables the built-in local Administrator account on a Windows system.
    The built-in Administrator account is uniquely identified by a Security Identifier (SID) that ends in "-500".

    NOTE: Script will not execute on servers.
#>

# Server check
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
If ($osInfo.ProductType -ne 1) {
  Write-Host "This is a server. Script will not execute on Server OS. Exiting!"
  exit 1
}

# Get all local users
$localUsers = Get-LocalUser

foreach ($user in $localUsers) {
    try {
        # Get the SID of the user
        $sid = (New-Object System.Security.Principal.NTAccount($user.Name)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Check if the SID ends in -500 (built-in Administrator)
        if ($sid.EndsWith("-500")) {
            if ($user.Enabled -eq $false) {
                Write-Output "Built-in Administrator account '$($user.Name)' is already disabled."
            } else {
                Write-Output "Found built-in Administrator account: '$($user.Name)'. Disabling it..."
                Disable-LocalUser -Name $user.Name -ErrorAction Stop
                Write-Output "Account '$($user.Name)' has been disabled."
            }
        }
    } catch {
        Write-Output "Error processing user '$($user.Name)': $_"
    }
}
