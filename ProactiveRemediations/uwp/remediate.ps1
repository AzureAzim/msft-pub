# Remediate-UWPAppFailures.ps1

[CmdletBinding()]
param(
    [string]$RepoRoot = "C:\Offline\APPXs",
    [int]$LookbackDays = 7,
    [int]$MaxEvents = 2000,
    [string]$LogPath = "C:\ProgramData\UWPRepair\Remediate-UWPAppFailures.log"
)

$ErrorActionPreference = "Continue"

# Ensure log folder exists
$logDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [Remediate] $Message" | Tee-Object -FilePath $LogPath -Append
}

function Get-PackageNameFromMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $null }

    $candidates = New-Object System.Collections.Generic.List[string]

    $fullPattern = '(?<pkg>[A-Za-z0-9][A-Za-z0-9\.\-]+?_\d+(?:\.\d+){1,5}_[A-Za-z0-9\.\-~]+(?:__[A-Za-z0-9]+|_[A-Za-z0-9]+))'
    $fullMatches = [regex]::Matches($Message, $fullPattern)
    foreach ($m in $fullMatches) {
        $pkg = $m.Groups['pkg'].Value
        if ($pkg) { $candidates.Add($pkg) }
    }

    $familyPattern = '(?<fam>[A-Za-z0-9][A-Za-z0-9\.\-]+?_[A-Za-z0-9]{8,20})'
    $familyMatches = [regex]::Matches($Message, $familyPattern)
    foreach ($m in $familyMatches) {
        $fam = $m.Groups['fam'].Value
        if ($fam) { $candidates.Add($fam) }
    }

    $pathPattern = '(?:WindowsApps|SystemApps)\\(?<name>[A-Za-z0-9][A-Za-z0-9\.\-]+?)_(?<ver>\d+(?:\.\d+){1,5})_'
    $pathMatches = [regex]::Matches($Message, $pathPattern)
    foreach ($m in $pathMatches) {
        $name = $m.Groups['name'].Value
        if ($name) { $candidates.Add($name) }
    }

    if ($candidates.Count -eq 0) { return $null }

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

function Get-FailingPackages {
    param(
        [int]$LookbackDays,
        [int]$MaxEvents
    )

    $startTime = (Get-Date).AddDays(-1 * $LookbackDays)

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = "Microsoft-Windows-AppXDeploymentServer/Operational"
        StartTime = $startTime
        Level     = 2
    } -MaxEvents $MaxEvents

    $pkgs = New-Object System.Collections.Generic.List[string]
    foreach ($evt in $events) {
        $names = Get-PackageNameFromMessage -Message $evt.Message
        if ($names) {
            foreach ($n in $names) { $pkgs.Add($n) }
        }
    }

    $excludedPatterns = @(
        '^Microsoft\.StorePurchaseApp$',
        '^Microsoft\.WindowsStore$'
    )

    return $pkgs |
        Sort-Object -Unique |
        Where-Object { -not ($excludedPatterns | Where-Object { $_ -and ($_ -as [string]) -and ($_ -match '.') -and ($PSItem -match $_) }) }
}

function Find-PackagePayload {
    param(
        [string]$RepoRoot,
        [string]$PackageName
    )

    # Search broadly for the main bundle/package by filename
    $main = Get-ChildItem -Path $RepoRoot -Recurse -File -Include *.msixbundle,*.appxbundle,*.msix,*.appx -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match [regex]::Escape($PackageName) -or $_.DirectoryName -match [regex]::Escape($PackageName)
        } |
        Sort-Object FullName |
        Select-Object -First 1

    if (-not $main) { return $null }

    $depFolder = Join-Path $main.DirectoryName "Dependencies"
    $deps = @()

    if (Test-Path $depFolder) {
        $deps = Get-ChildItem -Path $depFolder -Recurse -File -Include *.appx,*.msix -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    else {
        # Fallback: any dependency-looking packages in same tree except main file
        $deps = Get-ChildItem -Path $main.DirectoryName -Recurse -File -Include *.appx,*.msix -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $main.FullName } |
            Select-Object -ExpandProperty FullName
    }

    [PSCustomObject]@{
        Main = $main.FullName
        Dependencies = @($deps)
    }
}

Write-Log "Starting remediation. RepoRoot=$RepoRoot LookbackDays=$LookbackDays MaxEvents=$MaxEvents"

if (-not (Test-Path $RepoRoot)) {
    Write-Log "Offline repository not found: $RepoRoot"
    throw "Offline repository not found: $RepoRoot"
}

$targets = Get-FailingPackages -LookbackDays $LookbackDays -MaxEvents $MaxEvents

if (-not $targets -or $targets.Count -eq 0) {
    Write-Log "No failing packages found. Nothing to remediate."
    "No failing packages found. Nothing to remediate."
    exit 0
}

Write-Log "Targets: $($targets -join ', ')"

foreach ($pkgName in $targets) {
    Write-Log "----- Processing $pkgName -----"

    try {
        $installed = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue
        $provisioned = Get-AppxProvisionedPackage -Online | Where-Object {
            $_.DisplayName -eq $pkgName -or $_.PackageName -like "$pkgName*"
        }

        # Skip non-removable installed packages
        $nonRemovable = $false
        if ($installed) {
            if (@($installed | Where-Object { $_.NonRemovable -eq $true }).Count -gt 0) {
                $nonRemovable = $true
            }
        }

        if ($nonRemovable) {
            Write-Log "Skipping $pkgName because at least one installed instance is NonRemovable."
            continue
        }

        $payload = Find-PackagePayload -RepoRoot $RepoRoot -PackageName $pkgName
        if (-not $payload) {
            Write-Log "No offline payload found for $pkgName under $RepoRoot"
            continue
        }

        Write-Log "Main package: $($payload.Main)"
        if ($payload.Dependencies.Count -gt 0) {
            Write-Log "Dependencies: $($payload.Dependencies -join '; ')"
        }
        else {
            Write-Log "No dependencies found"
        }

        # Remove installed package registrations for all users
        if ($installed) {
            foreach ($item in $installed) {
                try {
                    Write-Log "Removing installed package: $($item.PackageFullName)"
                    Remove-AppxPackage -Package $item.PackageFullName -AllUsers -ErrorAction Stop
                }
                catch {
                    Write-Log "Remove-AppxPackage failed for $($item.PackageFullName): $($_.Exception.Message)"
                }
            }
        }

        # Remove provisioned package if present
        if ($provisioned) {
            foreach ($p in $provisioned) {
                try {
                    Write-Log "Removing provisioned package: $($p.PackageName)"
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Log "Remove-AppxProvisionedPackage failed for $($p.PackageName): $($_.Exception.Message)"
                }
            }
        }

        # Re-provision the package
        try {
            if ($payload.Dependencies.Count -gt 0) {
                Write-Log "Adding provisioned package with dependencies for $pkgName"
                Add-AppxProvisionedPackage `
                    -Online `
                    -PackagePath $payload.Main `
                    -DependencyPackagePath $payload.Dependencies `
                    -SkipLicense `
                    -ErrorAction Stop | Out-Null
            }
            else {
                Write-Log "Adding provisioned package without dependencies for $pkgName"
                Add-AppxProvisionedPackage `
                    -Online `
                    -PackagePath $payload.Main `
                    -SkipLicense `
                    -ErrorAction Stop | Out-Null
            }

            Write-Log "Provisioning succeeded for $pkgName"
        }
        catch {
            Write-Log "Add-AppxProvisionedPackage failed for $pkgName: $($_.Exception.Message)"
            continue
        }
    }
    catch {
        Write-Log "Unhandled failure while processing $pkgName : $($_.Exception.Message)"
    }
}

Write-Log "Remediation finished. A reboot/sign-out may still be needed for some existing user sessions."
"Remediation finished."
exit 0
`
