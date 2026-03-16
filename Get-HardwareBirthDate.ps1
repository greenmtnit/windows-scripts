<# 
    Get-HardwareBirthDate.ps1
    
    OLD VERSION - HAS BEEN UPDATED TO USE SYNCRO WARRANTY TRACKING
    
    Determines birth date of a computer asset.

    Uses Dell and Lenovo APIs to look up the warranty start date for the asset.
    For other manufacturers, uses fallback methods based on BIOS release date and the OS install date.
    Dates generated with fallback methods are appended with (Estimated)

    Writes the output to a Syncro asset custom field named "Birth Date".
    
    Syncro Script Variables:
    $existingBirthDate - Existing Syncro platform asset custom field "Birth Date"
    
    Adding Dell API Keys:
    $DellClientID - Dell API key ID from Dell Tech Direct (https://tdm.dell.com/service-page/api)
    $DellClientSecret - Dell API Secret from Dell Tech Direct
    
#>

if ($null -ne $env:SyncroModule) { Import-Module $env:SyncroModule -DisableNameChecking }

function Check-VM {
    $model = Get-CimInstance Win32_ComputerSystem | select Model
    if ($model -match "virtual") {
        return $true
    }
    return $false
}

# Check if this is a VM
if (Check-VM) {
    $warStartDate = "N/A (VM)"
}

else { # Not a VM

    $ServiceTag = Get-CimInstance Win32_BIOS | Select-Object -ExpandProperty SerialNumber
    $Mfg = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
    $Lenovo = "LENOVO*"
    $Dell = "DELL*"
    $today = Get-Date -Format yyyy-MM-dd

    switch -Wildcard ($Mfg) {
        $Lenovo {
            $APIURL = "https://pcsupport.lenovo.com/us/en/api/v4/mse/getproducts?productId=$ServiceTag"
            $WarReq = Invoke-RestMethod -Uri $APIURL -Method Get

            if ($WarReq.id) {
                $APIURL = "https://pcsupport.lenovo.com/us/en/products/$($WarReq.id)/warranty"
                $WarReq = Invoke-RestMethod -Uri $APIURL -Method Get
                $search = $WarReq | Select-String -Pattern "var ds_warranties = window.ds_warranties \|\| (.*);[\r\n]*"
                $jsonWarranties = $search.Matches.Groups[1].Value | ConvertFrom-Json
            }

            if ($jsonWarranties.BaseWarranties) {
                $warfirst = $jsonWarranties.BaseWarranties | Sort-Object -Property [DateTime]End | Select-Object -First 1
                $warlatest = $jsonWarranties.BaseWarranties | Sort-Object -Property [DateTime]End | Select-Object -Last 1
                $WarObj = [PSCustomObject]@{
                    'Serial' = $jsonWarranties.Serial
                    'Warranty Product name' = $jsonWarranties.ProductName
                    'StartDate' = [DateTime]$warfirst.Start
                    'EndDate' = [DateTime]$warlatest.End
                    'Warranty Status' = $warlatest.StatusV2
                    'Client' = $Client
                    'Product Image' = $jsonWarranties.ProductImage
                    'Warranty URL' = $jsonWarranties.WarrantyUpgradeURLInfo.WarrantyURL
                }
                $warStartDate = [DateTime]$warfirst.Start
                $warStartDate = $warStartDate.ToShortDateString()
                $warEndDate = [DateTime]$warlatest.End
                $warEndDate = $warEndDate.ToShortDateString()
            } 
            else {
                $WarObj = [PSCustomObject]@{
                    'Serial' = $SourceDevice
                    'Warranty Product name' = 'Could not get warranty information'
                    'StartDate' = $null
                    'EndDate' = $null
                    'Warranty Status' = 'Could not get warranty information'
                    'Client' = $Client
                    'Product Image' = ""
                    'Warranty URL' = ""
                }
                $warStartDate = $null
                $warEndDate = $null
            }
        }
        $Dell {
            $AuthURI = "https://apigtwb2c.us.dell.com/auth/oauth/v2/token"
            if ($Global:TokenAge -lt (Get-Date).AddMinutes(-55)) { $global:Token = $null }
            if ($null -eq $global:Token) {
                $OAuth = "$DellClientID`:$DellClientSecret"
                $Bytes = [System.Text.Encoding]::ASCII.GetBytes($OAuth)
                $EncodedOAuth = [Convert]::ToBase64String($Bytes)
                $HeadersAuth = @{ "Authorization" = "Basic $EncodedOAuth" }
                $AuthBody = 'grant_type=client_credentials'
                $AuthResult = Invoke-RestMethod -Method Post -Uri $AuthURI -Body $AuthBody -Headers $HeadersAuth
                $global:Token = $AuthResult.access_token
                $Global:TokenAge = Get-Date
            }

            $HeadersReq = @{ "Authorization" = "Bearer $global:Token" }
            $ReqBody = @{ servicetags = $ServiceTag }
            $WarReq = Invoke-RestMethod -Uri "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements" -Headers $HeadersReq -Body $ReqBody -Method Get -ContentType "application/json"
            $warlatest = $WarReq.entitlements.enddate | Sort-Object | Select-Object -Last 1
            $WarrantyState = if ($warlatest -le $today) { "Expired" } else { "OK" }
            if ($WarReq.entitlements.serviceleveldescription) {
                $WarObj = [PSCustomObject]@{
                    'Serial' = $SourceDevice
                    'Warranty Product name' = $WarReq.entitlements.serviceleveldescription -join "`n"
                    'StartDate' = (($WarReq.entitlements.startdate | Sort-Object -Descending | Select-Object -Last 1) -split 'T')[0]
                    'EndDate' = (($WarReq.entitlements.enddate | Sort-Object | Select-Object -Last 1) -split 'T')[0]
                    'Warranty Status' = $WarrantyState
                    'Client' = $Client
                }
                $warStartDate = (($WarReq.entitlements.startdate | Sort-Object -Descending | Select-Object -Last 1) -split 'T')[0]
                $warEndDate = (($WarReq.entitlements.enddate | Sort-Object | Select-Object -Last 1) -split 'T')[0]
            } 
            else {
                $WarObj = [PSCustomObject]@{
                    'Serial' = $SourceDevice
                    'Warranty Product name' = 'Could not get warranty information'
                    'StartDate' = $null
                    'EndDate' = $null
                    'Warranty Status' = 'Could not get warranty information'
                    'Client' = $Client
                }
                $warStartDate = $null
                $warEndDate = $null
            }
        }
        default {
            $warStartDate = $null
            $warEndDate = $null
        }
    }

    # If lookup fails, use fallback methods
    if ($warStartDate -eq $null) {
        # Check BIOS release date
        $biosDate = Get-Date (Get-CimInstance -Class Win32_BIOS).ReleaseDate -Format "MM/dd/yyyy"
        
        # Estimate OS install Date by checking the date of the System Volume Information folder
        $osInstallDate = Get-Date (Get-CimInstance Win32_OperatingSystem).InstallDate -Format "MM/dd/yyyy"

        # Use the older of the two as a best guess for age
        if ($biosDate -lt $osInstallDate) {
            $warStartDate = $biosDate
        } else {
            $warStartDate = $osInstallDate
        }
        $warStartDate += " (Estimated)"
    }


    # SANITY CHECK - make sure we're not overwriting with a newer date

    # Check if existing date is present
    if ($existingBirthDate -ne "" -and $existingBirthDate -ne $null -and (Test-Path variable:\existingBirthDate)) {
      
        # Remove "(Estimated)" from the existing fields, if present - strip out just the date

        $pattern = "(\d{2}/\d{2}/\d{4})"
        if ($existingBirthDate -match $pattern) {
            $dateOnly = $matches[1]
            $existingDate = $dateOnly
        }
        if ($warStartDate -match $pattern) {
            $dateOnly = $matches[1]
            $newDate = $dateOnly
        }   
        
        $existingDate = Get-Date $existingDate
        $newDate = Get-Date $newDate
            
        if ($newDate -gt $existingDate) {
            Write-Host "Error! Detected birth date newer than the as existing field. Will not overwrite."
            Exit 0
        }
        if ($newDate -eq $existingDate) {
            # Dates are the same. No update needed.
            Exit 0
        }
    }

}

if (Get-Module | Where-Object { $_.ModuleBase -match 'Syncro' }) {
    Set-Asset-Field -Name "Birth Date" -Value "$warStartDate"
}
else {
    Write-Host $warStartDate
}