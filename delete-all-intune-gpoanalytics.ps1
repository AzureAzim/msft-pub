# Delete all Group Policy Analytics entries from Intune via Microsoft Graph
# Usage: .\Delete-GroupPolicyAnalytics.ps1 [-ResourcePath <path>] [-Force]
param(
    [string]$ResourcePath = "deviceManagement/groupPolicyAnalytics",
    [switch]$Force
)

# Authenticate (will prompt)
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

$baseUrl = "https://graph.microsoft.com/v1.0/$ResourcePath"
$next = $baseUrl

while ($next) {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $next
    if (-not $resp.value -or $resp.value.Count -eq 0) { break }

    foreach ($item in $resp.value) {
        if (-not $item.id) { continue }
        $deleteUri = "$baseUrl/$($item.id)"

        if (-not $Force) {
            $ans = Read-Host "Delete $deleteUri ? (Y/N)"
            if ($ans -notin @('Y','y')) { continue }
        }

        try {
            Invoke-MgGraphRequest -Method DELETE -Uri $deleteUri
            Write-Output "Deleted: $deleteUri"
        } catch {
            Write-Warning "Failed to delete $deleteUri : $_"
        }
    }

    $next = $resp.'@odata.nextLink'
}
