This is my lazy-persons build of the Microsoft Remote Desktop Client used for Azure Virtual Desktop or WIndows 365. This version is designed to download the latest version from Microsoft and install under the Device Context.

During Endpoint Manager import of IntuneWoin file, you must use these lines as parameters to configure:

Install cmd: powershell.exe -executionpolicy Bypass -file .\install-msrdc.ps1
Uninstall cmd: powershell.exe -executionpolicy Bypass -file .\uninstall-msrdc.ps1

Detection: C:\Program Files\Remote Desktop\msrdc.exe
