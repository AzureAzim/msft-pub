##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false

##detection mode
if($mode -eq "detect") {


}
##remediation mode TODO: Get actual mode string from a runtime
Elseif($mode -ne "detect" -or $null) {

}
##Testing mode? 
elseif ($mode -eq $null){
    Write-host "Not in Proactive Remedations context!"
}
