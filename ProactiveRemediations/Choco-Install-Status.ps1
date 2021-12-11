##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]

##detection mode
if($mode -eq "detect") {
    try {choco.exe}
    catch  [System.CommandNotFoundException] 
    {write-host "Choco not intalled"
    $chocoinstalled = $false
    
    }
    finally {
         if ($chocoinstalled -eq $true){
         write-host "choco installed"
         exit 0}
    else {write-host "Choco not intalled"
        exit 1}
    
}
##remediation mode TODO: Get actual mode string from a runtime
Elseif($mode -ne "detect" -or $null) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    choco feature enable -n=allowGlobalConfirmationS    
    
}
##Testing mode? 
elseif ($mode -eq $null){
    Write-host "Not in Proactive Remedations context!"
}
