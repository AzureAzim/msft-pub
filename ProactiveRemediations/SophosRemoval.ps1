## Script removes Sophos installed on a device if it is detected. This is for customers moving to Microsoft Defender for Endpoint. Devices must have Tamper Protection disabled in Sophos management console!

##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
$sophosapps = Get-WmiObject -Class Win32_Product  | where {$_.vendor -like "*Sophos*"}

##detection mode
if($mode -eq "detect") {

if($sophosapps -ge 1) {

    $modechange = $true
}
#Exit logic
    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}

}

Elseif($mode -eq "remediate") {

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
##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}





}
