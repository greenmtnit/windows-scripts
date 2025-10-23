@ECHO OFF
TITLE Windows 11 Version 24H2 Upgrade

REM ####################################
REM Windows24H2SelfServiceUpgrade.bat
REM
REM Batch script to allow user to upgrade their machine to Windows 11 version 24H2.
REM Meant to be used in conjunction with Create-Windows24H2SelfServiceUpgradeShortcut.ps1
REM https://github.com/greenmtnit/windows-scripts/blob/main/Create-Windows24H2SelfServiceUpgradeShortcut.ps1
REM 
REM Script overview:
REM First, perform some simple checks:
REM   - Checks current OS.
REM   - Checks for at least 25GB free disk space
REM Next, prompt the user to confirm the upgrade.
REM Finally, download and run the Windows 11 Update Assistant. For GMITS managed machines, an AutoElevate rule exists to run the Assistant automatically.
REM ####################################

REM ===== CHECK OS VERSION =====
REM Get ProductName
FOR /F "tokens=3*" %%A IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>NUL') DO SET "ProductName=%%A %%B"

REM Get Build number
FOR /F "tokens=3*" %%A IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild 2^>NUL') DO SET "Build=%%A"

IF %Build% GEQ 26100 (
    ECHO This computer is already on Windows 11 version 24H2. No need to upgrade!
    PAUSE
    EXIT
) ELSE (
    ECHO This computer needs the upgrade. Proceeding...
)


REM ===== CHECK FOR AT LEAST 25GB FREE ON C: =====
REM Minimum free space in GB
SET MinFreeGB=25

REM Get free space on C: in GB using PowerShell and round to integer. Use PowerShell because Batch doesn't handle large numbers well.
FOR /F %%A IN ('POWERSHELL -NoProfile -Command "[math]::Floor((Get-PSDrive C).Free / 1GB)"') DO SET FreeGB=%%A

REM Compare to minimum threshold
IF %FreeGB% LSS %MinFreeGB% (
    ECHO ERROR: Not enough free disk space. Upgrade cannot proceed.
    PAUSE
    EXIT /B 1
)

REM ===== PROMPT USER TO CONFIRM =====

REM Confirmation Prompt 1
ECHO.
ECHO =============================================
ECHO      Windows 11 Version 24H2 Upgrade
ECHO =============================================
ECHO.
ECHO   Your system will be upgraded to Windows 11 version 24H2. Please read the following before continuing:  
ECHO.
ECHO   1) This process can take a while. Your computer must stay on the entire time. You can continue to use the computer. If this is a laptop, keep it plugged in. Don't close the lid.  
ECHO.
ECHO   2) A reboot is required when the upgrade finishes. You will receive a pop-up notification with a 30 minute warning of the reboot.  
ECHO.
ECHO   3) The upgrade keeps all your files, applications, and settings, but there is always a small chance some unique setups may have issues. By proceeding, you confirm you understand the risks.  
ECHO.
CHOICE /C YN /M "  Press Y to confirm you have read and understood the above information, or N to cancel.  "
IF ERRORLEVEL 2 (
    ECHO Upgrade cancelled by user.
    PAUSE
    EXIT
)
IF ERRORLEVEL 1 (
    ECHO OK! Proceeding with 24H2 upgrade...
)

TIMEOUT /T 3 >NUL
CLS
ECHO Getting things ready...

REM ===== DOWNLOAD AND RUN CAFFEINE -  PREVENT SLEEP DURING UPGRADE ===== 

SET PROCESSNAME=caffeine64.exe
SET URL=https://www.zhornsoftware.co.uk/caffeine/caffeine.zip
SET ZIPFILE=%TEMP%\caffeine.zip
SET EXTRACTDIR=%TEMP%\caffeine_extract

REM Check if caffeine64.exe is running
TASKLIST /FI "IMAGENAME eq %PROCESSNAME%" /FI "STATUS eq RUNNING" | FIND /I "%PROCESSNAME%" >NUL
IF NOT %ERRORLEVEL% EQU 0 (
    REM Download ZIP silently
    @BITSADMIN /TRANSFER download_caffeine /PRIORITY normal %URL% %ZIPFILE% >NUL 2>&1

    REM Delete extraction folder if it exists
    IF EXIST "%EXTRACTDIR%" RMDIR /S /Q "%EXTRACTDIR%"

    REM Create extraction folder
    MKDIR "%EXTRACTDIR%"

    REM Extract ZIP (no overwrite errors because dir was removed)
    POWERSHELL -COMMAND "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIPFILE%', '%EXTRACTDIR%')" >NUL 2>&1

    REM Run caffeine64.exe with 30 second interval
    CD /D "%EXTRACTDIR%"
    START "" "caffeine64.exe" "30"
)


REM ===== DO THE UPGRADE =====

REM ===== Define working directory and URL =====
SET "WORKDIR=C:\temp"
SET "URL=https://go.microsoft.com/fwlink/?linkid=2171764"
SET "FILE=%WORKDIR%\Windows11InstallationAssistant.exe"

REM ===== Create working directory if it does not exist =====
IF NOT EXIST "%WORKDIR%" (
    MKDIR "%WORKDIR%"
)

REM ===== Download Windows 11 Installation Assistant =====
ECHO.
ECHO Downloading Installation Assistant...this may take a few minutes.
@BITSADMIN /TRANSFER W11INSTALL /DOWNLOAD /PRIORITY HIGH "%URL%" "%FILE%" >NUL 2>&1
IF NOT EXIST "%FILE%" (
    ECHO ERROR: Failed to download Windows 11 Installation Assistant. Exiting!
    PAUSE
    EXIT /B 1
)

REM ===== Prompt User =====
CLS
ECHO .
ECHO NOTICE: Click Accept and Install when it appears.
ECHO If the upgrade window does not appear, check for and click the icon on the taskbar.
TIMEOUT /T 5 >NUL

REM ===== Run the Windows 11 Installation Assistant silently =====
ECHO Starting install...
START "" "%FILE%" /SkipEULA /Auto Upgrade /CopyLogs "%WORKDIR%"