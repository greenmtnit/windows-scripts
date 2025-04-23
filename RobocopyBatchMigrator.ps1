<#
    Script Purpose:
    - Automates file/folder migration using Robocopy with customizable options.
    - Supports dry run mode (default) to simulate actions without making changes.
    - Prompts for user confirmation before running, unless -Force is specified.
    - Logs all Robocopy output to a timestamped file for auditing.
    - Allows easy configuration of Robocopy options and multiple migration jobs.
    - Excludes specified files and folders from migration.
    - Displays and executes each Robocopy command in sequence.

    Usage:
    - Run as-is for a dry run (no changes made).
    - Use -DryRun:$false to perform an actual migration.
    - Use -Force to skip confirmation prompt (use with caution).
    - Edit the $options array as needed with robocopy options
    - Edit the $commands arrays to run multiple migration jobs in one script.
#>


param (
    [switch]$DryRun = $true,
    # Run .\Do-RobocopyMigration.ps1 -DryRun:$false to do a live run
    
    [switch]$Force # Do not confirm. Dangerous!

)

$jobName = "Server_Migration" # Do not put spaces in the job name
$logPath = "C:\!TECH\robocopy_logs\$jobName$(Get-Date -Format yyyyMMdd_hhmmss).txt"

# Dry run check
if ($DryRun) {
    Write-Host "Notice: This is a dry run."
    $dryRunFlag = "/L"
}
else {
    Write-Host "This is a LIVE run, NOT a dry run!" -ForegroundColor Red -BackgroundColor White    
    $dryRunFlag = ""
}

# Confirmation
if (-not $Force) {
    do {
        $confirmation = Read-Host "Are you sure to run the job? Type 'YES' to proceed or 'N' to cancel"
        if ($confirmation -eq 'N') {
            Write-Output "Operation cancelled."
            exit
        }
    } while ($confirmation -ne 'YES')

    Write-Output "Confirmed. Proceeding with the operation!"
} else {
    Write-Output "Force parameter set. Proceeding with the operation."
}


# Robocopy options. Add or edit as you like
$options = @(
    "/E",                       # Copy subdirectories, including empty ones
    "/B",                       # Copy files in backup mode (uses BackupSemantics)
    "/COPY:DAT",                # Copy data, attributes, timestamps - NOTE: Excludes permissions
    "/PURGE",                   # DELETE destination files/folders that no longer exist in the source
    "/R:5",                     # Number of retries on failed copies
    "/W:5",                     # Wait time between retries
    "/MT:64",                   # Use multithreaded copies (value can be adjusted based on system resources)
    "/TEE",                     # Display output in the console window and log file
    "/LOG+:$logPath",           # Append log output to a file
    "/XD", "APPDATA", "TEST*",  # Example directory exclusions
	"/XF", "*.tmp", "*.pdf"     # Example file exclusions
    #"/V"                       # Produce verbose output
        # Next two options: together, /NFL and /NDL are the opposite of verbose - just print a summary.
    # "/NFL",                   # No File List - do not log file names
    # "/NDL"                    # No Directory List - do not log directory names
        # Notice there is no comma after the last option!
)

$commands = @(
    # ADD JOBS, ONE LINE AT A TIME
    # COMMA AFTER EACH LINE EXCEPT THE LAST

    # Example 1
    "robocopy 'D:\Shares\' '\\NEW-SERVER\Data\Shared' $dryRunFlag $($options -join ' ')",
    
    # Example 2 - Notice You can add unique options to each line
    "robocopy 'D:\Users\' '\\NEW-SERVER\Users' $dryRunFlag $($options -join ' ') /XD 'D:\Scratch\common\ServerScans'",
    
)

foreach ($command in $commands) {
    Write-Host $command
	Invoke-Expression -Command $command
}