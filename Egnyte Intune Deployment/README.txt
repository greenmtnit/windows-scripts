# How It Works - Egnyte Mass Deployment
Egnyte can be configured with a .json file. See the [Egnyte documentation](https://helpdesk.egnyte.com/hc/en-us/articles/32411199461773-Desktop-App-for-Windows-Mass-Configuration-Capabilities
) for more details:


If a .json exists at 

`C:\Program Files (x86)\Egnyte Connect\defaultMassDeploymentConfig.json`

the config will be applied to all users on the machine who use Egnyte.

Egynte does this by automatically copying `defaultMassDeploymentConfig.json` to each user's ED_DATA_STORAGE_DIR, by default 

`C:\Users\<user>\AppData\Local\Egnyte Connect\config\massDeploymentConfig.json`

when Egnyte is launched for that user.

# Creating a .json

An example `config.json` is included in this repo that creates two drives:
1. Z: drive, connected to \Shared, listed as 
2. S: drive, connected to the current Egynte user's private folder using the provided `::egnyte_username::` variable

See here for more on what can be done with the .json:
[Egnyte: Desktop App for Windows Mass Configuration Capabilities
](https://helpdesk.egnyte.com/hc/en-us/articles/32411199461773-Desktop-App-for-Windows-Mass-Configuration-Capabilities
).

# Intune Deployment
Place `Deploy-Egnyte.ps1` script and your `config.json` into a source directory.

Package with IntuneWinAppUtil.exe, e.g.,
`IntuneWinAppUtil.exe -c .\source\ -s Deploy-Egnyte.ps1 -o .\dest\`

where **source** folder contains `Deploy-Egnyte.ps1` and `config.json`

Upload the resulting **.intunewin** file to Intune as a Win32 app.

Install in the system context.

I prefer to use this install command:

`%windir%\SysNative\WindowsPowershell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Deploy-Egnyte.ps1 -LogOutput -Verbose`

## Intune Detection Rule
I use a simple file detection rule to detect the existence of the file:

`\Program Files (x86)\Egnyte Connect\EgnyteClient.exe`