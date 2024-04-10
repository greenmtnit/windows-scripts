#####################################################################
$BackupDriver = $true
#####################################################################

if (-not (Get-Module PSWriteHTML)){
    Install-Module -Name PSWriteHTML -AllowClobber -Force
}

Import-Module -Name PSWriteHTML
Import-Module -Name PrintManagement

# Get current timestamp for backup directory
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDirectory = "C:\!TECH\PrinterBackup_$Timestamp"

# Create the backup directory
if (-Not (Test-Path $BackupDirectory -ErrorAction SilentlyContinue)) {
    New-Item $BackupDirectory -ItemType Directory | Out-Null
}

$PrinterList = Get-Printer

foreach ($Printer in $PrinterList) {
    $PrinterConfig = Get-PrintConfiguration -PrinterName $printer.Name
    $PortConfig = Get-PrinterPort -Name $printer.PortName
    $PrinterProperties = Get-PrinterProperty -PrinterName $printer.Name

    if ($BackupDriver) {
        $Driver = Get-PrinterDriver -Name $printer.DriverName | ForEach-Object { $_.InfPath; $_.ConfigFile; $_.DataFile; $_.DependentFiles } | Where-Object { $_ -ne $null }
        $BackupPath = New-Item -Path "$ENV:TEMP\$($printer.name)" -ItemType Directory -Force
        $Driver | ForEach-Object { Copy-Item -Path $_ -Destination "$ENV:TEMP\$($printer.name)" -Force }
        Compress-Archive -Path "$ENV:TEMP\$($printer.name)" -DestinationPath "$BackupDirectory\$($printer.name).zip" -Force
        Remove-Item "$ENV:TEMP\$($printer.name)" -Force -Recurse
    }

    New-HTML {
        New-HTMLTab -Name $printer.name {
            New-HTMLSection -Invisible {
                New-HTMLSection -HeaderText 'Configuration' {
                    New-HTMLTable -DataTable $PrinterConfig
                }
            }
            New-HTMLSection -Invisible {
                New-HTMLSection -HeaderText "Driver Name" {
                    New-HTMLTable -DataTable "Printer Driver: $($printer.DriverName)"
                }
            }
            New-HTMLSection -Invisible {
                New-HTMLSection -HeaderText "Port Config" {
                    New-HTMLTable -DataTable $PortConfig
                }
                New-HTMLSection -HeaderText "Printer Properties" {
                    New-HTMLTable -DataTable $PrinterProperties
                }
            }
        }
    } -FilePath "$BackupDirectory\$($Printer.name) PrinterDocumentation.html" -Online
}

#Create README
$readme = "$BackupDirectory\README.txt"
New-Item -Path $readme | Out-Null
Add-Content -Path $readme -Value "Printer backup created with this script: https://github.com/greenmtnit/windows-scripts/blob/main/Backup-PrinterSettings.ps1"

Write-Host "Backed up printer config to $BackupDirectory"