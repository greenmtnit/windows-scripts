<#
.SYNOPSIS
    Weekly technician review from Syncro, for the previous calendar week (Sunday-Saturday):
      1. Non-Project tickets opened vs. resolved, and the kill rate (resolved / opened)
      2. Non-Project tickets created or resolved that week with more than 1 hour of time logged

.DESCRIPTION
    Read-only: this script only makes GET requests. It never creates, edits,
    or deletes anything in Syncro.

    Tickets whose Issue Type (problem_type) is "Projects" are excluded from everything.

    The week runs from Sunday 12:00 AM through Saturday 11:59 PM, in this computer's
    local time. By default it's the most recent completed week, so running it on
    Wednesday, Nov 11 checks Sunday, Nov 1 through Saturday, Nov 7.

    Outputs are saved in a dated subfolder (yyyyMMdd, the Sunday that starts the
    review week) inside -OutFolder:
      Syncro-WeeklyReview-<week start>-summary.txt   the item 1 numbers
      Syncro-WeeklyReview-<week start>-over-1hr.csv  the item 2 ticket list

    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Subdomain
    Your Syncro subdomain (the "yourcompany" part of yourcompany.syncromsp.com).
    Defaults to 'greenmtnit'.

.PARAMETER WeekOf
    Optional. Any date inside the Sunday-Saturday week you want to review.
    Leave it out to review the most recent completed week.

.PARAMETER HourThreshold
    Optional. Item 2 lists tickets with MORE than this many hours logged. Default 1.

.PARAMETER OutFolder
    Optional. The folder that holds the dated review folders. Default:
    %USERPROFILE%\Green Mountain IT Solutions, LLC\Main Shared - Documents\Service Delivery\Weekly Tech Review
    If it doesn't exist, the script asks for a different path before doing anything else.

.PARAMETER ApiKey
    Syncro API token. If omitted, uses $env:SYNCRO_API_KEY, or prompts securely.

.EXAMPLE
    $env:SYNCRO_API_KEY = 'paste-token-here'
    .\Syncro-WeeklyReview.ps1

.EXAMPLE
    .\Syncro-WeeklyReview.ps1 -WeekOf 2026-10-28
#>
[CmdletBinding()]
param(
    [string]$Subdomain = 'greenmtnit',
    [datetime]$WeekOf,
    [double]$HourThreshold = 1,
    [string]$OutFolder = (Join-Path $env:USERPROFILE 'Green Mountain IT Solutions, LLC\Main Shared - Documents\Service Delivery\Weekly Tech Review'),
    [string]$ApiKey = $env:SYNCRO_API_KEY
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $ApiKey) {
    $secure = Read-Host 'Syncro API token' -AsSecureString
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$BaseUrl = "https://$Subdomain.syncromsp.com/api/v1"
$Headers = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json' }

# ---------------------------------------------------------------------------
# Work out the review week (Sunday 12:00 AM through Saturday 11:59 PM)
# ---------------------------------------------------------------------------

if ($PSBoundParameters.ContainsKey('WeekOf')) {
    $weekStartDate = $WeekOf.Date.AddDays(-[int]$WeekOf.DayOfWeek)
}
else {
    $today = (Get-Date).Date
    $weekStartDate = $today.AddDays(-[int]$today.DayOfWeek - 7)
}
$WeekStart = [DateTimeOffset]$weekStartDate
$WeekEnd   = $WeekStart.AddDays(7)   # exclusive: the following Sunday at 12:00 AM
$WeekLabel = '{0:dddd, MMM d} - {1:dddd, MMM d, yyyy}' -f $weekStartDate, $weekStartDate.AddDays(6)

# Confirm the output folder exists before doing any API work
while (-not (Test-Path -LiteralPath $OutFolder -PathType Container)) {
    Write-Warning "Folder not found: $OutFolder"
    $answer = Read-Host 'Enter a different folder path (or press Enter to cancel)'
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'No output folder chosen. Exiting.' }
    $OutFolder = $answer.Trim().Trim('"')
}
$OutFolder = Join-Path $OutFolder $weekStartDate.ToString('yyyyMMdd')
New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Invoke-Syncro {
    param([string]$Path, [hashtable]$Query = @{})

    $qs = ($Query.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    $uri = if ($qs) { "$BaseUrl$($Path)?$qs" } else { "$BaseUrl$($Path)" }
    Write-Verbose "GET $uri"

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
            Start-Sleep -Milliseconds 350   # stays under Syncro's 180 requests/minute limit
            return $result
        }
        catch {
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($status -eq 429 -and $attempt -lt 5) {
                Write-Warning "Rate limited; waiting $(15 * $attempt) seconds..."
                Start-Sleep -Seconds (15 * $attempt)
                continue
            }
            throw
        }
    }
}

function ConvertTo-Date($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [datetime]) { return [DateTimeOffset]$value }   # PS7 auto-converts ISO dates
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return $null }
    return [DateTimeOffset]::Parse([string]$value, [Globalization.CultureInfo]::InvariantCulture)
}

function Test-InWeek($date) {
    return ($null -ne $date -and $date -ge $WeekStart -and $date -lt $WeekEnd)
}

function Get-TotalPages($resp) {
    if ($resp.meta -and $resp.meta.total_pages) { return [int]$resp.meta.total_pages }
    return 1
}

function Format-Local($date) {
    if ($null -eq $date) { return '' }
    return $date.LocalDateTime.ToString('yyyy-MM-dd HH:mm')
}

# ---------------------------------------------------------------------------
# 1. Tech names (optional: falls back to the names on the tickets if this fails)
# ---------------------------------------------------------------------------

Write-Host "Reviewing week: $WeekLabel" -ForegroundColor Cyan
Write-Host "Loading Syncro users..."
$UserNames = @{}
try {
    $page = 1
    do {
        $resp = Invoke-Syncro '/users' @{ page = $page }
        foreach ($u in $resp.users) {
            if ($u -is [array]) {
                $UserNames[[string]$u[0]] = [string]$u[1]
            }
            else {
                $name = $u.full_name
                if (-not $name) { $name = ("{0} {1}" -f $u.firstname, $u.lastname).Trim() }
                $UserNames[[string]$u.id] = $name
            }
        }
        $totalPages = Get-TotalPages $resp
        $page++
    } while ($page -le $totalPages)
}
catch {
    Write-Warning "Couldn't load the user list ($($_.Exception.Message)). Using tech names from the tickets instead."
}

function Get-UserName($id, $fallbackUser) {
    if ($null -ne $id -and [string]$id -ne '' -and $UserNames.ContainsKey([string]$id)) {
        return $UserNames[[string]$id]
    }
    if ($fallbackUser -and $fallbackUser.full_name) { return $fallbackUser.full_name }
    if ($null -ne $id -and [string]$id -ne '') { return "User $id" }
    return $null
}

# ---------------------------------------------------------------------------
# 2. Pull every ticket updated since the week started. Creating or resolving a
#    ticket updates it, so this catches everything opened or resolved that week.
# ---------------------------------------------------------------------------

Write-Host "Loading tickets..."
$candidates = @{}
$page = 1
do {
    $resp = Invoke-Syncro '/tickets' @{ since_updated_at = $WeekStart.UtcDateTime.ToString('o'); page = $page }
    foreach ($t in $resp.tickets) { $candidates[[string]$t.id] = $t }   # keyed by ID to drop duplicates
    $totalPages = Get-TotalPages $resp
    Write-Progress -Activity 'Listing tickets' -Status "Page $page of $totalPages" -PercentComplete ([math]::Min(100, 100 * $page / [math]::Max(1, $totalPages)))
    $page++
} while ($page -le $totalPages)
Write-Progress -Activity 'Listing tickets' -Completed

# ---------------------------------------------------------------------------
# 3. Item 1: count non-Project tickets opened and resolved during the week
# ---------------------------------------------------------------------------

$openedCount   = 0
$resolvedCount = 0
$fallbackCount = 0
$inWeek = New-Object System.Collections.Generic.List[object]

foreach ($t in $candidates.Values) {
    if (([string]$t.problem_type).Trim() -eq 'Projects') { continue }

    $created  = ConvertTo-Date $t.created_at
    $resolved = ConvertTo-Date $t.resolved_at

    # Fallback only if Syncro doesn't send resolved_at at all
    if (-not $resolved -and $t.status -eq 'Resolved' -and -not ($t.PSObject.Properties.Name -contains 'resolved_at')) {
        $resolved = ConvertTo-Date $t.updated_at
        $fallbackCount++
    }

    $wasOpened   = Test-InWeek $created
    $wasResolved = Test-InWeek $resolved

    if ($wasOpened)   { $openedCount++ }
    if ($wasResolved) { $resolvedCount++ }

    if ($wasOpened -or $wasResolved) {
        $inWeek.Add([pscustomobject]@{
            Ticket = $t; Created = $created; Resolved = $resolved
            Opened = $wasOpened; Closed = $wasResolved
        })
    }
}

if ($fallbackCount -gt 0) {
    Write-Warning "$fallbackCount resolved ticket(s) had no resolved_at date, so their last-updated date was used instead. Their resolved counts may be off."
}

$killRate = if ($openedCount -gt 0) {
    '{0}%' -f [math]::Round(100 * $resolvedCount / $openedCount, 1)
} else { 'N/A (no tickets opened)' }

# ---------------------------------------------------------------------------
# 4. Item 2: total the logged time on each of those tickets
# ---------------------------------------------------------------------------

Write-Host "Checking logged time on $($inWeek.Count) ticket(s)..."
$overThreshold = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($m in $inWeek) {
    $i++
    $t = $m.Ticket
    Write-Progress -Activity 'Reading timer entries' -Status "Ticket #$($t.number) ($i of $($inWeek.Count))" -PercentComplete (100 * $i / [math]::Max(1, $inWeek.Count))

    $detail = (Invoke-Syncro "/tickets/$($t.id)").ticket
    $timers = @($detail.ticket_timers | Where-Object { $null -ne $_ })

    $totalSec    = 0.0
    $billableSec = 0.0
    $loggedBy    = New-Object System.Collections.Generic.List[string]

    foreach ($tm in $timers) {
        $sec = 0.0
        if ($null -ne $tm.active_duration -and [string]$tm.active_duration -ne '') {
            $sec = [double]$tm.active_duration
        }
        else {
            $start = ConvertTo-Date $tm.start_time
            $end   = ConvertTo-Date $tm.end_time
            if ($start -and $end) { $sec = ($end - $start).TotalSeconds }
        }
        $totalSec += $sec
        if ($tm.billable) { $billableSec += $sec }

        $who = Get-UserName $tm.user_id $null
        if ($who -and -not $loggedBy.Contains($who)) { $loggedBy.Add($who) }
    }

    if ($totalSec -le ($HourThreshold * 3600)) { continue }

    $customer = $t.customer_business_then_name
    if (-not $customer -and $t.customer) { $customer = $t.customer.business_then_name }

    $assigned = Get-UserName $t.user_id $t.user
    if (-not $assigned) { $assigned = 'Unassigned' }

    $activity = if ($m.Opened -and $m.Closed) { 'Opened & Resolved' } elseif ($m.Opened) { 'Opened' } else { 'Resolved' }

    $overThreshold.Add([pscustomobject][ordered]@{
        'Ticket #'       = $t.number
        'Customer'       = $customer
        'Subject'        = $t.subject
        'Issue Type'     = $t.problem_type
        'Status'         = $t.status
        'Assigned Tech'  = $assigned
        'This Week'      = $activity
        'Created'        = Format-Local $m.Created
        'Resolved'       = Format-Local $m.Resolved
        'Total Hours'    = [math]::Round($totalSec / 3600, 2)
        'Billable Hours' = [math]::Round($billableSec / 3600, 2)
        'Timer Entries'  = $timers.Count
        'Time Logged By' = ($loggedBy -join '; ')
    })
}
Write-Progress -Activity 'Reading timer entries' -Completed

# ---------------------------------------------------------------------------
# 5. Report and save
# ---------------------------------------------------------------------------

$stamp       = $weekStartDate.ToString('yyyy-MM-dd')
$summaryFile = Join-Path $OutFolder "Syncro-WeeklyReview-$stamp-summary.txt"
$csvFile     = Join-Path $OutFolder "Syncro-WeeklyReview-$stamp-over-$($HourThreshold)hr.csv"

$overThreshold = @($overThreshold | Sort-Object 'Total Hours' -Descending)

$summary = @"
Weekly Technician Review
Week: $WeekLabel
(Excludes tickets with Issue Type = Projects)

1. Tickets opened vs. resolved
   a. Opened:    $openedCount
   b. Resolved:  $resolvedCount
   c. Kill rate: $killRate  (resolved / opened)

2. Tickets created or resolved this week with more than $HourThreshold hour(s) logged: $($overThreshold.Count)
   See: $csvFile
"@

$summary | Set-Content -Path $summaryFile -Encoding UTF8
$overThreshold | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host $summary -ForegroundColor Green
if ($overThreshold.Count -gt 0) {
    $overThreshold | Format-Table 'Ticket #', 'Customer', 'Subject', 'Assigned Tech', 'This Week', 'Total Hours' -AutoSize | Out-String -Width 200 | Write-Host
}
Write-Host "Summary saved to: $summaryFile"