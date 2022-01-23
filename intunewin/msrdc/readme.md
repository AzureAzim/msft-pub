# Maintinence Free MSRDC IntuneWin
## Inspired by Christian Brinkoff's [article] (https://christiaanbrinkhoff.com/2020/11/12/learn-how-to-deploy-the-remote-desktop-msrdc-wvd-client-as-intune-win32-app-via-microsoft-endpoint-manager-mem-to-your-physical-clients/) 
This is my lazy-persons build of the Microsoft Remote Desktop Client used for Azure Virtual Desktop or WIndows 365. This version is designed to download the latest version from Microsoft and install under the Device Context. No need for maintaining the package as this product team has very regular updates to this package. 

During Endpoint Manager import of IntuneWoin file, you must use these lines as parameters to configure:

Install cmd: 
  `powershell.exe -executionpolicy Bypass -file .\install-msrdc.ps1`
Uninstall cmd: 
  `powershell.exe -executionpolicy Bypass -file .\uninstall-msrdc.ps1`

Detection: 
  `C:\Program Files\Remote Desktop\msrdc.exe`
