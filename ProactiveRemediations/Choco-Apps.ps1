$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
#checkforapps
$apptolookfor = "powertoys","prusaslicer","firefox","googlechrome","7zip","chrome-remote-desktop-host","vscode","vlc","python3","microsoft-windows-terminal","winscp","git","rsat","steam-client","microsoft-windows-terminal","notepadplusplus","azcopy","obs-studio","obs-virtualcam","obs-ndi","firefox","rufus","vscode-python","vscode-arduino","vscode-powershell","drawio","discord","microsoftazurestorageexplorer"

[System.Collections.ArrayList]$chocoapps = (choco list --local-only).split([Environment]::NewLine)
[System.Collections.ArrayList]$chocooutdatedapps = (choco outdated).split([Environment]::NewLine)
$choconoupdatesstring = "Chocolatey has determined 0 package(s) are outdated. "
$chocoversion = $chocoapps[0]
$chocopkgcountremoval = $chocoapps[-1]
$chocoapps.remove($chocopkgcountremoval)
$chocoapps.remove($chocoversion)

if($mode -eq "detect") {
    foreach ($app in $apptolookfor){
        $appexists = ($apptolookfor -contains "$app")
        if ($appexists -eq $true) {
            write-host "$app found"
        }
        Else {
            write-host "$app not found, marking for remediation"
            $modechange = $true
        }
    }
    if ($chocooutdatedapps -notcontains $choconoupdatesstring) {
        write-host "outdated apps detected"
        $modechange = $true
    }
    if ($modechange -eq $true){exit 1}
    elseif ($modechange -eq $false){exit 0}
}
Elseif($mode -ne "detect" -or $null) {
    foreach ($app in $apptolookfor){
        $appexists = ($apps -contains "$app")
        if ($appexists -eq $true) {
            write-host "$app found"
        }
        Else {
            write-host "$app not found, installing $app"
            choco install $app -y
        }
        if ($chocooutdatedapps -notcontains $choconoupdatesstring) {
            write-host "outdated apps detected"
            choco upgrade all -y
        }

    }

}
elseif ($mode -eq $null){
    Write-host "Not in Proactive Remedations context!"
}
