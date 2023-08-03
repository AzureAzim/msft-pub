##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
$service =  get-service -name power
$starttype = $power.starttype
$state = $power.status

##detection mode
if($mode -eq "detect") {

    if($starttype -ne "Automatic") {$modechange = $true}
    if($state -ne "Running") {$modechange = $true}

    #Exit logic
        if ($modechange -eq $false){exit 0}
        if ($modechange -eq $true){$modeerror; exit 1}

    }

Elseif($mode --eq "remediate") {
    if($starttype -eq "Disabled" -or "Manual") {set-service power -StartupType "Automatic" }
    if($state -eq "Stopped"){Start-service power} 


    ##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}
