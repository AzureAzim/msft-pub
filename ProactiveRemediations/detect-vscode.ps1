#can be used in a remediation OR intunewin32 app, requires choco 

C:\ProgramData\chocolatey\bin\choco.exe feature enable --name="'useEnhancedExitCodes'" -y
$PackageName = "gazorp"
C:\ProgramData\chocolatey\bin\choco.exe list -e $PackageName
exit $LastExitCode
