<#
.SYNOPSIS
    Creates (or re-enables) a temporary local admin account with a random
    password, sets it to expire tomorrow, and prints the password.

.NOTES
    Run in 64-bit Windows PowerShell 5.1 as admin/SYSTEM (e.g. Syncro Backgrounding Tools).
    When you're done, disable the account:  net user LocalAdmin /active:no
#>

param(
    [string]$UserName = "LocalAdmin",
    [int]$PasswordLength = 16
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command New-LocalUser -ErrorAction SilentlyContinue)) {
    throw "LocalAccounts cmdlets not available. Run this in 64-bit Windows PowerShell 5.1 (Windows 10/11 or Server 2016+)."
}

# --- Random password generation (cryptographically secure) ---
$rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 4

function Get-RandomIndex([int]$Max) {
    # Rejection sampling to avoid modulo bias
    $range = [uint64][uint32]::MaxValue + 1
    $limit = $range - ($range % $Max)
    do {
        $rng.GetBytes($bytes)
        $val = [BitConverter]::ToUInt32($bytes, 0)
    } while ($val -ge $limit)
    return [int]($val % $Max)
}

# Ambiguous characters (0/O, 1/l/I) left out so the password is easy to type
$upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
$lower   = 'abcdefghijkmnopqrstuvwxyz'
$digits  = '23456789'
$symbols = '!@#$%*-_+=?'
$all     = $upper + $lower + $digits + $symbols

$chars = New-Object System.Collections.Generic.List[char]
# Guarantee at least one of each type (meets Windows complexity rules)
foreach ($set in @($upper, $lower, $digits, $symbols)) {
    $chars.Add($set[(Get-RandomIndex $set.Length)])
}
while ($chars.Count -lt $PasswordLength) {
    $chars.Add($all[(Get-RandomIndex $all.Length)])
}
# Fisher-Yates shuffle so the guaranteed characters aren't always first
for ($i = $chars.Count - 1; $i -gt 0; $i--) {
    $j = Get-RandomIndex ($i + 1)
    $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
}

$Password       = -join $chars
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Expires        = (Get-Date).AddDays(1)

# --- Create or re-enable the account ---
$existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if ($existing -and $existing.Enabled) {
    throw "Account '$UserName' already exists and is enabled. Someone may be using it. Change the password manually if needed."
}
if ($existing) {
    Set-LocalUser -Name $UserName -Password $SecurePassword -AccountExpires $Expires
    Enable-LocalUser -Name $UserName
    Write-Output "Existing account '$UserName' re-enabled and password reset."
}
else {
    New-LocalUser -Name $UserName -Password $SecurePassword -AccountExpires $Expires `
        -Description "Temporary GMITS support account" | Out-Null
    Write-Output "Account '$UserName' created."
}

# --- Add to local Administrators (by SID, works on non-English Windows) ---
try {
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $UserName
    Write-Output "Added '$UserName' to local Administrators."
}
catch [Microsoft.PowerShell.Commands.MemberExistsException] {
    Write-Output "'$UserName' is already a local Administrator."
}

# --- Output ---
Write-Output ""
Write-Output "Username: .\$UserName"
Write-Output "Password: $Password"
Write-Output "Expires:  $Expires"