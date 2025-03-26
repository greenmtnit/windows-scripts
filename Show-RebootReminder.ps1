#######################
# TODO - sloppy notes
#######################

<#
- Add uptime checks
    - Reboot instantly if uptime is too long (not servers, though)
    - Throw RMM alert for really long uptime
    - Don't run reboot / snoze login on servers - only do uptime check
- Avoid duplicte definiton of vars and functions in script block
- Reboot if no user is logged in
- Add Write-VerboseOutput function to show output
- Add Syncro broadcast messages for when alerts are shown and user snoozed
- add better documentation, esp. how other scripts will set key
- Make sure volatile key dissappears!
#>

# ===========================================
#  FUNCTIONS
# ===========================================  
function Set-VolatileRegKey {
    <#
        .SYNOPSIS
        Adds or updates a value in a volatile registry key.

        .DESCRIPTION
        This function adds or updates a value under `HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName`.
        If the volatile key does not already exist, it will be created. Volatile keys exist only during the current session
        and are automatically cleared after a reboot.

        .PARAMETER BaseKeyPath
        The base registry path under `HKEY_LOCAL_MACHINE`.

        .PARAMETER SubKeyPath
        The subkey path where the volatile key is located or will be created.

        .PARAMETER VolatileKeyName
        The name of the volatile registry key.

        .PARAMETER ValueName
        The name of the value to be added or updated.

        .PARAMETER ValueData
        The data to be stored in the value (integer).

        .EXAMPLE
        Set-VolatileRegKey -BaseKeyPath 'SOFTWARE\Green Mountain IT Solutions' -SubKeyPath 'RMM' -VolatileKeyName 'RebootNeeded' -ValueName 'SnoozesRemaining' -ValueData 5

        Adds or updates the value `SnoozesRemaining` under `HKLM:\SOFTWARE\Green Mountain IT Solutions\RMM\RebootNeeded` 
        with data `5`. The `RebootNeeded` key will be volatile and cleared after a reboot.

        .NOTES
        Requires administrative privileges to modify keys under `HKEY_LOCAL_MACHINE`.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$BaseKeyPath,

        [Parameter(Mandatory=$true)]
        [string]$SubKeyPath,

        [Parameter(Mandatory=$true)]
        [string]$VolatileKeyName,

        [Parameter(Mandatory=$true)]
        [string]$ValueName,

        [Parameter(Mandatory=$true)]
        [int]$ValueData
    )

    try {
        # Open the HKEY_LOCAL_MACHINE base key
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Default)

        # Open or create the base key
        $baseKey = $hklm.CreateSubKey($BaseKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Open or create the subkey
        $subKey = $baseKey.CreateSubKey($SubKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Check if the volatile key already exists
        $volatileKey = $subKey.OpenSubKey($VolatileKeyName, $true)
        
        if (-not $volatileKey) {
            # Create a new volatile key if it doesn't exist
            $volatileKey = $subKey.CreateSubKey($VolatileKeyName, 
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, 
                [Microsoft.Win32.RegistryOptions]::Volatile)
            Write-Output "Created new volatile registry key: HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName"
        }

        # Set or update the value in the volatile key as REG_DWORD
        $volatileKey.SetValue($ValueName, $ValueData, [Microsoft.Win32.RegistryValueKind]::DWord)

        Write-Output "Volatile registry key 'HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName' updated with value '$ValueName' set to '$ValueData'."
    }
    catch {
        Write-Error "An error occurred while updating the volatile registry key: $_"
    }
    finally {
        # Close all keys to release resources
        if ($volatileKey) { $volatileKey.Close() }
        if ($subKey) { $subKey.Close() }
        if ($baseKey) { $baseKey.Close() }
        if ($hklm) { $hklm.Close() }
    }
}

# ===========================================
#  VARS
# ===========================================  

# NOTE: You need to re-set any vars in the RunAsUser Script block below!
# The script block can't access vars in the main script

# Registry paths
$BaseKeyPath = 'SOFTWARE\Green Mountain IT Solutions'
$SubKeyPath = 'RMM'
$VolatileKeyName = 'RebootNeeded'
$regPath = "HKLM:\$BaseKeyPath\$SubKeyPath\$VolatileKeyName"

# Working directories
$baseDirectory = "C:\Program Files\Green Mountain IT Solutions"
$scriptsDirectory = Join-Path -Path $baseDirectory -ChildPath "Scripts"
$workingDirectory = Join-Path -Path $baseDirectory -ChildPath "RMM"
$toolsDirectory = Join-Path -Path $workingDirectory -ChildPath "Tools"

# ===========================================
#  MAIN SCRIPT ACTION
# ===========================================  

# Check if RebootNeeded Key/Value exists
if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Green Mountain IT Solutions\RMM\RebootNeeded' -Name 'RebootNeeded' -ErrorAction SilentlyContinue).RebootNeeded -eq 1) {
    Write-Host "Found RebootNeeded reg key. Reboot required. Proceeding!"
} else {
    Write-Host "The registry value 'RebootNeeded' is not set to 1 or does not exist. No reboot needed."
    exit 0
}

## Fix registry permissions to allow non-admin users to edit the volatile registry key 

# Get the current ACL (Access Control List) of the registry key
$acl = Get-Acl -Path $regPath

# Create a new access rule for "Everyone" with FullControl permissions
$accessRule = New-Object System.Security.AccessControl.RegistryAccessRule(
    "Everyone",
    [System.Security.AccessControl.RegistryRights]::FullControl,
    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)

# Add the new access rule to the ACL
$acl.SetAccessRule($accessRule)

# Apply the updated ACL back to the registry key
Set-Acl -Path $regPath -AclObject $acl

## Set up working directories
$directories = @($baseDirectory, $scriptsDirectory, $workingDirectory, $toolsDirectory)

foreach ($dir in $directories) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host -Message "Created directory: $dir"
    }
    else {
        Write-Host -Message "Directory already exists: $dir"
    }
}

##  Install the RunAsUserModule

# Check if the module is already installed 
if (Get-Module -Name RunAsUser -ListAvailable) {
    Write-Host "RunAsUser Module is already installed; skipping install"
}
else {
    $moduleURL = "https://github.com/KelvinTegelaar/RunAsUser/archive/refs/heads/master.zip"
    $moduleDownloadPath = Join-Path -Path $toolsDirectory -ChildPath "RunAsUser.zip"

    if (-not (Test-Path $moduleDownloadPath)) {
        $ProgressPreference = "SilentlyContinue"
        Write-Host -Message "Downloading to $moduleDownloadPath"
        Invoke-WebRequest -Uri $moduleURL -OutFile $moduleDownloadPath
    }
    else {
        Write-Host "Found $moduleDownloadPath already exists; skipping download"
    }

    # Unzip
    Write-Host "Extracting archive to $toolsDirectory"
    Expand-Archive -Path $moduleDownloadPath -DestinationPath $toolsDirectory -Force

    # Import the Module (Manual copy)
    $modulesPath = "C:\Program Files\WindowsPowerShell\Modules"

    Write-Host -Message "Manually copying module to $modulesPath and importing it."
    Copy-Item -Path "$toolsDirectory\RunAsUser-master" -Destination $modulesPath\RunAsUser -Recurse -Force
}
Import-Module -Name "RunAsUser"   


################################################
# Start of RunAsUser $scriptBlock

$scriptBlock = {

# ===========================================
#  FUNCTIONS
# ===========================================  

# Functions and variables must be re-defined in the script block.
# The script block can't access function and variable definitions in the main scope.
# There are clever ways to get around this, but we'll just duplicate the definitions.

function Set-VolatileRegKey {
    <#
        .SYNOPSIS
        Adds or updates a value in a volatile registry key.

        .DESCRIPTION
        This function adds or updates a value under `HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName`.
        If the volatile key does not already exist, it will be created. Volatile keys exist only during the current session
        and are automatically cleared after a reboot.

        .PARAMETER BaseKeyPath
        The base registry path under `HKEY_LOCAL_MACHINE`.

        .PARAMETER SubKeyPath
        The subkey path where the volatile key is located or will be created.

        .PARAMETER VolatileKeyName
        The name of the volatile registry key.

        .PARAMETER ValueName
        The name of the value to be added or updated.

        .PARAMETER ValueData
        The data to be stored in the value (integer).

        .EXAMPLE
        Set-VolatileRegKey -BaseKeyPath 'SOFTWARE\Green Mountain IT Solutions' -SubKeyPath 'RMM' -VolatileKeyName 'RebootNeeded' -ValueName 'SnoozesRemaining' -ValueData 5

        Adds or updates the value `SnoozesRemaining` under `HKLM:\SOFTWARE\Green Mountain IT Solutions\RMM\RebootNeeded` 
        with data `5`. The `RebootNeeded` key will be volatile and cleared after a reboot.

        .NOTES
        Requires administrative privileges to modify keys under `HKEY_LOCAL_MACHINE`.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$BaseKeyPath,

        [Parameter(Mandatory=$true)]
        [string]$SubKeyPath,

        [Parameter(Mandatory=$true)]
        [string]$VolatileKeyName,

        [Parameter(Mandatory=$true)]
        [string]$ValueName,

        [Parameter(Mandatory=$true)]
        [int]$ValueData
    )

    try {
        # Open the HKEY_LOCAL_MACHINE base key
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Default)

        # Open or create the base key
        $baseKey = $hklm.CreateSubKey($BaseKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Open or create the subkey
        $subKey = $baseKey.CreateSubKey($SubKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)

        # Check if the volatile key already exists
        $volatileKey = $subKey.OpenSubKey($VolatileKeyName, $true)
        
        if (-not $volatileKey) {
            # Create a new volatile key if it doesn't exist
            $volatileKey = $subKey.CreateSubKey($VolatileKeyName, 
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, 
                [Microsoft.Win32.RegistryOptions]::Volatile)
            Write-Output "Created new volatile registry key: HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName"
        }

        # Set or update the value in the volatile key as REG_DWORD
        $volatileKey.SetValue($ValueName, $ValueData, [Microsoft.Win32.RegistryValueKind]::DWord)

        Write-Output "Volatile registry key 'HKEY_LOCAL_MACHINE\$BaseKeyPath\$SubKeyPath\$VolatileKeyName' updated with value '$ValueName' set to '$ValueData'."
    }
    catch {
        Write-Error "An error occurred while updating the volatile registry key: $_"
    }
    finally {
        # Close all keys to release resources
        if ($volatileKey) { $volatileKey.Close() }
        if ($subKey) { $subKey.Close() }
        if ($baseKey) { $baseKey.Close() }
        if ($hklm) { $hklm.Close() }
    }
}

# ===========================================
#  VARS
# ===========================================  

# Like functions, variables must be re-defined in the script block.
# The script block cannot access definitions from the main script scope.

$BaseKeyPath = 'SOFTWARE\Green Mountain IT Solutions'
$SubKeyPath = 'RMM'
$VolatileKeyName = 'RebootNeeded'
$ValueName = 'SnoozesRemaining'
$MaxSnoozes = '4'  # Default value if the registry value doesn't exist
$ValueData = $MaxSnoozes

# Construct the full registry path
$regPath = "HKLM:\$BaseKeyPath\$SubKeyPath\$VolatileKeyName"

# Check if the registry value exists and retrieve its current value
$CurrentSnoozeValue = (Get-ItemProperty -Path $regPath -Name $ValueName).$ValueName

if ($CurrentSnoozeValue -eq 0) { # NO SNOOZES REMAINING - FORCE A REBOOT
    $snoozeLimitExceeded = "$true"
    shutdown /r /t 300 /c "Your system needs to reboot to finish installing important updates. There are no snoozes remaining. YOUR SYSTEM WILL REBOOT IN 5 MINUTES. PLEASE SAVE IMPORTANT WORK NOW."
}

else { # There are still snoozes remaining. Show window.

    $message = "Your system needs to reboot to finish installing important updates."
    $prompt = "Would you like to restart now?"
    
    if ($CurrentSnoozeValue -eq $null) {
        $snoozeCountMessage = "You can snooze up to $MaxSnoozes more time(s)."
    }
    else {
        $snoozeCountMessage = "You can snooze up to $CurrentSnoozeValue more time(s)."
    }

    # Load the necessary WPF assembly
    Add-Type -AssemblyName PresentationFramework

    # XAML UI Definition for window
    [xml]$XAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            Title="Update Needed" MinWidth="450" MinHeight="300"
            Background="White" Foreground="Black" ResizeMode="CanResizeWithGrip"
            WindowStartupLocation="CenterScreen" 
            Width="Auto" Height="Auto" SizeToContent="WidthAndHeight"
            ShowInTaskbar="False"
            UseLayoutRounding="True"
            Topmost="True"
            WindowStyle="none"
            >
        
        <Grid Margin="5">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />   <!-- Header Row -->
                <RowDefinition Height="*" />      <!-- Message Row -->
                <RowDefinition Height="Auto" />   <!-- Button Row -->
            </Grid.RowDefinitions>

            <!-- Header Text -->
            <TextBlock Grid.Row="0" Text="System Update Needed" FontSize="20" FontWeight="Bold"
                       HorizontalAlignment="Center" VerticalAlignment="Center" Padding="10" />

            <!-- Message Text -->
            <TextBlock Name="MessageText" Grid.Row="1" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"
                       TextWrapping="Wrap" Padding="10" TextAlignment="Center">
                $message
                <LineBreak />
                $prompt
                <LineBreak />
                $snoozeCountMessage
            </TextBlock>

            <!-- Button Container -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="10">
                <Button Name="RestartButton" Content="Restart" Padding="16,8" Margin="10,0"
                        Background="#016839" Foreground="White" FontSize="14"
                        HorizontalAlignment="Stretch"/>
                <Button Name="SnoozeButton" Content="Snooze" Padding="16,8" Margin="10,0"
                        Background="Gray" Foreground="White" FontSize="14"
                        HorizontalAlignment="Stretch"/>
            </StackPanel>
        </Grid>
    </Window>
"@
# Don't indent the previous line!

    # Create a XML reader
    $reader = New-Object System.Xml.XmlNodeReader $XAML

    # Load XAML
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    # Get Controls
    $RestartButton = $Window.FindName("RestartButton")
    $SnoozeButton = $Window.FindName("SnoozeButton")

    # Event Handler for Restart Button
    $RestartButton.Add_Click({
            $confirm = [System.Windows.MessageBox]::Show("Your system will restart in 60 seconds.", "Confirm Restart", [System.Windows.MessageBoxButton]::OKCancel, [System.Windows.MessageBoxImage]::Question)
            if ($confirm -eq [System.Windows.MessageBoxResult]::OK) {
                shutdown /r /t 60  # Restart the system with a 60-second delay
                $Window.Close()
            }
            else {
                $Window.Close()
            }
    })

    # Event Handler for Snooze Button
    $SnoozeButton.Add_Click({
        if ($CurrentSnoozeValue -eq $null) { # Don't do if (! $CurrentSnoozeValue) - we need to handle 0 separately! elseif ($CurrentSnoozeValue -eq 0)
            # If the value does not exist, set it to the default ($MaxSnoozes)
            Write-Output "The registry value '$ValueName' does not exist. Creating it with default value: $MaxSnoozes."
            Set-VolatileRegKey -BaseKeyPath $BaseKeyPath -SubKeyPath $SubKeyPath -VolatileKeyName $VolatileKeyName -ValueName $ValueName -ValueData $MaxSnoozes
        }
         
        else {
            # Decrease the value by 1, ensuring it doesn't go below 0
            $newValue = [math]::Max(0, $CurrentSnoozeValue - 1)

            # Update the registry value with the new value
            Set-VolatileRegKey -BaseKeyPath $BaseKeyPath -SubKeyPath $SubKeyPath -VolatileKeyName $VolatileKeyName -ValueName $ValueName -ValueData $newValue

            Write-Output "The registry value '$ValueName' was updated. New value: $newValue."
        }
        # Close the window
        $Window.Close()
    })

    # Show the window
    $Window.ShowDialog()
    }

} 
#End of $scriptBlock
################################################


# Run the script block with RunAsUser
Invoke-AsCurrentUser -ScriptBlock $scriptblock
