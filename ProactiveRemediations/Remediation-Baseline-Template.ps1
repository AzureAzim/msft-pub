##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false

##detection mode
if($mode -eq "detect") {

if(#we detect the tthing we wanna change
) {

    $modechange = $true
}

    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}

}
##remediation mode TODO: Get actual mode string from a runtime
Elseif($mode --eq "remediate") {



exit 0
}
