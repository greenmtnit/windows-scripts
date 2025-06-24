@ECHO OFF

REM ####################################
REM UninstallConnectsecure.bat
REM Uninstalls Connectsecure Vulnerability Scan Agent a.k.a CyberCNS Agent https://connectsecure.com/
REM ####################################

IF NOT EXIST "C:\Program Files (x86)\CyberCNSAgent\cybercnsagent.exe" (
    ECHO Connectsecure does not appear to be installed. Exiting.
    EXIT
)

"C:\Program Files (x86)\CyberCNSAgent\cybercnsagent.exe" -r
