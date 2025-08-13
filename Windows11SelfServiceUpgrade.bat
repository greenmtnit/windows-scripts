@ECHO OFF

REM ===== Check OS Version =====
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

REM ===== Confirmation Prompt 1 =====
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

REM ===== Confirmation Prompt 2 =====
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
CLS
ECHO Downloading Windows 11 Installation Assistant...this may take a few minutes.
BITSADMIN /TRANSFER W11INSTALL /DOWNLOAD /PRIORITY HIGH "%URL%" "%FILE%"
IF NOT EXIST "%FILE%" (
    ECHO ERROR: Failed to download Windows 11 Installation Assistant. Exiting!
    PAUSE
    EXIT /B 1
)

REM ===== Run the Windows 11 Installation Assistant silently =====
ECHO Starting install...
START "" "%FILE%" /SkipEULA /Auto upgrade /NoRestartUI /copylogs "%WORKDIR%"
