##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
$chocoupdates = choco outdated
$string = ($chocoupdates | select-string -Pattern "Chocolatey has determined").ToString()
$expectedstring = "Chocolatey has determined 0 package(s) are outdated. "

##detection mode
if($mode -eq "detect") {

if($expectedstring -ne $string) {
    
    $modechange = $true
}
else {
    $modechange = $false
}
#Exit logic
    if ($modechange -eq $false){$string; exit 0}
    if ($modechange -eq $true){$string; exit 1}
    else {$string;exit 0}
}

Elseif($mode -eq "remediate") {

choco upgrade all -y
$chocoupdates = choco outdated
$string = ($chocoupdates | select-string -Pattern "Chocolatey has determined").ToString()
$expectedstring = "Chocolatey has determined 0 package(s) are outdated. "
if ($expectedstring -ne $string){$string; exit 1}
if ($expectedstring -eq $string){$string; exit 0}
else {$string;exit 0}
}
