# How It Works - Egnyte Mass Deployment
Egnyte can be configured with a .json file. See the [Egnyte documentation](https://helpdesk.egnyte.com/hc/en-us/articles/32411199461773-Desktop-App-for-Windows-Mass-Configuration-Capabilities
) for more details:

If a .json exists at 

`C:\Program Files (x86)\Egnyte Connect\defaultMassDeploymentConfig.json`

the config will be applied to all users on the machine who use Egnyte.

Egynte does this by automatically copying `defaultMassDeploymentConfig.json` to each user's ED_DATA_STORAGE_DIR, by default 

`C:\Users\<user>\AppData\Local\Egnyte Connect\config\massDeploymentConfig.json`

when Egnyte is launched for that user.

Our custom script `Deploy-Egnyte.ps1` copies a customzied `config.json` to the expected path: `C:\Program Files (x86)\Egnyte Connect\defaultMassDeploymentConfig.json`

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

Use IntuneWinAppUtil.exe to create a .intunewin file, e.g.,
`IntuneWinAppUtil.exe -c .\source\ -s Deploy-Egnyte.ps1 -o .\dest\`

where **source** folder contains `Deploy-Egnyte.ps1` and `config.json`

Upload the resulting **.intunewin** file to Intune as a Win32 app.

## Example Intune App Settings

### App Information
* Name: Egynte
* Description: PowerShell script to install Egnyte with a .json mass config.
* Publisher: Custom
* Leave all other App Info settings at their defaults

### Program
* Install command: `%windir%\SysNative\WindowsPowershell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -File .\Deploy-Egnyte.ps1 -LogOutput -Verbose`
* Uninstall command: N/A
* Installation time required: 60 minutes (probably overkill, but whatever)
* Allow available uninstall: No
* Install behavior: System
* Device restart behavior: App install may force a device restart
* Leave all Return Codes at their defaults

### Requirements
* Operating system architecture: 64 Bit
* Minimum operating system: You can select the oldest version available, unless you have special requirements
* Leave all other Requirements settings at their defaults

### Detection Rules
* Rules format: Manually configure detection rules
* Add file rule
    * Path: `C:\Program Files (x86)\Egnyte Connect`
    * File or folder: `EgnyteClient.exe`
    * Detection method: File or folder exists
    * Associated with a 32-bit app on 64-bit clients: no

### Assignments
* Assign to a user or device group as needed.
* Configure End user notifications as desired


# Troubleshooting
Log Files
- `C:\Windows\Temp\egnyte_deployment\` directory (when using -LogOutput and -Verbose flags on Deploy-Egnyte.ps1)
- `C:\Users\<user>\AppData\Local\Egnyte Connect\logs\mass_deployment.log`