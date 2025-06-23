@ECHO OFF

REM ####################################
REM UninstallSophosNormal.bat
REM Uninstalls Sophos Antivirus using uninstaller (as opposed to SophosZap)
REM
REM See here for more info: How to Uninstall Sophos Antivirus | https://hudu.greenmtnit.com/shared_article/fMoZjmBx6EQiWxsuL3qWHYgv
REM
REM Notes:
REM   - Tamper Protection must be disabled for the uninstall to succeed.
REM   - You may need to reboot before and/or after running. 
REM     Check the exit codes of the uninstaller. 
REM     e.g. Exit code 1 means the uninstall worked, but you must reboot to finish uninstall. 
REM     Exit code 8 means a reboot is needed before uninstall.
REM     Full list of exit codes here: https://support.sophos.com/support/s/article/KBA-000008497?language=en_US
REM
REM ####################################

IF NOT EXIST "C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe" (
    ECHO Sophos uninstaller not found. Exiting.
    EXIT
)

"C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe" --quiet
ECHO %ERRORLEVEL%