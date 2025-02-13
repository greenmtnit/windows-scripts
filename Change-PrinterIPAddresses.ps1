<#
.SYNOPSIS
    Updates IP addresses of locally added printers.

.DESCRIPTION
    This script defines old and new IP addresses for a list of printers, then loops through each old IP address to find printers using it.
    For each printer, it creates a new printer port with the new IP address and assigns the printer to this new port.
    If a port with the new IP address already exists, it appends a numeral to the port name to ensure uniqueness.

.PARAMETER oldIPs
    An array of old IP addresses to be updated.

.PARAMETER newIPs
    An array of new IP addresses to replace the old ones.

.EXAMPLE
    .\Update-PrinterIPs.ps1

.NOTES
    Author: Timothy West
    Date: 2025-02-13
#>

# CHANGE THESE TO MATCH YOUR PRINTERS
# Define the old and new IP addresses
$oldIPs = @("10.1.10.29", "10.1.10.200", "10.1.10.135", "10.1.10.14")
$newIPs = @("10.138.10.50", "10.138.10.51", "10.138.10.52", "10.138.10.53")

# Loop through each old IP address
for ($i = 0; $i -lt $oldIPs.Length; $i++) {
    $oldIP = $oldIPs[$i]
    $newIP = $newIPs[$i]

    # Get printers using the old IP address
    $printers = Get-CimInstance -Query "SELECT * FROM Win32_Printer WHERE PortName LIKE '%$oldIP%'"

    foreach ($printer in $printers) {
        # Create a new printer port with the new IP address
        $portName = "$newIP"
        if (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
          Write-Host "Port called $portName already exists! Will attempt to add numeral to port name, e.g. _1"
          $i=0
          while (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
            $i+=1
            $portName = $newIP+"_"+$i
          }
        }
        Add-PrinterPort -Name $portName -PrinterHostAddress $newIP

        # Assign the printer to the new port
        Set-Printer -Name $printer.Name -PortName $portName

        Write-Host "Updated printer '$($printer.Name)' to use new IP address '$newIP'"
    }
}