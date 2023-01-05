#this two liner creates a UDR that allows you to direct AVD traffic directly to AVD services, thereby bypassing any traffic that would be forced elsewhere and drop the traffic.
#Useful when customers direct all traffic back on premises

$cfg = New-AzRouteConfig -Name "WindowsVirtualDesktopRoute" -AddressPrefix "WindowsVirtualDesktop" -NextHopType "Internet"
$routeTable = New-AzureRmRouteTable -ResourceGroupName w365poc -Location centralus -Name UDR-AVD -Route $cfg


