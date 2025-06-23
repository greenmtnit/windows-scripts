@ECHO OFF

REM ####################################
REM UninstallAugmennt.bat
REM Uninstalls Augmentt https://www.augmentt.com/
REM ####################################

IF NOT EXIST "C:\Program Files (x86)\Augmentt\unins000.exe" (
    ECHO Augmentt does not appear to be installed. Exiting.
    EXIT
)

ECHO Calling Augmennt uninstaller. If no errors uninstall has succeeded.
"C:\Program Files (x86)\Augmentt\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES