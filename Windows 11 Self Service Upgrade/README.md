# Windows 11 Self Service Upgrade
## Overview
The self-service upgrade process consists of a desktop shortcut to a batch script to run the Windows 11 Upgrade Assistant.

## Enviroment Prerequisites
This system is designed for a managed IT environment where the following are available:

- **SyncroMSP RMM**: For running scripts. Syncro's asset custom field feature is also used to track Windows 11 compatibility.
- **AutoElevate**: Allows users to run the Windows 11 Update Assistant without local administrator rights.

You may be able to adapt for other RMM and elevation tools.

## Steps

### Read and Update the Scripts
You are responsible for reading, understanding, and testing all scripts before deployment.

Be warned that some alerts, file paths, etc. may use our company name. You'll want to change these.

### Deploy Windows 11 Compatibility Check Script
Deploy the [Windows 11 Compatibility Check Script](https://github.com/greenmtnit/windows-scripts/blob/main/Check-Windows11Support.ps1) via Syncro. Recommended: add the script as a Setup Script in Syncro policies so it will run on every machine added to Syncro.

You need to create a Syncro custom asset field (text field) called `SupportWindows11`

This script is based on Microsoft's official hardware readiness script. If the machine supports Windows 11, the script writes a value of "Yes" to the `SupportWindows11` custom field. If the machine does **not** support Windows 11, the script write a value of "No" to the `SupportWindows11` custom field, plus a reason why Windows 11 is not supported. Example: `No, Processor, TPM`.


### Create AutoElevate Rule for the Update Assistant
Create a rule in AutoElevate to allow the Windows 11 Update Assistant to run. This way, users can run the self-service upgrade without local administrator privileges.

#### Recommendations for AutoElevate
- Create a global (top-level / all-company) rule in AutoElevate
- Download and run the [Windows 11 Update Assistant](https://go.microsoft.com/fwlink/?linkid=2171764) on a test machine so you can capture the elevation event in AutoElevate and use the event to create the rule.
- Restrict the path in the AutoElevation rule to the path where the self-service script will save the Update Assistant, i.e. `C:\temp\Windows11InstallationAssistant.exe`. While not perfect, this prevents users from running the Update Assistant independently, e.g. from their Downloads folder.

#### Example AutoElevate Rule

##### File section:
- Product Name: `Windows Installation Assistant`
- File path: `C:\temp\Windows11InstallationAssistant.exe`
- All other File criteria un-checked

#####  Publisher section:
- Subject elements:
- CN: `Microsoft Corporation`
- All other Publisher criteria un-checked

### Deploy the Shortcut Script
Use Syncro to deploy the [Create-Windows11SelfServiceUpgradeShortcut.ps1](https://github.com/greenmtnit/windows-scripts/blob/main/Windows%2011%20Self%20Service%20Upgrade/Create-Windows11SelfServiceUpgradeShortcut.ps1) script. This script will create a desktop shortcut to run the [batch script](https://github.com/greenmtnit/windows-scripts/blob/main/Windows%2011%20Self%20Service%20Upgrade/Windows11SelfServiceUpgrade.bat) that runs the Windows 11 upgrade. 

#### Notes
- Batch is used for the self-service update because using PowerShell would require handling ExecutionPolicy issues, and possibly require yet another wrapper script. In other Words, Batch is more foolproof for a simple double-click and run.
- The script will not create the shortcut on machines that are already on Windows 11, or machines that are not compatible with the Windows 11 upgrade.

## Using the Self-Service Upgrade

Users can simply double-click the desktop icon to run the self-service upgrade.

The batch script will run. The script first performs some checks, then prompts the user to confirm the upgrade, and finally downloads and runs the Windows 11 Update Assistant with flags for a safe upgrade. The AutoElevate rule will cause the Update Assistant process to be elevated with the required admin permissions.

## More Information
For more information on how the scripts work, see the individual scripts themselves, especially in the script headers.
