#Intunewin32 post install detection script for choco

try {choco.exe
     $chocoinstalled = $true
     }
catch [System.Management.Automation.CommandNotFoundException] {
     write-host "Choco not installed catch"
     $chocoinstalled = $false
}
catch {write-host "some other error occured"
     $Error[0].exception
     $chocoinstalled = $false
          }
if ($chocoinstalled -eq $true){
     write-host "choco installed"
     exit 0}
else {write-host "Choco not intalled"
     exit 1}
