# Detect-UWPAppFailures.ps1
# Exit 1 = remediation needed
# Exit 0 = no remediation needed

[CmdletBinding()]
param(
    [int]$LookbackDays = 7,
    [int]$MaxEvents = 2000,
    [string]$LogPath = "C:\ProgramData\UWPRepair\Detect-UWPAppFailures.log"
)

$ErrorActionPreference = "Stop"

# Ensure log folder exists
$logDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [Detect] $Message" | Tee-Object -FilePath $LogPath -Append
}

function Get-PackageNameFromMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $null }

    $candidates = New-Object System.Collections.Generic.List[string]

    # Common full package pattern:
    # Microsoft.Windows.Photos_2026.11020.20001.0_x64__8wekyb3d8bbwe
    $fullPattern = '(?<pkg>[A-Za-z0-9][A-Za-z0-9\.\-]+?_\d+(?:\.\d+){1,5}_[A-Za-z0-9\.\-~]+(?:__[A-Za-z0-9]+|_[A-Za-z0-9]+))'
    $fullMatches = [regex]::Matches($Message, $fullPattern)
    foreach ($m in $fullMatches) {
        $pkg = $m.Groups['pkg'].Value
        if ($pkg) { $candidates.Add($pkg) }
    }

    # Package family pattern:
    # Microsoft.WindowsCalculator_8wekyb3d8bbwe
    $familyPattern = '(?<fam>[A-Za-z0-9][A-Za-z0-9\.\-]+?_[A-Za-z0-9]{8,20})'
    $familyMatches = [regex]::Matches($Message, $familyPattern)
    foreach ($m in $familyMatches) {
        $fam = $m.Groups['fam'].Value
        if ($fam) { $candidates.Add($fam) }
    }

    # Path-based clue under WindowsApps / SystemApps
    $pathPattern = '(?:WindowsApps|SystemApps)\\(?<name>[A-Za-z0-9][A-Za-z0-9\.\-]+?)_(?<ver>\d+(?:\.\d+){1,5})_'
    $pathMatches = [regex]::Matches($Message, $pathPattern)
    foreach ($m in $pathMatches) {
        $name = $m.Groups['name'].Value
        if ($name) { $candidates.Add($name) }
    }

    if ($candidates.Count -eq 0) { return $null }

    # Normalize to the app name when possible:
    # e.g. Microsoft.Windows.Photos_2026.11020.20001.0_x64__8wekyb3d8bbwe -> Microsoft.Windows.Photos
    $normalized = foreach ($c in $candidates) {
        if ($c -match '^(?<name>[A-Za-z0-9][A-Za-z0-9\.\-]+?)_\d+(?:\.\d+){1,5}_') {
            $matches['name']
        }
        elseif ($c -match '^(?<name>[A-Za-z0-9][A-Za-z0-9\.\-]+?)_[A-Za-z0-9]{8,20}$') {
            $matches['name']
        }
        else {
            $c
        }
    }

    $normalized |
        Where-Object { $_ -and $_.Length -gt 2 } |
        Sort-Object -Unique
}

Write-Log "Starting detection. LookbackDays=$LookbackDays MaxEvents=$MaxEvents"

$startTime = (Get-Date).AddDays(-1 * $LookbackDays)

# AppX deployment failures are documented in this log location
$events = Get-WinEvent -FilterHashtable @{
    LogName   = "Microsoft-Windows-AppXDeploymentServer/Operational"
    StartTime = $startTime
    Level     = 2   # Error
} -MaxEvents $MaxEvents

Write-Log "Retrieved $($events.Count) error events from AppXDeploymentServer"

$allEventPackages = New-Object System.Collections.Generic.List[string]

foreach ($evt in $events) {
    $names = Get-PackageNameFromMessage -Message $evt.Message
    if ($names) {
        foreach ($n in $names) {
            $allEventPackages.Add($n)
        }
    }
}

$allEventPackages = $allEventPackages | Sort-Object -Unique

Write-Log "Extracted package candidates from events: $($allEventPackages -join ', ')"

$actionable = New-Object System.Collections.Generic.List[object]

foreach ($pkgName in $allEventPackages) {
    try {
        $installed   = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue
        $provisioned = Get-AppxProvisionedPackage -Online | Where-Object {
            $_.DisplayName -eq $pkgName -or $_.PackageName -like "$pkgName*"
        }

        # Flag as actionable if it exists as an installed/provisioned app
        # or if there are clear failure events for it but it appears missing now.
        $obj = [PSCustomObject]@{
            Name              = $pkgName
            InstalledCount    = @($installed).Count
            ProvisionedCount  = @($provisioned).Count
            Actionable        = $true
        }

        $actionable.Add($obj)
        Write-Log "Candidate: $pkgName Installed=$(@($installed).Count) Provisioned=$(@($provisioned).Count)"
    }
    catch {
        Write-Log "Failed inspecting $pkgName : $($_.Exception.Message)"
    }
}

# Exclusions:
# - Microsoft Store removal is unsupported
$excludedPatterns = @(
    '^Microsoft\.StorePurchaseApp$',
    '^Microsoft\.WindowsStore$'
)

$final = $actionable | Where-Object {
    $name = $_.Name
    -not ($excludedPatterns | Where-Object { $name -match $_ })
} | Sort-Object Name -Unique

if ($final.Count -gt 0) {
    Write-Log "Remediation required for: $($final.Name -join ', ')"
    $final | ConvertTo-Json -Depth 4
    exit 1
}
else {
    Write-Log "No actionable UWP/AppX failures detected."
    "No actionable UWP/AppX failures detected."
    exit 0
}
