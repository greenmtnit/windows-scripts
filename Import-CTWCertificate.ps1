<#
  Import-CTWCertificate.ps1
  
  Automates RDS certificate deployment with Certify the Web.
  
  https://certifytheweb.com/
  
  Adapted from: http://web.archive.org/web/20210121104409/https://diverse.services/secure-an-rd-gateway-using-lets-encrypt/
    
#>


param($result)

Set-Alias ps64 "$env:C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Force

ps64 -args $result -command {

   $result = $args[0]

   $pfxpath = $result.ManagedItem.CertificatePath

   Import-Module RemoteDesktop
   
   Stop-Service TSGateway -Force

   Set-RDCertificate -Role RDPublishing -ImportPath $pfxpath -Force

   Set-RDCertificate -Role RDWebAccess -ImportPath $pfxpath -Force
   
   Set-RDCertificate -Role RDRedirector -ImportPath $pfxpath -Force

   # -ErrorAction added to workaround an issue with below cmdlet timing out. This may not be needed on all deployments.
   Set-RDCertificate -Role RDGateway -ImportPath $pfxpath -Force -ErrorAction SilentlyContinue
   
   Start-Service TSGateway

}