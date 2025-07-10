@ECHO OFF

REM ####################################
REM UninstallConnectsecure.bat
REM Uninstalls Connectsecure Vulnerability Scan Agent a.k.a CyberCNS Agent https://connectsecure.com/
REM Note: in some cases, the program path will be C:\Program Files (x86)\CyberCNSAgentV2 instead of \CyberCNSAgent. 
REM This script currently does not handle V2 so manual intervention would be needed in that case.
REM ####################################

REM Uninstall the agent
IF NOT EXIST "C:\Program Files (x86)\CyberCNSAgent\cybercnsagent.exe" (
    ECHO Connectsecure does not appear to be installed. Skipping uninstall and proceeding to cleanup.
) ELSE (
    "C:\Program Files (x86)\CyberCNSAgent\cybercnsagent.exe" -r
)

REM Delete registry key for ConnectSecure Agent
set KEY="HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ConnectSecure Agent"

REM Check if the registry key exists
REG QUERY %KEY% >nul 2>&1

REM If the key exists, delete it
if %errorlevel%==0 (
    REG DELETE %KEY% /f
) else (
    echo Registry key not found: %KEY%
)

REM Delete empty program folder if it exists and is empty
IF EXIST "C:\Program Files (x86)\CyberCNSAgent" (
    RD "C:\Program Files (x86)\CyberCNSAgent"
)

REM Delete Services if they exist
sc query cybercnsagent >nul 2>&1
if %errorlevel%==0 (
    sc delete cybercnsagent
)

sc query cybercnsagentmonitor >nul 2>&1
if %errorlevel%==0 (
    sc delete cybercnsagentmonitor
)

ECHO Uninstallation and cleanup complete.
EXIT