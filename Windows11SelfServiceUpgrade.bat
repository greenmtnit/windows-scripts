@ECHO OFF

REM ####################################
REM Windows11SelfServiceUpgrade.bat
REM
REM Batch script to allow user to upgrade their machine to Windows 11.
REM Meant to be used in conjunction with Create-Windows11SelfServiceUpgradeShortcut.ps1
REM https://github.com/greenmtnit/windows-scripts/blob/main/Create-Windows11SelfServiceUpgradeShortcut.ps1
REM 
REM Script overview:
REM First, perform some simple checks:
REM   - Checks current OS. Only Windows 10 is eligible for upgrade.
REM   - Checks for at least 25GB free disk space
REM Next, prompt the user to confirm the upgrade.
REM Finally, download and run the Windows 11 Update Assistant. For GMITS managed machines, an AutoElevate rule exists to run the Assistant automatically.
REM ####################################

REM ===== CHECK OS VERSION =====
REM Get ProductName
FOR /F "tokens=3*" %%A IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>NUL') DO SET "ProductName=%%A %%B"

REM Get Build number
FOR /F "tokens=3*" %%A IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild 2^>NUL') DO SET "Build=%%A"

REM Check if ProductName starts with Windows 10
ECHO %ProductName% | FINDSTR /B /I "Windows 10" >NUL
IF %ERRORLEVEL%==0 (
    IF %Build% GEQ 22000 (
        ECHO This computer is already on Windows 11. No need to upgrade!
        PAUSE
        EXIT
    ) ELSE (
        ECHO This computer is on Windows 10. Proceeding...
    )
) ELSE (
    ECHO ERROR: Detected incompatible operating system: %ProductName%.
    PAUSE
    EXIT
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
ECHO      WINDOWS 11 SELF-SERVICE UPGRADE
ECHO =============================================
ECHO.
ECHO Your system will be upgraded to Windows 11. Please read the following before continuing:
ECHO.
ECHO 1) This process can take several hours. Your computer must stay on the entire time. If this is a laptop, keep it plugged in. Don't close the lid. It's recommended to run the upgrade overnight, or when you aren't using the computer.
ECHO.
ECHO 2) The upgrade keeps all your files, applications, and settings, but there is always a small chance some unique setups may have issues. By proceeding, you confirm you understand the risks.
ECHO.
CHOICE /C YN /M "Press Y to confirm you have read and understood the above information, or N to cancel."
IF ERRORLEVEL 2 (
    ECHO Upgrade cancelled by user.
    PAUSE
    EXIT
)
CLS

REM Confirmation Prompt 2
ECHO.
ECHO =============================================
ECHO Let me ask you again:
ECHO.
ECHO BY PROCEEDING, YOU CONFIRM YOU HAVE READ THE ABOVE INFORMATION, UNDERSTAND THE RISKS, AND WISH TO PROCEED WITH THE WINDOWS 11 UPGRADE.
ECHO.
CHOICE /C YN /M "Press Y to confirm, or N to cancel."
IF ERRORLEVEL 2 (
    ECHO Upgrade cancelled by user.
    PAUSE
    EXIT
)
IF ERRORLEVEL 1 (
    ECHO OK! Proceeding with Windows 11 upgrade...
)

TIMEOUT /T 3
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
ECHO Downloading Windows 11 Installation Assistant...this may take a few minutes.
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

REM ===== Run the Windows 11 Installation Assistant silently =====
ECHO Starting install...
START "" "%FILE%" /SkipEULA /Auto upgrade /NoRestartUI /copylogs "%WORKDIR%"