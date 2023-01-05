# https://github.com/tonyjobson/ping-logger
# This power shell script is designed to be used to track the latency between a server and a specific end point over Time.
# This is formatted for easy graphing in Excel. 
# The typical use case is to track intermittent network issues to help track down saturated switch ports or firewall capacity issues.
# Resolution is roughly 1 second rate. This can lead to large files if the script is left running for several days. 
# Approximatly 2MB of log file growth per day should be expected.
# I recommend enabling NTFS compression on the folder it's run from to prevent unecassary file growth.
# Ping Timeouts will be recorded as 4001ms which is easy to spot in a graph as a dropped packet (Time out)
# The filename output is formatted so the same script can be quickly started on multiple servers and all log files imported to the same folder for analysis without filename conflict. 


<#
CSV format:
Source,Destination,Date,Time,ResponseTime
8.8.8.8,2018/09/18,11:17:00,6
8.8.8.8,2018/09/18,11:17:01,8
8.8.8.8,2018/09/18,11:17:02,11
8.8.8.8,2018/09/18,11:17:03,7
8.8.8.8,2018/09/18,11:17:04,11
8.8.8.8,2018/09/18,11:17:21,10
8.8.8.8,2018/09/18,11:17:26,4001
8.8.8.8,2018/09/18,11:17:27,5
8.8.8.8,2018/09/18,11:17:28,5
#>




#Timestamp.
$DateStart = Get-Date -format yyyy-MM-dd;
$TimeStart = Get-Date -format HH.mm.ss


#let's ask them where to ping to start with
$Destination = Read-Host -Prompt "Hostname/IP to ping? Enter for 8.8.8.8 as a default"
if ($Destination -eq '') {$Destination = '8.8.8.8'}



#Log Files: Main log (all pings) and Fail log (errors only)
$DefaultMainLogName = "MainPingLog-$Destination-$DateStart-$TimeStart.CSV"
$MainLogName = read-host -Prompt "Where should the main log be (all results)? Default $DefaultMainLogName"
if ($MainLogName -eq ''){$MainLogName = $DefaultMainLogName}

$DefaultFailLogName = "FailPingLog-$Destination-$DateStart-$TimeStart.CSV"
$FailLogName = read-host -Prompt "Where should we log FAILURES to? Default $DefaultFailLogName"
if ($FailLogName -eq ''){$FailLogName = $DefaultFailLogName}


#Set up CSV files
Add-Content ./$MainLogName "Destination,Date,Time,ResponseTime,Status";
Add-Content ./$FailLogName "Destination,Date,Time,ResponseTime,Status";


#Pretend start time is a successful ping, to calculate seconds since successful response in case we never get a response.
$LastSuccessful = Get-Date


while($true)
{

        $Result = Test-Connection $Destination -Count 1 -ErrorAction SilentlyContinue

        if ($Result-eq $null) 
            {
                #PING FAILED
                #If we get here it means we had a timeout or failure on the ping.
                
                #Work out how long since a last sucsessful ping.
                $TimeSpan = [DateTime](Get-Date) - [DateTime]$LastSuccessful

                $TotalSeconds = $TimeSpan.TotalSeconds
                
                #Give the user something to see for the failures.
                $TimeNow = Get-Date -format HH:mm.ss
                Write-host "$TimeNow : Last Ping timed out. Failure logged. $TotalSeconds since last success"

 
                #Log the failure to both main log and fail log.
                $Date = Get-Date -format yyyy-MM-dd;
                $Time = Get-Date -format HH:mm:ss
                Add-Content ./$MainLogName "$Destination,$Date,$Time,4001,Failed";
                Add-Content ./$FailLogName "$Destination,$Date,$Time,4001,Failed";

                #incase the nic goes down we need a delay here too. means that our highest resolution of outage is 5 seconds.
                Start-Sleep -Seconds 1
            }

        else
            {
                #PING SUCCESS
                #if we get here then it means we got a response to the ping
                
                #Update the time since sucsessful in case the next ping fails.
                $LastSuccessful = Get-Date
                
                $TimeNow = Get-Date -format HH:mm:ss
                $PingTime = $Result.ResponseTime
                Write-host "$TimeNow : Ping Successful. Reponse Time = $PingTime"

                
                 #Log to the main log.
                $Date = Get-Date -format yyyy-MM-dd;
                $Time = Get-Date -format HH:mm:ss;
                 Add-Content ./$MainLogName "$Destination,$Date,$Time,$PingTime,Success";

                #pause for 1 second to prevent low latency loop being too quick.
                Start-Sleep -Seconds 1

                #set $Result to null in case the ping starts to fail or 
            }


}