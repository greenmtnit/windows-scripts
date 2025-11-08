<#
Check-Windows11Support.ps1

Script adapted from Microsoft's official hardware readiness script: https://aka.ms/HWReadinessScript to work in SyncroMSP.

This script writes Windows 11 compatibility results to a Syncro custom asset field called "SupportWindows11".

If the machine DOES support Windows 11, $SupportWindows11 will be set to the string "Yes".

If the machine does NOT support Windows 11, $SupportWindows11 will be set to "No", plus a description of the reason(s) why.
Example: $SupportsWindows11 = "No, Processor, TPM" means the machine does not support Windows 11 because it lacks a compatible processor and TPM.

Note: Certain compatibility checks may be easily resolved.
If the only reason(s) for failed Windows 11 support is the TPM and/or SecureBoot, these may be able to be enabled in BIOS.
Other reasons, such as an incompatibler processor, are not easily resolved.

#>

# ===========================================
#  BEGIN OFFICIAL MICROSOFT SCRIPT PORTION
# ===========================================  

#=============================================================================================================================
#
# Script Name:     HardwareReadiness.ps1
# Description:     Verifies the hardware compliance. Return code 0 for success. 
#                  In case of failure, returns non zero error code along with error message.

# This script is not supported under any Microsoft standard support program or service and is distributed under the MIT license

# Copyright (C) 2021 Microsoft Corporation

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
# is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#=============================================================================================================================

$exitCode = 0

[int]$MinOSDiskSizeGB = 64
[int]$MinMemoryGB = 4
[Uint32]$MinClockSpeedMHz = 1000
[Uint32]$MinLogicalCores = 2
[Uint16]$RequiredAddressWidth = 64

$PASS_STRING = "PASS"
$FAIL_STRING = "FAIL"
$FAILED_TO_RUN_STRING = "FAILED TO RUN"
$UNDETERMINED_CAPS_STRING = "UNDETERMINED"
$UNDETERMINED_STRING = "Undetermined"
$CAPABLE_STRING = "Capable"
$NOT_CAPABLE_STRING = "Not capable"
$CAPABLE_CAPS_STRING = "CAPABLE"
$NOT_CAPABLE_CAPS_STRING = "NOT CAPABLE"
$STORAGE_STRING = "Storage"
$OS_DISK_SIZE_STRING = "OSDiskSize"
$MEMORY_STRING = "Memory"
$SYSTEM_MEMORY_STRING = "System_Memory"
$GB_UNIT_STRING = "GB"
$TPM_STRING = "TPM"
$TPM_VERSION_STRING = "TPMVersion"
$PROCESSOR_STRING = "Processor"
$SECUREBOOT_STRING = "SecureBoot"
$I7_7820HQ_CPU_STRING = "i7-7820hq CPU"

# 0=name of check, 1=attribute checked, 2=value, 3=PASS/FAIL/UNDETERMINED
$logFormat = '{0}: {1}={2}. {3}; '

# 0=name of check, 1=attribute checked, 2=value, 3=unit of the value, 4=PASS/FAIL/UNDETERMINED
$logFormatWithUnit = '{0}: {1}={2}{3}. {4}; '

# 0=name of check.
$logFormatReturnReason = '{0}, '

# 0=exception.
$logFormatException = '{0}; '

# 0=name of check, 1= attribute checked and its value, 2=PASS/FAIL/UNDETERMINED
$logFormatWithBlob = '{0}: {1}. {2}; '

# return returnCode is -1 when an exception is thrown. 1 if the value does not meet requirements. 0 if successful. -2 default, script didn't run.
$outObject = @{ returnCode = -2; returnResult = $FAILED_TO_RUN_STRING; returnReason = ""; logging = "" }

# NOT CAPABLE(1) state takes precedence over UNDETERMINED(-1) state
function Private:UpdateReturnCode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(-2, 1)]
        [int] $ReturnCode
    )

    Switch ($ReturnCode) {

        0 {
            if ($outObject.returnCode -eq -2) {
                $outObject.returnCode = $ReturnCode
            }
        }
        1 {
            $outObject.returnCode = $ReturnCode
        }
        -1 {
            if ($outObject.returnCode -ne 1) {
                $outObject.returnCode = $ReturnCode
            }
        }
    }
}

$Source = @"
using Microsoft.Win32;
using System;
using System.Runtime.InteropServices;

    public class CpuFamilyResult
    {
        public bool IsValid { get; set; }
        public string Message { get; set; }
    }

    public class CpuFamily
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_INFO
        {
            public ushort ProcessorArchitecture;
            ushort Reserved;
            public uint PageSize;
            public IntPtr MinimumApplicationAddress;
            public IntPtr MaximumApplicationAddress;
            public IntPtr ActiveProcessorMask;
            public uint NumberOfProcessors;
            public uint ProcessorType;
            public uint AllocationGranularity;
            public ushort ProcessorLevel;
            public ushort ProcessorRevision;
        }

        [DllImport("kernel32.dll")]
        internal static extern void GetNativeSystemInfo(ref SYSTEM_INFO lpSystemInfo);

        public enum ProcessorFeature : uint
        {
            ARM_SUPPORTED_INSTRUCTIONS = 34
        }

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool IsProcessorFeaturePresent(ProcessorFeature processorFeature);

        private const ushort PROCESSOR_ARCHITECTURE_X86 = 0;
        private const ushort PROCESSOR_ARCHITECTURE_ARM64 = 12;
        private const ushort PROCESSOR_ARCHITECTURE_X64 = 9;

        private const string INTEL_MANUFACTURER = "GenuineIntel";
        private const string AMD_MANUFACTURER = "AuthenticAMD";
        private const string QUALCOMM_MANUFACTURER = "Qualcomm Technologies Inc";

        public static CpuFamilyResult Validate(string manufacturer, ushort processorArchitecture)
        {
            CpuFamilyResult cpuFamilyResult = new CpuFamilyResult();

            if (string.IsNullOrWhiteSpace(manufacturer))
            {
                cpuFamilyResult.IsValid = false;
                cpuFamilyResult.Message = "Manufacturer is null or empty";
                return cpuFamilyResult;
            }

            string registryPath = "HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0";
            SYSTEM_INFO sysInfo = new SYSTEM_INFO();
            GetNativeSystemInfo(ref sysInfo);

            switch (processorArchitecture)
            {
                case PROCESSOR_ARCHITECTURE_ARM64:

                    if (manufacturer.Equals(QUALCOMM_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        bool isArmv81Supported = IsProcessorFeaturePresent(ProcessorFeature.ARM_SUPPORTED_INSTRUCTIONS);

                        if (!isArmv81Supported)
                        {
                            string registryName = "CP 4030";
                            long registryValue = (long)Registry.GetValue(registryPath, registryName, -1);
                            long atomicResult = (registryValue >> 20) & 0xF;

                            if (atomicResult >= 2)
                            {
                                isArmv81Supported = true;
                            }
                        }

                        cpuFamilyResult.IsValid = isArmv81Supported;
                        cpuFamilyResult.Message = isArmv81Supported ? "" : "Processor does not implement ARM v8.1 atomic instruction";
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "The processor isn't currently supported for Windows 11";
                    }

                    break;

                case PROCESSOR_ARCHITECTURE_X64:
                case PROCESSOR_ARCHITECTURE_X86:

                    int cpuFamily = sysInfo.ProcessorLevel;
                    int cpuModel = (sysInfo.ProcessorRevision >> 8) & 0xFF;
                    int cpuStepping = sysInfo.ProcessorRevision & 0xFF;

                    if (manufacturer.Equals(INTEL_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            cpuFamilyResult.IsValid = true;
                            cpuFamilyResult.Message = "";

                            if (cpuFamily >= 6 && cpuModel <= 95 && !(cpuFamily == 6 && cpuModel == 85))
                            {
                                cpuFamilyResult.IsValid = false;
                                cpuFamilyResult.Message = "";
                            }
                            else if (cpuFamily == 6 && (cpuModel == 142 || cpuModel == 158) && cpuStepping == 9)
                            {
                                string registryName = "Platform Specific Field 1";
                                int registryValue = (int)Registry.GetValue(registryPath, registryName, -1);

                                if ((cpuModel == 142 && registryValue != 16) || (cpuModel == 158 && registryValue != 8))
                                {
                                    cpuFamilyResult.IsValid = false;
                                }
                                cpuFamilyResult.Message = "PlatformId " + registryValue;
                            }
                        }
                        catch (Exception ex)
                        {
                            cpuFamilyResult.IsValid = false;
                            cpuFamilyResult.Message = "Exception:" + ex.GetType().Name;
                        }
                    }
                    else if (manufacturer.Equals(AMD_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        cpuFamilyResult.IsValid = true;
                        cpuFamilyResult.Message = "";

                        if (cpuFamily < 23 || (cpuFamily == 23 && (cpuModel == 1 || cpuModel == 17)))
                        {
                            cpuFamilyResult.IsValid = false;
                        }
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "Unsupported Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    }

                    break;

                default:
                    cpuFamilyResult.IsValid = false;
                    cpuFamilyResult.Message = "Unsupported CPU category. Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    break;
            }
            return cpuFamilyResult;
        }
    }
"@

# Storage
try {
    $osDrive = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -Property SystemDrive
    $osDriveSize = Get-WmiObject -Class Win32_LogicalDisk -filter "DeviceID='$($osDrive.SystemDrive)'" | Select-Object @{Name = "SizeGB"; Expression = { $_.Size / 1GB -as [int] } }  

    if ($null -eq $osDriveSize) {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
        $outObject.logging += $logFormatWithBlob -f $STORAGE_STRING, "Storage is null", $FAIL_STRING
        $exitCode = 1
    }
    elseif ($osDriveSize.SizeGB -lt $MinOSDiskSizeGB) {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
        $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
        $exitCode = 1
    }
    else {
        $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $PASS_STRING
        UpdateReturnCode -ReturnCode 0
    }
}
catch {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormat -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}

# Memory (bytes)
try {
    $memory = Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum | Select-Object @{Name = "SizeGB"; Expression = { $_.Sum / 1GB -as [int] } }

    if ($null -eq $memory) {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
        $outObject.logging += $logFormatWithBlob -f $MEMORY_STRING, "Memory is null", $FAIL_STRING
        $exitCode = 1
    }
    elseif ($memory.SizeGB -lt $MinMemoryGB) {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
        $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
        $exitCode = 1
    }
    else {
        $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $PASS_STRING
        UpdateReturnCode -ReturnCode 0
    }
}
catch {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormat -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}

# TPM
try {
    $tpm = Get-Tpm

    if ($null -eq $tpm) {
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
        $outObject.logging += $logFormatWithBlob -f $TPM_STRING, "TPM is null", $FAIL_STRING
        $exitCode = 1
    }
    elseif ($tpm.TpmPresent) {
        $tpmVersion = Get-WmiObject -Class Win32_Tpm -Namespace root\CIMV2\Security\MicrosoftTpm | Select-Object -Property SpecVersion

        if ($null -eq $tpmVersion.SpecVersion) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
            $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, "null", $FAIL_STRING
            $exitCode = 1
        }

        $majorVersion = $tpmVersion.SpecVersion.Split(",")[0] -as [int]
        if ($majorVersion -lt 2) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
            $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $FAIL_STRING
            $exitCode = 1
        }
        else {
            $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $PASS_STRING
            UpdateReturnCode -ReturnCode 0
        }
    }
    else {
        if ($tpm.GetType().Name -eq "String") {
            UpdateReturnCode -ReturnCode -1
            $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
            $outObject.logging += $logFormatException -f $tpm
        }
        else {
            UpdateReturnCode -ReturnCode  1
            $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
            $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpm.TpmPresent), $FAIL_STRING
        }
        $exitCode = 1
    }
}
catch {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}

# CPU Details
$cpuDetails;
try {
    $cpuDetails = @(Get-WmiObject -Class Win32_Processor)[0]

    if ($null -eq $cpuDetails) {
        UpdateReturnCode -ReturnCode 1
        $exitCode = 1
        $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
        $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, "CpuDetails is null", $FAIL_STRING
    }
    else {
        $processorCheckFailed = $false

        # AddressWidth
        if ($null -eq $cpuDetails.AddressWidth -or $cpuDetails.AddressWidth -ne $RequiredAddressWidth) {
            UpdateReturnCode -ReturnCode 1
            $processorCheckFailed = $true
            $exitCode = 1
        }

        # ClockSpeed is in MHz
        if ($null -eq $cpuDetails.MaxClockSpeed -or $cpuDetails.MaxClockSpeed -le $MinClockSpeedMHz) {
            UpdateReturnCode -ReturnCode 1;
            $processorCheckFailed = $true
            $exitCode = 1
        }

        # Number of Logical Cores
        if ($null -eq $cpuDetails.NumberOfLogicalProcessors -or $cpuDetails.NumberOfLogicalProcessors -lt $MinLogicalCores) {
            UpdateReturnCode -ReturnCode 1
            $processorCheckFailed = $true
            $exitCode = 1
        }

        # CPU Family
        Add-Type -TypeDefinition $Source
        $cpuFamilyResult = [CpuFamily]::Validate([String]$cpuDetails.Manufacturer, [uint16]$cpuDetails.Architecture)

        $cpuDetailsLog = "{AddressWidth=$($cpuDetails.AddressWidth); MaxClockSpeed=$($cpuDetails.MaxClockSpeed); NumberOfLogicalCores=$($cpuDetails.NumberOfLogicalProcessors); Manufacturer=$($cpuDetails.Manufacturer); Caption=$($cpuDetails.Caption); $($cpuFamilyResult.Message)}"

        if (!$cpuFamilyResult.IsValid) {
            UpdateReturnCode -ReturnCode 1
            $processorCheckFailed = $true
            $exitCode = 1
        }

        if ($processorCheckFailed) {
            $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
            $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $FAIL_STRING
        }
        else {
            $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $PASS_STRING
            UpdateReturnCode -ReturnCode 0
        }
    }
}
catch {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormat -f $PROCESSOR_STRING, $PROCESSOR_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}

# SecureBooot
try {
    $isSecureBootEnabled = Confirm-SecureBootUEFI
    $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $CAPABLE_STRING, $PASS_STRING
    UpdateReturnCode -ReturnCode 0
}
catch [System.PlatformNotSupportedException] {
    # PlatformNotSupportedException "Cmdlet not supported on this platform." - SecureBoot is not supported or is non-UEFI computer.
    UpdateReturnCode -ReturnCode 1
    $outObject.returnReason += $logFormatReturnReason -f $SECUREBOOT_STRING
    $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $NOT_CAPABLE_STRING, $FAIL_STRING
    $exitCode = 1
}
catch [System.UnauthorizedAccessException] {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}
catch {
    UpdateReturnCode -ReturnCode -1
    $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
    $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
    $exitCode = 1
}

# i7-7820hq CPU
try {
    $supportedDevices = @('surface studio 2', 'precision 5520')
    $systemInfo = @(Get-WmiObject -Class Win32_ComputerSystem)[0]

    if ($null -ne $cpuDetails) {
        if ($cpuDetails.Name -match 'i7-7820hq cpu @ 2.90ghz'){
            $modelOrSKUCheckLog = $systemInfo.Model.Trim()
            if ($supportedDevices -contains $modelOrSKUCheckLog){
                $outObject.logging += $logFormatWithBlob -f $I7_7820HQ_CPU_STRING, $modelOrSKUCheckLog, $PASS_STRING
                $outObject.returnCode = 0
                $exitCode = 0
            }
        }
    }
}
catch {
    if ($outObject.returnCode -ne 0){
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormatWithBlob -f $I7_7820HQ_CPU_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
    }
}

Switch ($outObject.returnCode) {

    0 { $outObject.returnResult = $CAPABLE_CAPS_STRING }
    1 { $outObject.returnResult = $NOT_CAPABLE_CAPS_STRING }
    -1 { $outObject.returnResult = $UNDETERMINED_CAPS_STRING }
    -2 { $outObject.returnResult = $FAILED_TO_RUN_STRING }
}

$reason=$outObject.returnReason

$outObject | ConvertTo-Json -Compress

# ===========================================
#  BEGIN CUSTOMIZATIONS FOR SYNCRO
# =========================================== 
Import-Module $env:SyncroModule

# Function to set reg key for all users
# We'll use this to set HKCU\Software\Microsoft\PCHC -> UpgradeEligibility = 1 for all users
function Set-HKCUAllUsersRegistryValue {
    <#
    .SYNOPSIS
        Sets or updates a registry value under HKEY_CURRENT_USER for all current and future users on the local machine.

    .DESCRIPTION
        This function modifies registry keys and values under HKCU for all user profiles currently on the machine and/or for future user profiles 
        (by updating the Default user hive). It supports setting any registry path, value name, value data, and type, with options to overwrite 
        existing values or skip them. It also provides an optional backup of affected registry hives before modification.

    .PARAMETER SubKeyPath
        The relative registry path under HKCU where the value will be created or updated for each user. For example: "Software\Microsoft\PCHC".

    .PARAMETER ValueName
        The name of the registry value to set.

    .PARAMETER ValueData
        The data to assign to the registry value.

    .PARAMETER ValueType
        The type of the registry value. Valid options: String, ExpandString, DWord, QWord, Binary, MultiString.

    .PARAMETER Force
        Switch to overwrite existing registry values. If not specified and the value exists, it will be skipped.

    .PARAMETER NoBackup
        Switch to disable backing up each user hive before modification. By default, backup is enabled.

    .PARAMETER BackupPath
        The folder path where registry backups will be stored. Default is "C:\Windows\Temp\RegistryBackups".

    .PARAMETER ModifyExistingUsers
        Switch to enable modifying all existing user profile registry hives. Default is enabled.

    .PARAMETER ModifyFutureUsers
        Switch to enable modifying the Default user hive (which affects future new user profiles). Default is enabled.

    .EXAMPLE
        Set-HKCUAllUsersRegistryValue -SubKeyPath "Software\MyApp" -ValueName "Enabled" -ValueData 1 -ValueType DWord -Force

        Updates or creates the DWORD registry value "Enabled" with data 1 under HKCU\Software\MyApp for all current and future users,
        overwriting existing values and backing up hives before modification.

    .EXAMPLE
        Set-HKCUAllUsersRegistryValue `
            -SubKeyPath "Software\ContosoApp" `
            -ValueName "UserPreference" `
            -ValueData "DarkMode" `
            -ValueType String `
            -ModifyFutureUsers:$false `
            -Verbose
            
        Set a string registry value for all current users only, without modifying future user profiles,
        and without forcing overwrite if the value already exists (no $Force).

    .NOTES
        - Requires administrative privileges to load/unload user hives.
        - Only modifies local, domain, and Azure AD user profiles, avoiding system accounts.
        - Uses built-in support (SupportsShouldProcess) for -WhatIf and -Confirm via CmdletBinding.

    .LINK
        None
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SubKeyPath,  # e.g. "Software\Microsoft\PCHC"

        [Parameter(Mandatory)]
        [string]$ValueName,   # e.g. "UpgradeEligibility"

        [Parameter(Mandatory)]
        [string]$ValueData,   # e.g. 1

        [Parameter(Mandatory)]
        [ValidateSet('String','ExpandString','DWord','QWord','Binary','MultiString')]
        [string]$ValueType,

        [switch]$Force,                   # Overwrite existing values
        [switch]$NoBackup,                # Disable registry backup
        [string]$BackupPath = "C:\Windows\Temp\RegistryBackups",

        [switch]$ModifyExistingUsers = $true,
        [switch]$ModifyFutureUsers = $true
    )

    Write-Verbose "Starting Set-HKCUAllUsersRegistryValue for $SubKeyPath\$ValueName"

    # Define regex to match only desired SIDs. This matches local, domain, and Azure AD (Entra) users.
    # It will not match system or built-in users.
    #   S-1-5-21 = local or domain user
    #   S-1-12-1 = Azure AD user
    $PatternSID = 'S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$'

    if (-not $NoBackup) {
        if (-not (Test-Path $BackupPath)) { New-Item -ItemType Directory -Path $BackupPath | Out-Null }
    }

    function Backup-Hive ($RootPath, $Username) {
        if (-not $NoBackup) {
            $BackupFile = Join-Path $BackupPath "$($Username)_$(Get-Date -Format 'yyyyMMdd_HHmmss').regbak"
            Write-Verbose "Backing up $RootPath to $BackupFile"
            # Use full path for REG.EXE export
            reg export $RootPath $BackupFile /y | Out-Null 2>&1
        }
    }
    
    function Backup-NTUserDat ($UserHivePath, $Username) {
        if (-not $NoBackup) {
            $BackupFile = Join-Path $BackupPath "$($Username)_NTUSER_$(Get-Date -Format 'yyyyMMdd_HHmmss').dat"
            Write-Verbose "Backing up NTUSER.DAT for $Username to $BackupFile"
            Copy-Item -Path $UserHivePath -Destination $BackupFile -Force
        }
    }

    function Set-RegistryValueForHive($RootPath, $Username) {
        $TargetRegPath = Join-Path $RootPath $SubKeyPath
        if (-not (Test-Path $TargetRegPath)) { New-Item -Path $TargetRegPath -Force | Out-Null }
        
        $existing = Get-ItemProperty -Path $TargetRegPath -Name $ValueName -ErrorAction SilentlyContinue
        if ($existing -and -not $Force) {
            Write-Verbose "Skipping $Username, value already exists and -Force not specified."
        } else {
            Write-Verbose "Setting $TargetRegPath\$ValueName => $ValueData"
            New-ItemProperty -Path $TargetRegPath -Name $ValueName -Value $ValueData -PropertyType $ValueType -Force | Out-Null
        }
    }

    if ($ModifyExistingUsers) {
        Write-Verbose "Modifying existing users' hives..."
        $ProfileList = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
            Where-Object { $_.PSChildName -match $PatternSID } |
            Select-Object @{Name="SID"; Expression={ $_.PSChildName }},
                          @{Name="HivePath"; Expression={ "$($_.ProfileImagePath)\NTUSER.DAT" }},
                          @{Name="Username"; Expression={ Split-Path $_.ProfileImagePath -Leaf }}

        $LoadedHives = Get-ChildItem -Path Registry::HKEY_USERS |
            Where-Object { $_.PSChildName -match $PatternSID } |
            Select-Object -ExpandProperty PSChildName

        foreach ($User in $ProfileList) {
            $HiveWasLoaded = $true
            if ($User.SID -notin $LoadedHives) {
                Write-Verbose "Loading hive for $($User.Username)"
                reg load "HKU\$($User.SID)" $User.HivePath | Out-Null
                $HiveWasLoaded = $false
            }

            Backup-Hive "HKU\$($User.SID)" $User.Username
            Set-RegistryValueForHive "Registry::HKEY_USERS\$($User.SID)" $User.Username

            if (-not $HiveWasLoaded) {
                [gc]::Collect()
                reg unload "HKU\$($User.SID)" | Out-Null
            }
        }
    }

    if ($ModifyFutureUsers) {
        Write-Verbose "Backing up Default User NTUSER.DAT"
        Backup-NTUserDat "C:\Users\Default\NTUSER.DAT" "DefaultUser"
        
        Write-Verbose "Modifying Default User hive for future users..."
        $TempHive = "HKLM\TempDefaultUser"
        $NTUserDat = "C:\Users\Default\NTUSER.DAT"

        reg load $TempHive $NTUserDat | Out-Null

        $DefaultRegPath = "Registry::HKEY_LOCAL_MACHINE\TempDefaultUser\$SubKeyPath"
        if (-not (Test-Path $DefaultRegPath)) { New-Item -Path $DefaultRegPath -Force | Out-Null }

        Backup-Hive "HKLM\TempDefaultUser" "DefaultUser"
        Set-RegistryValueForHive "Registry::HKEY_LOCAL_MACHINE\TempDefaultUser" "DefaultUser"

        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        reg unload $TempHive | Out-Null
    }

    Write-Verbose "Completed registry modifications."
}

If (-Not $outObject.returnCode) {
  Write-Host "This system DOES support Windows 11"
  $SupportsWindows11="Yes"
  Write-Host "Setting UpgradeEligibility registry value for all users"
  # Set HKCU\Software\Microsoft\PCHC -> UpgradeEligibility = 1 for all users
  # Prevents Update Assistant from requiring PC Health Check app to run.
  Set-HKCUAllUsersRegistryValue `
  -SubKeyPath "Software\Microsoft\PCHC" `
  -ValueName "UpgradeEligibility" `
  -ValueData 1 `
  -ValueType DWord `
  -Force `
}
Elseif ($outObject.returnCode -ge 1) {
  Write-Host "This system does NOT support Windows 11. Reason: $reason"
  $SupportsWindows11="No, $reason"
}
Else {
  Write-Host "Unknown result!"
  $SupportsWindows11="Unknown"
}

Set-Asset-Field -Name "SupportsWindows11" -Value $SupportsWindows11
