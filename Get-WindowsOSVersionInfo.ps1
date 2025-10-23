<#
  Get-WindowsOSVersionInfo.ps1
  
  Gets Windows version, build number, and edition. 
  
  Also checks if Windows 10 or Windows 11 is running a supported version.
  If on an unsupported version, an RMM alert is generated in SyncroMSP.
  
  If the script detects Windows 10, a GUI pop-up will be displayed to the currently logged in user advising them of Windows 10 EoL.
  
  If the script detects Windows 11 Version 23H2, a GUI pop-up will be displayed to the currently logged in user offering a self-service upgrade to the latest version.
  
  Thanks to https://gist.github.com/asheroto/cfa26dd00177a03c81635ea774406b2b for Get-OSInfo function
  
#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

# FUNCTIONS
function Check-Laptop {
    $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    return $systemInfo.PCSystemType -eq 2
}

# VARIABLES - CHANGE THESE 

# Minimum Build Versions
# To get build numbers, see: https://en.wikipedia.org/wiki/Windows_11_version_history

# $Windows10MinimumBuild = "19045" # 22H2, EoL October 14, 2025
$Windows11MinimumBuild = "22631" # 23H2, EoL November 11, 2025
#$Windows11MinimumBuild = "26100" # 24H2, EoL October 13, 2026

# SCRIPT BLOCKS - For GUI Pop-Ups

################################################
# SCRIPT BLOCK 1 - $Win10ScriptBlock
################################################
$Win10ScriptBlock = {
$message = "This computer is running Windows 10, which reached End-of-Life on October 14, 2025.
Running an operating system past its end-of-life date is a serious security risk.
Please use the self-service upgrade icon on your desktop, if present,
or contact your IT provider ASAP for assistance."

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework

# Define XAML
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Upgrade Required"
        MinWidth="450" MinHeight="250"
        WindowStartupLocation="CenterScreen"
        Background="#FFF5F5"
        Foreground="#111"
        SizeToContent="WidthAndHeight"
        Topmost="True"
        ResizeMode="NoResize"
        WindowStyle="None"
        AllowsTransparency="False">

    <Window.Resources>
        <Style x:Key="HoverButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Width" Value="120"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#7F1D1D"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border BorderThickness="3" BorderBrush="#DC2626" CornerRadius="6" Padding="10">
        <Grid Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>   <!-- Header -->
                <RowDefinition Height="*"/>     <!-- Body -->
                <RowDefinition Height="Auto"/>  <!-- Button -->
            </Grid.RowDefinitions>

            <!-- Header -->
            <Border Grid.Row="0" Background="#DC2626" Padding="8" CornerRadius="4">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock Text="⚠" FontSize="28" Foreground="White" Margin="0,0,8,0"/>
                    <TextBlock Text="CRITICAL: Windows 10 Support Has Ended"
                               FontSize="18"
                               FontWeight="Bold"
                               Foreground="White"
                               VerticalAlignment="Center"/>
                </StackPanel>
            </Border>

            <!-- Message -->
            <TextBlock Name="MessageText" Grid.Row="1"
                       TextWrapping="Wrap"
                       FontSize="15"
                       FontWeight="SemiBold"
                       LineHeight="22"
                       TextAlignment="Center"
                       Margin="15,20,15,10"
                       Foreground="#3B0D0C"/>

            <!-- Buttons -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,15,0,0">
                <Button Name="DismissButton"
                        Content="Dismiss"
                        Style="{StaticResource HoverButtonStyle}"
                        Margin="5"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

# Load XAML
$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Set message text
$Window.FindName("MessageText").Text = $message

# Hook up Dismiss button
$DismissButton = $Window.FindName("DismissButton")
$DismissButton.Add_Click({
    $Window.Close()
})

# Show window
$Window.ShowDialog()
}
# End of $Win10ScriptBlock
################################################


################################################
# SCRIPT BLOCK 2 - $23H2ScriptBlock
################################################

$23H2ScriptBlock = {
$message = "Your computer needs an update to stay secure and running smoothly.
You can run the update now, or use the self-service upgrade icon on your desktop at any time.    
Please contact your IT provider if you need assistance."

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework

# Define XAML with a Button style that changes background color on hover
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Upgrade Required"
        MinWidth="450" MinHeight="250"
        WindowStartupLocation="CenterScreen"
        Background="#FAFAFA"
        Foreground="#222"
        SizeToContent="WidthAndHeight"
        Topmost="True"
        ResizeMode="NoResize"
        WindowStyle="None"
        AllowsTransparency="False">
    <Window.Resources>
        <Style x:Key="HoverButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Gray"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="20,8"/>
            <Setter Property="Width" Value="120"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#00BCF2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="LightGray"/>
                                <Setter Property="Foreground" Value="Gray"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border BorderThickness="2" BorderBrush="#0078D4" Padding="10">
        <Grid Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>   <!-- Header -->
                <RowDefinition Height="*"/>     <!-- Body -->
                <RowDefinition Height="Auto"/>  <!-- Button -->
            </Grid.RowDefinitions>
            <!-- Header Row -->
            <StackPanel Grid.Row="0" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,0,0,10">
                <TextBlock Text="⚠" FontSize="26" Foreground="#DC2626" Margin="0,0,8,0"/>
                <TextBlock Text="System Update Needed"
                           FontSize="20" FontWeight="Bold"
                           VerticalAlignment="Center"/>
            </StackPanel>
            <!-- Message -->
            <TextBlock Name="MessageText" Grid.Row="1"
                       TextWrapping="Wrap"
                       FontSize="15"
                       TextAlignment="Center"
                       Margin="5"
                       Foreground="Black"/>
            <!-- Buttons -->
            <StackPanel Grid.Row="2" Orientation="Horizontal"
                        HorizontalAlignment="Center" Margin="0,15,0,0">
                <Button Name="RunBatchButton" 
                        Content="Update Now"
                        Style="{StaticResource HoverButtonStyle}" 
                        Margin="5"/>
                <Button Name="DismissButton"
                        Content="Dismiss"
                        Style="{StaticResource HoverButtonStyle}"
                        Margin="5"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@
# Do not indent the previous line!

# Load the XAML
$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Insert message dynamically
$Window.FindName("MessageText").Text = $message

# Get the Dismiss button and attach event
$DismissButton = $Window.FindName("DismissButton")
$DismissButton.Add_Click({
    $Window.Close()
})

$RunBatchButton = $Window.FindName("RunBatchButton")
$RunBatchButton.Add_Click({
    Start-Process -FilePath "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows24H2SelfServiceUpgrade.bat"
    $Window.Close()
})

# Show window
$Window.ShowDialog()

}
# End of $23H2ScriptBlock
################################################

# FUNCTIONS
function Get-OSInfo { # https://gist.github.com/asheroto/cfa26dd00177a03c81635ea774406b2b
    <#
        .SYNOPSIS
        Retrieves detailed information about the operating system version and architecture.

        .DESCRIPTION
        This function queries both the Windows registry and the Win32_OperatingSystem class to gather comprehensive information about the operating system. It returns details such as the release ID, display version, name, type (Workstation/Server), numeric version, edition ID, version (object that includes major, minor, and build numbers), and architecture (OS architecture, not processor architecture).

        .EXAMPLE
        Get-OSInfo

        This example retrieves the OS version details of the current system and returns an object with properties like ReleaseId, DisplayVersion, Name, Type, NumericVersion, EditionId, Version, and Architecture.

        .EXAMPLE
        (Get-OSInfo).Version.Major

        This example retrieves the major version number of the operating system. The Get-OSInfo function returns an object with a Version property, which itself is an object containing Major, Minor, and Build properties. You can access these sub-properties using dot notation.

        .EXAMPLE
        $osDetails = Get-OSInfo
        Write-Output "OS Name: $($osDetails.Name)"
        Write-Output "OS Type: $($osDetails.Type)"
        Write-Output "OS Architecture: $($osDetails.Architecture)"

        This example stores the result of Get-OSInfo in a variable and then accesses various properties to print details about the operating system.
    #>
    [CmdletBinding()]
    param ()

    try {
        # Get registry values
        $registryValues = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $releaseIdValue = $registryValues.ReleaseId
        $displayVersionValue = $registryValues.DisplayVersion
        $nameValue = $registryValues.ProductName
        $editionIdValue = $registryValues.EditionId

        # Strip out "Server" from the $editionIdValue if it exists
        $editionIdValue = $editionIdValue -replace "Server", ""

        # Get OS details using Get-CimInstance because the registry key for Name is not always correct with Windows 11
        $osDetails = Get-CimInstance -ClassName Win32_OperatingSystem
        $nameValue = $osDetails.Caption

        # Get architecture details of the OS (not the processor)
        $architecture = $osDetails.OSArchitecture

        # Normalize architecture
        if ($architecture -match "(?i)32") {
            $architecture = "x32"
        } elseif ($architecture -match "(?i)64" -and $architecture -match "(?i)ARM") {
            $architecture = "ARM64"
        } elseif ($architecture -match "(?i)64") {
            $architecture = "x64"
        } else {
            $architecture = "Unknown"
        }

        # Get OS version details (as version object)
        $versionValue = [System.Environment]::OSVersion.Version

        # Determine product type
        # Reference: https://learn.microsoft.com/en-us/dotnet/api/microsoft.powershell.commands.producttype?view=powershellsdk-1.1.0
        if ($osDetails.ProductType -eq 1) {
            $typeValue = "Workstation"
        } elseif ($osDetails.ProductType -eq 2 -or $osDetails.ProductType -eq 3) {
            $typeValue = "Server"
        } else {
            $typeValue = "Unknown"
        }

        # Extract numerical value from Name
        $numericVersion = ($nameValue -replace "[^\d]").Trim()

        # Create and return custom object with the required properties
        $result = [PSCustomObject]@{
            Name           = $nameValue
            ReleaseId      = $releaseIdValue
            DisplayVersion = $displayVersionValue
            Type           = $typeValue
            NumericVersion = $numericVersion
            EditionId      = $editionIdValue
            Version        = $versionValue
            Architecture   = $architecture
        }

        return $result
    } catch {
        Write-Error "Unable to get OS version details.`nError: $_"
        exit 1
    }
}

function Sleep-Random {
    param (
        [int]$MaximumSeconds = 300
    )
    if ($RandomDelay -eq "true") {
        $RandomSleep = Get-Random -Maximum $MaximumSeconds
        Write-Host "Sleeping for $RandomSleep seconds"
        Start-Sleep -Seconds $RandomSleep
    }
    else {
        Write-Host "Random delay is not enabled. Skipping sleep."
    }
}

# INSTALL THE RUNASUSERMODULE

# Check if the module is already installed 
if (Get-Module -Name RunAsUser -ListAvailable) {
    Write-Host "RunAsUser Module is already installed; skipping install"
}
else {
    $toolsDirectory = "C:\Program Files\Green Mountain IT Solutions\Tools"
    if (-not (Test-Path -Path $toolsDirectory -PathType Container)) {
        New-Item -Path $toolsDirectory -ItemType Directory -Force | Out-Null
    }

    $moduleURL = "https://github.com/KelvinTegelaar/RunAsUser/archive/refs/heads/master.zip"
    $moduleDownloadPath = Join-Path -Path $toolsDirectory -ChildPath "RunAsUser.zip"

    if (-not (Test-Path $moduleDownloadPath)) {
        $ProgressPreference = "SilentlyContinue"
        #Write-Host -Message "Downloading to $moduleDownloadPath"
        Invoke-WebRequest -Uri $moduleURL -OutFile $moduleDownloadPath
    }
    else {
        #Write-Host "Found $moduleDownloadPath already exists; skipping download"
    }

    # Unzip
    #Write-Host "Extracting archive to $toolsDirectory"
    Expand-Archive -Path $moduleDownloadPath -DestinationPath $toolsDirectory -Force

    # Import the Module (Manual copy)
    $modulesPath = "C:\Program Files\WindowsPowerShell\Modules"

    #Write-Host -Message "Manually copying module to $modulesPath and importing it."
    Copy-Item -Path "$toolsDirectory\RunAsUser-master" -Destination $modulesPath\RunAsUser -Recurse -Force
}
Import-Module -Name "RunAsUser" 

## MAIN SCRIPT ACTION

$osInfo = Get-OSInfo
$osInfo | Format-List

$currentBuild = $osInfo.Version.Build
$currentName = $osInfo.Name
$currentDisplayVersion = $OSInfo.DisplayVersion


# Alert Messages
$AlertCategory = "Windows OS Version"
$AlertBody = "This machine is running an unsupported operating system build version: $currentName $currentDisplayVersion . You should upgrade to the latest."


# Windows 10 Checks
if ($osInfo.NumericVersion -eq "10") {
    Write-Host "WARNING: Unsupported operating system version detected!"
    
    # Grace period for new clients - check if Syncro was installed less than 60 days ago. If so, don't show alerts.
    $syncroFolder = "C:\Program Files\RepairTech\Syncro"
    $creationTime = (Get-Item $syncroFolder).CreationTime
    $threshold = (Get-Date).AddDays(-60)
    if ($creationTime -gt $threshold) {
        Write-Output "Syncro was installed less than 60 days ago. Skipping Windows 10 alerts."
    }
    else { # not in grace period, show alerts
        if ($null -ne $env:SyncroModule) {
            Rmm-Alert -Category $AlertCategory -Body $AlertBody
        }
    
        # Display Windows 10 Warning Pop-Up
        if ($null -ne $env:SyncroModule) {
            Log-Activity -Message "Windows 10 End of Life alert was displayed." -EventName "Windows Upgrade Alert"
        }
        Sleep-Random
        Invoke-AsCurrentUser -ScriptBlock $Win10ScriptBlock -NoWait # Show the GUI Alert

    }

}

# Windows 11 Checks
elseif ($osInfo.NumericVersion -eq "11") {
    if ($currentBuild -lt $Windows11MinimumBuild) {
        Write-Host "WARNING: Unsupported operating system version detected!"
        if ($null -ne $env:SyncroModule) {
            Rmm-Alert -Category $AlertCategory -Body $AlertBody
        }    
    }        
    else {
        if ($currentBuild -eq "22631") { # Windows 11 23H2 warning
            $is23H2 = $true
        }
        Write-Host "This machine is running a supported operating system version."
        if ($null -ne $env:SyncroModule) {
            Close-Rmm-Alert -Category $AlertCategory -CloseAlertTicket "true"
        }
    }
}

# Display Warning for 23H2

if ($is23H2) {
        if (-not (Check-Laptop)) {
            Write-Host "This system is not a laptop. Self-service upgrade will not be offered."
        }
        else {
            Write-Host "This system is a laptop on version 23H2. Self-service upgrade will be offered."

        
            # Download latest self-service batch script
            $scriptURL = "https://raw.githubusercontent.com/greenmtnit/windows-scripts/refs/heads/main/Windows%2011%2024H2%20Self%20Service%20Upgrade/Windows24H2SelfServiceUpgrade.bat"
            $scriptPath = "C:\Program Files\Green Mountain IT Solutions\Scripts\Windows24H2SelfServiceUpgrade.bat"

            # Download the script
            $ProgressPreference = "SilentlyContinue"
            Remove-Item $scriptPath -ErrorAction SilentlyContinue # Delete if already exist
            Try {
                Write-Host "Downloading Windows24H2SelfServiceUpgrade.bat..."
                Invoke-WebRequest -Uri $scriptURL -OutFile $scriptPath -ErrorAction Stop
            } Catch {
                Write-Host "ERROR: Failed to download the file."
                Write-Host $_.Exception.Message
                Exit 1
            }

            # Display Warning Pop-up
            if ($null -ne $env:SyncroModule) {
                Log-Activity -Message "Windows 23H2 upgrade alert was displayed." -EventName "Windows Upgrade Alert"
            }   
            # Random Delay to avoid all users getting notified at the same time
            Sleep-Random
            Invoke-AsCurrentUser -ScriptBlock $23H2ScriptBlock -NoWait # Show the GUI Alert
        }
}
