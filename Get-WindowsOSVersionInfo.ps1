<#
  Get-WindowsOSVersionInfo.ps1
  
  Gets Windows version, build number, and edition. 
  
  Also checks if Windows 10 or Windows 11 is running a supported version.
  If on an unsupported version, an RMM alert is generated in SyncroMSP.
  
  If the script detects Windows 10, a GUI pop-up will be displayed to the currently logged in user advising them of the upcoming Windows 10 EoL.
  
  Thanks to https://gist.github.com/asheroto/cfa26dd00177a03c81635ea774406b2b for Get-OSInfo function
  
#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

# VARIABLES - CHANGE THESE 

# Minimum Build Versions
# To get build numbers, see: https://en.wikipedia.org/wiki/Windows_11_version_history

# $Windows10MinimumBuild = "19045" # 22H2, EoL October 14, 2025
$Windows11MinimumBuild = "22631" # 23H2, EoL November 11, 2025
#$Windows11MinimumBuild = "26100" # 24H2, EoL October 13, 2026

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
    if ($null -ne $env:SyncroModule) {
        Rmm-Alert -Category $AlertCategory -Body $AlertBody
    }
}
    
# Display Warning Pop-up on Windows 10

################################################
# Start of RunAsUser $ScriptBlock

$ScriptBlock = {
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

# End of RunAsUser $ScriptBlock
################################################

$today = Get-Date

if ($null -ne $env:SyncroModule) {
    Log-Activity -Message "Windows 10 End of Life alert was displayed." -EventName "Windows Upgrade Alert"
}   
Invoke-AsCurrentUser -ScriptBlock $ScriptBlock -NoWait # Show the GUI Alert

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
        Write-Host "This machine is running a supported operating system version."
        if ($null -ne $env:SyncroModule) {
            Close-Rmm-Alert -Category $AlertCategory -CloseAlertTicket "true"
        }
    }
}