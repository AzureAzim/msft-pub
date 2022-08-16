Function Annoy-computer {
    Param {
        [Parameter(Mandatory = $true)]
        [string] $compute

    }
Invoke-Command -ComputerName $computer -SessionOption -runasadministrator -ScriptBlock {
do {
$timer = Get-Random -Minimum 15 -Maximum 600
$length = Get-Random -Minimum 500 -Maximum 10000
Start-Sleep $timer

[console]::beep(14000,$length)
} while ($true)

}
}
