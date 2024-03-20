#Remediation Script to check for and enable W365 Boot configuration for Windows 11 23h2 without being in an insider build, This was inspired by Terry Gore and I referenced code from Donna Ryan's PR for UDP Shortpath for making / checking reg keys

##CHECK Script Running Context (ie detection or remediation mode)
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false

$boottocloudmode = Get-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\CloudDesktop"     
$Overrrideshellprogram = Get-ItemProperty -path "HKLM:\Software\Microsoft\PolicyManager\current\device\WindowsLogon"
$nodevalues = Get-ItemProperty -path "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues" 


##detection mode
if($mode -eq "detect") {

    if($boottocloudmode.BootToCloudMode -ne "1") {$modechange = $true}
    if($Overrrideshellprogram.OverrideShellProgram -ne "1") {$modechange = $true}
    if($nodevalues.18 -ne "1") {$modechange = $true}
    if($nodevalues.01 -ne "1") {$modechange = $true}

    #Exit logic
        if ($modechange -eq $false){exit 0}
        if ($modechange -eq $true){$modeerror; exit 1}

    }

Elseif($mode --eq "remediate") {
    if((test-path "HKLM:\Software\Microsoft\PolicyManager\current\device\CloudDesktop") -eq $false) {New-item "HKLM:\Software\Microsoft\PolicyManager\current\device\CloudDesktop"}
    if((test-path "HKLM:\Software\Microsoft\PolicyManager\current\device\WindowsLogon") -eq $false) {New-item "HKLM:\Software\Microsoft\PolicyManager\current\device\WindowsLogon"}
    if((test-path "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues") -eq $false) {New-item "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues"}

    New-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\CloudDesktop" -Name "BootToCloudMode" -Value "1"
    New-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\current\device\WindowsLogon" -Name "OverrideShellProgram" -Value "1"
    New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues" -Name "18" -Value "1"
    New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedPC\NodeValues" -Name "01" -Value "1"
    ##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}
