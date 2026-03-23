<#
    Remove-LocalAdmins.ps1

    Script to remove users from the local Administrators group.

    - Gets local Administrators group members.
    - Removes each from the local Administrators group
    - For currently logged in users, the change may not take effect until the next reboot or user logoff
    
    Notes:
        - This script will not execute on servers.
        - Exceptions: The script will NOT demote the built-in Administrator account, the Domain Admins group, or the Enterprise Admins group.
    
    SyncroRMM Script Variables
        $DryRun - Dropdown - Choices "true" or "false" (default). 
            Choose whether to do a dry run.
        $CustomerRemoveLocalAdmins - Platform - {{customer_custom_field_remove_local_admins}}. Customer custom field, checkbox type. 
            If set (checked), the script will remove local admins for all the customer's assets.
            If not set (unchecked), the script will not execute on the customer's assets.
        $AssetPreserveLocalAdmins - Platform - {{aseset_custom_field_preserve_local_admins}}. Asset custom field, checkbox type. 
            If set (checked), local administrators will not be removed on the asset, regardless of if $CustomerRemoveLocalAdmins is set.
            This can be used to override $CustomerRemoveLocalAdmins for specific assets.

#>

# ── Functions ─────────────────────────────────────────────────────────────

function ConvertTo-Boolean {
    <# 
        Function to convert SyncroRMM's string values (e.g. "true" or "false") to Boolean.
    #>
    param (
        [string]$value
    )
    switch ($value.ToLower()) {
        'true' { return $true }
        '1' { return $true }
        't' { return $true }
        'y' { return $true }
        'yes' { return $true }
        'false' { return $false }
        '0' { return $false }
        'f' { return $false }
        'n' { return $false }
        'no' { return $false }
        default { throw "Invalid boolean string: $value" }
    }
}

function Get-LocalAdminsNet {
    <#
        Function to parse net localgroup administrators command to get local admins.
        Get-LocalGroupMember is unreliable. See https://github.com/PowerShell/PowerShell/issues/2996
    #>

    [CmdletBinding()]
    param()

    $raw = net localgroup administrators 2>$null

    $members = $raw |
        Where-Object {
            $_ -and
            $_ -notmatch "command completed successfully" -and
            $_ -notmatch '^\s*$' -and
            $_ -notmatch '^Alias name' -and
            $_ -notmatch '^Comment' -and
            $_ -notmatch '^Members' -and
            $_ -notmatch '^---'
        } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }

    $results = foreach ($member in $members) {
        if ($member -match '\\') {
            $parts = $member.Split('\', 2)
            $domain = $parts[0]
            $user   = $parts[1]
        }
        else {
            $domain = $env:COMPUTERNAME
            $user   = $member
        }

        [pscustomobject]@{
            Domain   = $domain
            Name     = $user
            FullName = "$domain\$user"
        }
    }

    return @($results)
}

# ── Variables ─────────────────────────────────────────────────────────────
$DryRun = ConvertTo-Boolean $DryRun
$CustomerRemoveLocalAdmins = ConvertTo-Boolean $CustomerRemoveLocalAdmins
$AssetPreserveLocalAdmins = ConvertTo-Boolean $AssetPreserveLocalAdmins

# ── Main Script Action ─────────────────────────────────────────────────────────────
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
if ($osInfo.ProductType -ne 1) {
  Write-Host "This is a server. Script should not run on servers. Exiting!"
    exit
}

if (-not $CustomerRemoveLocalAdmins) {
    Write-Host "Remove Local Admins is not set for this client. Exiting."
    exit
}

if ($AssetPreserveLocalAdmins) {
    Write-Host "Preserve Local Admins is set for this asset. Exiting."
    exit
}

if ($DryRun) {
    Write-Host "NOTICE: `$DryRun is set"
}

# Get local admins
Write-Host "Getting exisiting members of local administrator group."
$LocalAdmins = Get-LocalAdminsNet | Where-Object {
    $_.Name -ne "Administrator" -and
    $_.Name -ne "Domain Admins" -and
    $_.Name -ne "Enterprise Admins"
}
$LocalAdmins | Format-Table

ForEach ($LocalAdmin in $LocalAdmins) {
    $name = $LocalAdmin.Name
    Write-Host "Removing $name from local administrators group"
    if ($DryRun) {
        Remove-LocalGroupMember -Group "Administrators" -Member $name -WhatIf
    }
    else {
        Remove-LocalGroupMember -Group "Administrators" -Member $name
    }
}

Write-Host "`nGetting members of local administrator group again, to confirm (should be blank):"
$LocalAdmins = Get-LocalAdminsNet | Where-Object {
    $_.Name -ne "Administrator" -and
    $_.Name -ne "Domain Admins" -and
    $_.Name -ne "Enterprise Admins"
}
$LocalAdmins | Format-Table

