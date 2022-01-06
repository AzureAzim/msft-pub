##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false

##detection mode
if($mode -eq "detect") {

if(<#we detect the thing we wanna change#>) {

    $modechange = $true
}
#Exit logic
    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}

}

Elseif($mode --eq "remediate") {

##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}
