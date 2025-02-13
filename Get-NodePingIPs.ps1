# Define the URL and the output file path
$url = "https://nodeping.com/content/txt/pinghosts.txt"
$outputFilePath = "C:\!TECH\nodeping-ips.txt"

# Download the content from the URL
$content = Invoke-WebRequest -Uri $url -UseBasicParsing

# Extract the IP addresses using a regular expression
$ips = $content.Content | Select-String -Pattern '\d{1,3}(\.\d{1,3}){3}' -AllMatches | ForEach-Object { $_.Matches.Value }

# Write the IP addresses to the output file
$ips | Out-File -FilePath $outputFilePath -Encoding UTF8

# Output a message indicating that the process is complete
Write-Host "IP addresses have been extracted and saved to $outputFilePath"

$answer = Read-Host "View the file now? [y/n]"

while ($answer -ne 'y' -and $answer -ne 'y') {
    $answer = Read-Host 'Please enter [y/n]'
}

if ($answer -eq 'y') {
    Invoke-Item -Path $outputFilePath
} elseif ($answer -eq 'n') {
    exit
}
