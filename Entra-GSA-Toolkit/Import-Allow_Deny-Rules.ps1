#import CSV Data, #CSV Headers needed are Url, Note
$denylist = import-csv .\Group2-iboss-block-list.csv
$allowlist = import-csv Group2-iboss-allow-list.csv

#import requisite module
Import-Module Microsoft.Graph.Beta.NetworkAccess

#auth to graph
Connect-MgGraph -scope NetworkAccessPolicy.ReadWrite.All,NetworkAccess.ReadWrite.All
#setup schema values
$ipRangeschema = "#microsoft.graph.networkaccess.ipRange"
$fqdnschema = "#microsoft.graph.networkaccess.fqdn"
$urlschema ="#microsoft.graph.networkaccess.url"
$ipschema = "#microsoft.graph.networkaccess.ipAddress"
$ipsubnetschema = "#microsoft.graph.networkaccess.ipSubnet"

#gather policy IDs, it is recommended to make an allow list, and block list for this import.
$blockpolicy = "d6ee7e11-76be-48de-8f09-b832d5818a9c"
$allowpolicy = "4aecccb4-6fca-4155-8f07-f7e1293a9c20"
$myblockpolicy = Get-MgBetaNetworkAccessFilteringPolicy -FilteringPolicyId $blockpolicy
$myallowpolicy = Get-MgBetaNetworkAccessFilteringPolicy -FilteringPolicyId $allowpolicy

#store policy as filteringpolicyid
$blockfilteringPolicyId = $myblockpolicy.Id
$allowfilteringpolicyid = $myallowpolicy.Id

#loop through denylist and make the rules
foreach ($rule in $denylist) { 

    $url = "https://" + $rule.url
    $note = $rule.note
$params = @{
	"@odata.type" = "#microsoft.graph.networkaccess.FilteringRule"
	name = $note
	ruleType = "url"
	destinations = @(
		@{
			"@odata.type" = $urlschema
			value = $url
		}
	)
}
New-MgBetaNetworkAccessFilteringPolicyRule -FilteringPolicyId $blockfilteringPolicyId -BodyParameter $params
}
#loop through allowlist and make the rules
foreach ($rule in $allowlist) { 
    $url = "https://" + $rule.url
    $note = $rule.note
$params = @{
	"@odata.type" = "#microsoft.graph.networkaccess.FilteringRule"
	name = $note
	ruleType = "url"
	destinations = @(
		@{
			"@odata.type" = $urlschema
			value = $url
		}
	)
}
New-MgBetaNetworkAccessFilteringPolicyRule -FilteringPolicyId $allowfilteringpolicyid -BodyParameter $params
}

