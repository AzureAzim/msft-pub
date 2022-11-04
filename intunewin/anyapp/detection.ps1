choco feature enable --name="'useEnhancedExitCodes'" -y
$PackageName = "vscode"
C:\ProgramData\chocolatey\bin\choco.exe list -e $PackageName --local-only
exit $LastExitCode
