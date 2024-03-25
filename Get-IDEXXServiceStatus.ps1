$ServiceName = 'NAME'
$arrService = Get-Service -Name $ServiceName

# Repeat this process until the service starts running
while ($arrService.Status -ne 'Running')
{
    # Start the service
    Start-Service $ServiceName
    # Wait a bit before retrying the while loop
    Start-Sleep -seconds 20
    $arrService.Refresh()

}