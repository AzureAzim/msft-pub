<#
.SYNOPSIS
Grab Windows Autopilot hardware hashes from all computers in an AD OU and export to CSV.

.PARAMETER OU
DistinguishedName of the AD OU to enumerate (e.g. "OU=Computers,DC=contoso,DC=com").

.PARAMETER Credential
Optional PSCredential for remote connections.

.PARAMETER LocalAutopilotScript
Optional path to a local Get-WindowsAutoPilotInfo.ps1 (Microsoft script). If provided the script will be copied/run on each remote host. If omitted the script will attempt to run the cmdlet Get-WindowsAutoPilotInfo on the remote host if present.

.PARAMETER OutputCsv
Path to output CSV file (default: .\AutopilotHashes.csv)

.NOTES
Requires:
- ActiveDirectory module for Get-ADComputer
- WinRM/PowerShell Remoting enabled on targets
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OU,

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory=$false)]
    [string]$LocalAutopilotScript,

    [Parameter(Mandatory=$false)]
    [string]$OutputCsv = ".\AutopilotHashes.csv"
)

Import-Module ActiveDirectory -ErrorAction Stop

$computers = Get-ADComputer -SearchBase $OU -Filter * | Select-Object -ExpandProperty Name
$results = @()

foreach ($comp in $computers) {
    Write-Verbose "Processing $comp"
    if (-not (Test-Connection -ComputerName $comp -Count 1 -Quiet)) {
        $results += [PSCustomObject]@{ ComputerName = $comp; Status = "Unreachable"; AutopilotHash = $null }
        continue
    }

    try {
        # Prepare remote output path
        $remoteOut = "C:\Temp\$($comp)-Autopilot.csv"
        $invokeParams = @{ ComputerName = $comp; ErrorAction = 'Stop' }
        if ($Credential) { $invokeParams.Credential = $Credential }

        # If user provided a local script, copy it and run it remotely.
        if ($LocalAutopilotScript -and (Test-Path $LocalAutopilotScript)) {
            # Ensure remote folder
            Invoke-Command @invokeParams -ScriptBlock { param($p) New-Item -Path (Split-Path $p) -ItemType Directory -Force | Out-Null } -ArgumentList $remoteOut

            # Copy local script to remote temp and execute it there to generate CSV.
            $remoteScriptPath = "\\$comp\C$\Temp\Get-WindowsAutoPilotInfo.ps1"
            Copy-Item -Path $LocalAutopilotScript -Destination $remoteScriptPath -Force -ErrorAction Stop

            # Run the copied script on remote; assume it accepts -OutputFile (Microsoft script does)
            Invoke-Command @invokeParams -ScriptBlock {
                param($scriptPath, $outPath)
                & $scriptPath -OutputFile $outPath -Force -ErrorAction Stop
            } -ArgumentList $remoteScriptPath, $remoteOut
        }
        else {
            # Try to run Get-WindowsAutoPilotInfo cmdlet on the remote host
            $script = {
                param($outPath)
                $cmd = Get-Command -Name Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue
                if ($null -ne $cmd) {
                    Get-WindowsAutoPilotInfo -OutputFile $outPath -Force -ErrorAction Stop
                } else {
                    throw "Get-WindowsAutoPilotInfo not found on remote host."
                }
            }
            Invoke-Command @invokeParams -ScriptBlock $script -ArgumentList $remoteOut
        }

        # Import the CSV on the remote and return its rows (if any)
        $remoteCsvRows = Invoke-Command @invokeParams -ScriptBlock {
            param($p)
            if (Test-Path $p) { Import-Csv $p } else { @() }
        } -ArgumentList $remoteOut

        if ($remoteCsvRows -and $remoteCsvRows.Count -gt 0) {
            foreach ($row in $remoteCsvRows) {
                # Normalize common column names: HardwareHash / DeviceHash / Hash
                $hash = $row.HardwareHash ? $row.HardwareHash : ($row.DeviceHash ? $row.DeviceHash : ($row.Hash ? $row.Hash : $null))
                $results += [PSCustomObject]@{
                    ComputerName = $comp
                    Hostname     = ($row.DeviceName ? $row.DeviceName : $comp)
                    AutopilotHash = $hash
                    RawObject     = ($row | ConvertTo-Json -Depth 5)
                    Status        = "Success"
                }
            }
        }
        else {
            $results += [PSCustomObject]@{ ComputerName = $comp; Hostname = $comp; AutopilotHash = $null; RawObject = $null; Status = "No CSV produced" }
        }
    }
    catch {
        $results += [PSCustomObject]@{ ComputerName = $comp; Hostname = $comp; AutopilotHash = $null; RawObject = $_.Exception.Message; Status = "Error" }
    }
}

# Export minimal CSV: ComputerName, Hostname, AutopilotHash, Status
$results | Select-Object ComputerName, Hostname, AutopilotHash, Status | Export-Csv -Path $OutputCsv -NoTypeInformation -Force

Write-Output "Done. Results exported to $OutputCsv"
