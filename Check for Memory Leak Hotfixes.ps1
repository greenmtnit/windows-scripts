if ( Get-WmiObject -Query "select * from Win32_OperatingSystem where ProductType='2'" ) { 
    # Define an array of options
    $options = @("5035849", "5035855", "5035857")

    # Get the list of installed Windows updates
    $updates = Get-WmiObject -Class Win32_QuickFixEngineering

    # Iterate through each update and check if any of the options are present in the HotFixID property
    foreach ($update in $updates) {
        foreach ($option in $options) {
            if ($update.HotFixID -eq "KB$($option)") {
                Write-Output "Found memory leak update $option"
                try {
                    wusa /uninstall /kb:$option
                    Write-Output "Succesfully uninstalled $option"
                } catch {
                    Write-Output "Errors during uninstall of $option"
                }
            }
        }
    }
    exit 1
} else { 
    Write-Host "Not a domain controller"
    exit 0 
}


