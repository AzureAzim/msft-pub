$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$TimeKey= Get-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\"
$Ntpserver = $timekey.ntpserver
$Timetype = $timekey.type
$modechange = $false
$modeerror = @()
$servicestate = get-service  -Name "w32time" 
######DETECT GOES HERE

if($mode -eq "detect") {
    if ($timeType -ne "All") {
        $modeerror += Write-Warning "NTP Type is wrong $Timetype"
        $modechange = $true
    }
    if ($NTPSERVER -ne 'time.windows.com,0x9') {
        $modeerror += Write-Warning "NTP Server is Wrong, $ntpserver"
        $modechange = $true
    }
    if ($servicestate.StartType -eq "Disabled") {
        $modeerror += Write-Warning "Service State is Wrong, $servicestate.StartType"
        $modechange = $true

    }
    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}
} Elseif($mode -eq "remediate") {  
    #Turn on the w32time service to ensure its enabled
    Set-Service -Name "w32time" -Status running -StartupType automatic
    w32tm /config /manualpeerlist:time.windows.com /syncfromflags:all
    net stop w32time
    net start w32time
    exit 0 }
