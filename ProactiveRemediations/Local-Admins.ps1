##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$localuser = $env:USERNAME
$LocalAdmins = net localgroup administrators

##detection mode
if($mode -eq "detect") {
        
        if (("$localadmins" -like "*$localuser*") -eq $true){
            Write-Host "Local user found in Admins Group"
            exit 1
        }
        else{
            #No matching certificates, do not remediate
            Write-Host "User is not local admin"        
            exit 0
        } 
    catch{
        $errMsg = $_.Exception.Message
        Write-Error $errMsg
        exit 1
    }

}
##remediation mode TODO: Get actual mode string from a runtime
Elseif($mode -ne "detect" -or $null) {
    try
    {      
        if (("$localadmins" -like "*$localuser*") -eq $true){
    
            Write-Host "Local user found in Admins Group"
            Remove-LocalGroupMember -Group "Administrators" -member $localuser # this works on newero OS's
            net localgroup Administrators $localuser /delete # this works on older OS's
            logoff.exe
        }
        else{
            #No matching certificates, do not remediate
            Write-Host "User is not local admin"        
            exit 0
        }   
    }
    catch{
        $errMsg = $_.Exception.Message
        Write-Error $errMsg
        exit 1
    }
    
}
##Testing mode? 
elseif ($mode -eq $null){
    Write-host "Not in Proactive Remedations context!"
}
