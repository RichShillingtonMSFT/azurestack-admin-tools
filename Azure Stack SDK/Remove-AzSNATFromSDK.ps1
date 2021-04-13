<#
.SYNOPSIS
    Script to remove the NAT from Azure Stack SDK

.DESCRIPTION
    This script can be used to remove the NAT from the Azure Stack SDK.
    This will expose the SDK to your network, allowing you to connect without VPN.

    Routes would need to be added to either your workstation or router.
    route add 192.168.200.0 mask 255.255.255.0 [IP of the ASDK]
    route add 192.168.100.0 mask 255.255.255.224 [IP of the ASDK]
    route add 192.168.101.0 mask 255.255.255.192 [IP of the ASDK]
    route add 192.168.102.0 mask 255.255.255.0 [IP of the ASDK]
    route add 192.168.103.0 mask 255.255.255.128 [IP of the ASDK]
    route add 192.168.104.0 mask 255.255.255.128 [IP of the ASDK]

    You can use this script to add the routes.
    $Range = 100..104
    foreach ($R in $Range) {Route add -p "192.168.$($R).0" mask 255.255.255.0 192.168.1.15}
    Route add -p 192.168.200.0 mask 255.255.255.0 192.168.1.15


    You also need to export the certificates from the ASDK Hosts Trusted Root Certificate Authorities Store
    and import them in to you machine store in the same location to avoid connection errors.
    AzureStackCertificateAuthority.cer
    AzureStackSelfSignedRootCert.cer

    Finally you need to add DNS conditional forwarders to resolve Azure Stack zones.
    DNS forwarding for azurestack.local to 192.168.200.224
    DNS forwarding for internal.azurestack.local to 192.168.200.224
    DNS forwarding for local.azurestack.external to 192.168.200.224
    DNS forwarding for local.cloudapp.azurestack.external 192.168.200.224 (after installing WebApps)

    Or set the DNS on your client to point to 192.168.200.224

.EXAMPLE
    .\Remove-AzSNATFromSDK.ps1
#>

$Interface = Get-NetIPInterface -InterfaceAlias Deployment
$IPAdressInfo = Get-NetIPAddress -InterfaceIndex $Interface.ifIndex
$NetworkInfo = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction Stop | Where-Object {$_.IpAddress -like "*$($IPAdressInfo.IPAddress)*"}

Get-NetNat | Remove-NetNat

New-NetIPAddress -InterfaceAlias Deployment -IPAddress $IPAdressInfo.IPAddress -PrefixLength $IPAdressInfo.PrefixLength
Set-DnsClientServerAddress -InterfaceAlias Deployment -ServerAddresses $NetworkInfo.DNSServerSearchOrder