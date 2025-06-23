REM ####################################
REM UninstallScreenconnect.bat
REM Uninstalls ScreenConnect a.k.a. Connectwise Control
REM All credit to original source: https://gist.github.com/ak9999/e68da02d7957bd7db2a2a647f76d50be#file-uninstallscreenconnectclient-bat
REM ####################################

wmic product where "name like 'ScreenConnect Client%%'" call uninstall /nointeractive