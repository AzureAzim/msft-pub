##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
$sophosapps = Get-WmiObject -Class Win32_Product  | where {$_.vendor -like "*Sophos*"}

##detection mode
if($mode -eq "detect") {

   # remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\" -Name PendingFileRenameOperations
   # cd "C:\Program Files\Sophos\Sophos Endpoint Agent"
   # .\uninstallcli.exe


if($sophosapps -ge 1) {

    $modechange = $true
}
#Exit logic
    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}

}

Elseif($mode -eq "remediate") {
    remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\" -Name PendingFileRenameOperations
    cd "C:\Program Files\Sophos\Sophos Endpoint Agent"
    .\uninstallcli.exe
    net stop "Sophos AutoUpdate Service"
    net stop "Sophos Agent"
    net stop "SAVService"
    net stop "SAVAdminService"
    net stop "Sophos Message Router"
    net stop "Sophos Web Control Service"
    net stop "swi_service"
    net stop "SntpService"
    net stop "sophossps"
    net stop "swi_filter"
    foreach ($app in $sophosapps) {
    $appguid = ($app.IdentifyingNumber).tostring()
    msiexec /qn /x $appguid REBOOT=ReallySuppress
    }
    remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\" -Name PendingFileRenameOperations
    cd "C:\Program Files\Sophos\Sophos Endpoint Agent"
    .\uninstallcli.exe

    msiexec.exe /qn /X 2C14E1A2-C4EB-466E-8374-81286D723D3A REBOOT=ReallySuppress
    msiexec.exe /qn /X 2D2A1891-4657-4E6F-9373-BFCE4C9AC5BA REBOOT=ReallySuppress
    msiexec.exe /qn /X 2831282D-8519-4910-B339-2302840ABEF3 REBOOT=ReallySuppress

msiexec.exe /qn /X 258F3C41-B03D-478A-8972-50F14E02841E REBOOT=ReallySuppress
msiexec.exe /qn /X 0EA5323F-DE1B-480C-911E-7827E5EA20E9 REBOOT=ReallySuppress
msiexec.exe /qn /X 8078549C-CFF0-48C5-9B77-6BA48A14673D REBOOT=ReallySuppress
msiexec.exe /qn /X 866151B2-E14E-40E0-B6D9-64B1D428F5CB REBOOT=ReallySuppress
msiexec.exe /qn /X CD39E739-F480-4AC4-B0C9-68CA731D8AC6 REBOOT=ReallySuppress

msiexec.exe /qn /X 5E8436D5-3688-4007-94C7-55D017275F89 REBOOT=ReallySuppress


##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}


