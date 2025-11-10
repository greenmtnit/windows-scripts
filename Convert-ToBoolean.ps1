# Function to handle Syncro's variables
function Convert-ToBoolean {
    <#
    .SYNOPSIS
        Converts string variables to true booleans. Meant for use with SyncroMSP, which doesn't support boolean script variables.

    .DESCRIPTION
        This function is designed to standardize text-based boolean values coming from systems such as SyncroMSP, 
        which do not support booleans for script variables. It interprets typical truthy and falsy string values 
        (such as "true", "yes", "1", "false", "no", "0") and returns proper boolean values ($true or $false). 

        If an unrecognized string is provided, the function throws an error to ensure script reliability 
        and prevent unintended logic errors in automation workflows.           
       
    .EXAMPLE 
        $UseBitlockerEncryption = ConvertTo-Boolean $UseBitlockerEncryption

        Converts a string variable $UseBitlockerEncryption with value "true" or "false" to a true boolean $true or $false
    #>
    
    param (
        [string]$value
    )
    switch ($value.ToLower()) {
        'true' { return $true }
        '1' { return $true }
        't' { return $true }
        'y' { return $true }
        'yes' { return $true }
        'false' { return $false }
        '0' { return $false }
        'f' { return $false }
        'n' { return $false }
        'no' { return $false }
        default { throw "Invalid boolean string: $value" }
    }
}