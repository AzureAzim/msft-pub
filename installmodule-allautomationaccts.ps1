$subs = Get-AzSubscription
foreach ($sub in $subs) {
    
    $id = $sub.id
    Set-AzContext -SubscriptionId $id
    $autoaccts = Get-AzAutomationAccount
    foreach ($autoacct in $autoaccts ) {
        
        $acct = $acct.AutomationAccountName
        $rg = $acct.ResourceGroupName 
        New-AzAutomationModule -AutomationAccountName $acct -ResourceGroupName $rg -Name "Microsoft.RDInfra.RDPowershell" -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Microsoft.RDInfra.RDPowershell/1.0.1.7"
        
    } #automationacct loop
    
} #subs loop