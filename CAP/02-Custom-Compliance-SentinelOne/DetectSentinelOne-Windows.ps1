[CmdletBinding()]
param()

# Intune custom compliance scripts must write a JSON object to stdout with keys that match
# the SettingName values in the companion rules file. This script checks whether SentinelOne
# appears to be installed and whether a SentinelOne-related service is currently running.
#
# IMPORTANT:
# - Exact SentinelOne service names and registry paths can vary by agent version and packaging.
# - Validate and adjust the candidate service names/paths below against your organization's
#   actual SentinelOne deployment before assigning the policy broadly.
# - Avoid writing anything except the final JSON object to stdout.

$ErrorActionPreference = 'SilentlyContinue'

$candidateServiceNames = @(
    'SentinelAgent',
    'SentinelServiceHelper'
)

$candidateRegistryPaths = @(
    'HKLM:\SOFTWARE\Sentinel Labs\Sentinel Agent',
    'HKLM:\SOFTWARE\WOW6432Node\Sentinel Labs\Sentinel Agent'
)

$uninstallRegistryRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# First, look for known SentinelOne service names.
$namedServices = foreach ($serviceName in $candidateServiceNames) {
    Get-Service -Name $serviceName
}

# Next, look for services whose display name or service name suggests SentinelOne.
$patternServices = Get-CimInstance -ClassName Win32_Service |
    Where-Object {
        $_.Name -match 'Sentinel' -or
        $_.DisplayName -match 'SentinelOne|Sentinel Agent|Sentinel'
    }

$allCandidateServices = @($namedServices + $patternServices) |
    Where-Object { $_ } |
    Sort-Object -Property Name -Unique

# Registry-based install detection.
$registryInstallFound = $false
foreach ($path in $candidateRegistryPaths) {
    if (Test-Path -Path $path) {
        $registryInstallFound = $true
        break
    }
}

# Uninstall-entry fallback detection.
$uninstallEntryFound = $false
foreach ($root in $uninstallRegistryRoots) {
    $match = Get-ItemProperty -Path $root |
        Where-Object {
            $_.DisplayName -match 'SentinelOne|Sentinel Agent|Sentinel'
        } |
        Select-Object -First 1

    if ($match) {
        $uninstallEntryFound = $true
        break
    }
}

$sentinelInstalled = ($allCandidateServices.Count -gt 0) -or $registryInstallFound -or $uninstallEntryFound

$runningService = $allCandidateServices |
    Where-Object {
        $_.State -eq 'Running' -or $_.Status -eq 'Running'
    } |
    Select-Object -First 1

$sentinelServiceRunning = $null -ne $runningService

$result = [ordered]@{
    SentinelOneInstalled = [bool]$sentinelInstalled
    SentinelOneServiceRunning = [bool]$sentinelServiceRunning
}

$result | ConvertTo-Json -Compress
