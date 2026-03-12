# THis is a script that deploys an Azure Policy that injects a Cloud Shell PSProfile that adds Transcripts and timestamps to commands run
$policyName = "deploy-cloudshell-powershell-profile"
$policyDisplayName = "Deploy PowerShell profile to Cloud Shell storage accounts"
$policyDescription = "Ensures a default PowerShell profile is added when a Cloud Shell storage account is created."

$policyRule = @{
    if = @{
        allOf = @(
            @{ field = "type"; equals = "Microsoft.Storage/storageAccounts" },
            @{ field = "kind"; equals = "StorageV2" }
        )
    }
    then = @{
        effect = "deployIfNotExists"
        details = @{
            type = "Microsoft.Resources/deploymentScripts"
            roleDefinitionIds = @(
                "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
            )
            deployment = @{
                properties = @{
                    mode = "incremental"
                    template = @{
                        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
                        contentVersion = "1.0.0.0"
                        parameters = @{
                            storageAccountName = @{ type = "string" }
                            location = @{ type = "string" }
                        }
                        resources = @(
                            @{
                                type = "Microsoft.Resources/deploymentScripts"
                                apiVersion = "2020-10-01"
                                name = "[concat('seed-ps-profile-', parameters('storageAccountName'))]"
                                location = "[parameters('location')]"
                                kind = "AzurePowerShell"
                                properties = @{
                                    azPowerShellVersion = "10.4"
                                    retentionInterval = "P1D"
                                    timeout = "PT15M"
                                    scriptContent = @'
param([string]$storageAccountName)

$rg = $env:AZURE_RESOURCE_GROUP
$shareName = "cloudshell"

$sa = Get-AzStorageAccount -ResourceGroupName $rg -Name $storageAccountName -ErrorAction Stop
$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $storageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $key

$share = Get-AzStorageShare -Context $ctx -Name $shareName -ErrorAction SilentlyContinue
if (-not $share) { return }

New-AzStorageDirectory -ShareName $shareName -Path ".config" -Context $ctx -ErrorAction SilentlyContinue | Out-Null
New-AzStorageDirectory -ShareName $shareName -Path ".config/PowerShell" -Context $ctx -ErrorAction SilentlyContinue | Out-Null

$tmp = Join-Path $env:TEMP "Microsoft.PowerShell_profile.ps1"
@"
Set-PSReadLineOption -EditMode Windows

# Start one transcript per session to capture command/activity history.
if (-not $global:CloudShellTranscriptStarted) {
    $global:CloudShellTranscriptStarted = $true
    $transcriptPath = Join-Path $HOME ("cloudshell-transcript-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null
}

# Prefix each prompt with current timestamp.
function prompt {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] PS " + $(Get-Location) + "> "
}

Write-Host 'Cloud Shell profile loaded. Transcript started if available.' -ForegroundColor Green
"@ | Set-Content -Path $tmp -Encoding UTF8

Set-AzStorageFileContent `
  -ShareName $shareName `
  -Path ".config/PowerShell/Microsoft.PowerShell_profile.ps1" `
  -Source $tmp `
  -Context $ctx `
  -Force | Out-Null
'@
                                    arguments = "[concat('-storageAccountName ', parameters('storageAccountName'))]"
                                }
                            }
                        )
                    }
                    parameters = @{
                        storageAccountName = @{
                            value = "[field('name')]"
                        }
                        location = @{
                            value = "[field('location')]"
                        }
                    }
                }
            }
        }
    }
}

New-AzPolicyDefinition `
  -Name $policyName `
  -DisplayName $policyDisplayName `
  -Description $policyDescription `
  -Policy $policyRule `
  -Mode All
