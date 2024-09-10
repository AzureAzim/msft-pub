#Convert-cidr function (thanks copilot)
function ConvertTo-CIDR {
    param (
        [string]$ipAddress,
        [string]$subnetMask
    )

    # Convert subnet mask to binary string
    $maskBytes = [System.Net.IPAddress]::Parse($subnetMask).GetAddressBytes()
    $binaryMask = [BitConverter]::ToUInt32($maskBytes, 0)
    $cidr = [Convert]::ToString($binaryMask, 2).ToCharArray() | Where-Object { $_ -eq '1' } | Measure-Object | Select-Object -ExpandProperty Count

    # Return IP address in CIDR notation
    return "$ipAddress/$cidr"
}
#source bypass rules
$importbypassrules = import-csv iboss_v2_pac.csv # CSV has Headers: Type (IP Mask, IP, FQDN)
#schema var
$ipRangeschema = "#microsoft.graph.networkaccess.ipRange"
$fqdnschema = "#microsoft.graph.networkaccess.fqdn"
$urlschema ="#microsoft.graph.networkaccess.url"
$ipschema = "#microsoft.graph.networkaccess.ipAddress"
$ipsubnetschema = "#microsoft.graph.networkaccess.ipSubnet"

#import requisite module
Import-Module Microsoft.Graph.Beta.NetworkAccess

#auth to graph
Connect-MgGraph -scope NetworkAccessPolicy.ReadWrite.All,NetworkAccess.ReadWrite.All

#get custom bypass rule ID
$custombypass = Get-MgBetaNetworkAccessForwardingPolicy | where {$_.name -eq "Custom Bypass"}

foreach ($importrule in $importbypassrules){
	#store row of data
	$type = $importrule.type
	$value = $importrule.value
	$mask = $importrule.mask
	#if else through rule types to  etup correct graph call parameters depending on IP, IP MASK, or FQDN
	if ($type -eq "IP with Mask"){
		$schema = $ipsubnetschema
		$ruletype = "ipSubnet"
		$cidr = ConvertTo-cidr -ipaddress $value -subnetmask $mask
		$value = $cidr
		}
	
	elseif ($type -eq "IP"){
		$schema = $ipschema
		$ruletype = "ipAddress"
		$value = $importrule.value
	}
	
	elseif ($type -eq "FQDN"){
		$schema = $fqdnschema
		$ruletype = "fqdn"
		$value = $cidr
	}
	#set graph call params
	$params = @{
		"@odata.type" = "#microsoft.graph.networkaccess.internetAccessForwardingRule"
		name = "Custom policy internet rule"
		ruleType = $ruletype
		action = "bypass"
		protocol = "tcp"
		ports = @(
			"80"
			"443"
		)
		destinations = @(
			@{
				"@odata.type" = $schema
				value = $value
	
			}
		)
	}
	New-MgBetaNetworkAccessForwardingPolicyRule -ForwardingPolicyId $custombypass.Id -BodyParameter $params

}
