# List of service names
$ServiceNames = @('IDEXXApplicationServer', 'IDEXXLabsServer')

# loop through and check each service individually
foreach ($ServiceName in $ServiceNames) {
    $ArrService = Get-Service -Name $ServiceName
    # check if the service is started
    while ($arrService.Status -ne 'Running') {
        # start the service
        Start-Service $ServiceName
        # give it some time to allow the service to actually start before checking agian
        Start-Sleep -Seconds 20
        $ArrService.Refresh()
    }
}
