<#
.SYNOPSIS
    Script to add the Azure Stack Operators Group as an Owner of the Tenant Management Subscription

.DESCRIPTION
    This script must be run on a workstation with access to the User Management ARM Endpoint.
    You must also be an owner of the subscription.
    You will need to query Active Directory using Get-ADGroup to retrieve the SID of the Group you wish to add.
    When prompted for the Environment, be sure to select the User Enviornment.

.PARAMETER StackHubRegionName
    Provide the Region Name of the Stack Hub.
    Example: WM01

.PARAMETER StackHubExternalDomainName
    Provide the Stack Hub External Domain Name.
    Example: Contoso.com

.PARAMETER GroupObjectSID
    Provide Active Directory Group Objects SID.
    Example: 'S-1-5-21-2541370298-4173347569-997948058-5620'

.EXAMPLE
    .\Configure-TenantManagmentUserSubscription.ps1 `
        -StackHubRegionName 'WM01' `
        -StackHubExternalDomainName 'Contoso.com' `
        -GroupObjectSID 'S-1-5-21-2541370298-4173347569-997948058-5620'
#>
[CmdletBinding()]
Param
(
    # Provide the Region Name of the Stack Hub. Example: WM01.
    # Example: 'WM01'
    [parameter(Mandatory=$true,HelpMessage='Provide the Region Name of the Stack Hub. Example: WM01')]
    [String]$StackHubRegionName,

    # Provide the Stack Hub External Domain Name.
    # Example: 'Contoso.com'
    [parameter(Mandatory=$false,HelpMessage='Provide the Stack Hub External Domain Name. Example: Contoso.com')]
    [String]$StackHubExternalDomainName = 'Contoso.com',

    # Provide Active Directory Group Objects SID.
    # Example: 'S-1-5-21-2541370298-4173347569-997948058-5620'
    [parameter(Mandatory=$false,HelpMessage='Provide Active Directory Group Objects SID. Example: S-1-5-21-2541370298-4173347569-997948058-5620')]
    [String]$GroupObjectSID = 'S-1-5-21-2541370298-4173347569-997948058-5620'
)

# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack User Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

try 
{
    $Subscription = Get-AzSubscription -SubscriptionName 'Azure Stack Operators Tenant Managment'
    Set-AzContext $Subscription
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$Location = Get-AzLocation
#endregion

$RoleDefinitionID = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

$Scope = '/subscriptions/' + $Subscription.Id

$ResourceManagerUrl = 'https://management.' + $StackHubRegionName + '.' + $StackHubExternalDomainName

$Guid = $((New-Guid).Guid)

function Invoke-CreateAuthHeader
{
    $AzureContext = Get-AzContext
    $AzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $ProfileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($AzureProfile)
    $Token = $ProfileClient.AcquireAccessToken($AzureContext.Subscription.TenantId)
    $AuthHeader = @{
        'Content-Type'='application/json'
        'Authorization'='Bearer ' + $Token.AccessToken
    }

    return $AuthHeader
}

function Add-ADGroup ($GroupObjectSID,$RoleDefinitionID,$Scope,$SubscriptionID,$Guid)
{
    $restUri = $ResourceManagerUrl + '/subscriptions/' + $SubscriptionID + '/providers/Microsoft.Authorization/roleAssignments/' + $Guid + '?api-version=2015-07-01'
    $AuthHeader = Invoke-CreateAuthHeader
    $Body = @"
    {
      "properties": {
        "roleDefinitionId": "/subscriptions/$SubscriptionID/providers/Microsoft.Authorization/roleDefinitions/$RoleDefinitionID",
        "PrincipalId": "$GroupObjectSID",
        "Scope": "$Scope"
      }
    }
"@

    $Response = Invoke-RestMethod -Uri $restUri -Method Put -Headers $AuthHeader -Body $Body
    return $Response
}

Add-ADGroup -GroupObjectSID $GroupObjectSID -RoleDefinitionID $RoleDefinitionID -Scope $Scope -SubscriptionID $Subscription.Id -Guid $Guid

$AssignableScopes = @()
$AzSubscriptions = Get-AzSubscription
[Int]$AzSubscriptionsCount = 1

Foreach ($AzSubscription in $AzSubscriptions)
{
    if ($AzSubscriptionsCount -lt $AzSubscriptions.Count)
    {
        $AssignableScopes += ('"' + '/subscriptions/' + $AzSubscription.Id + '",')
        $AzSubscriptionsCount ++
    }
    else
    {
        $AssignableScopes += ('"' + '/subscriptions/' + $AzSubscription.Id + '"')
    }
}

$ContributorLimitedNetworking = @"
{
    "Name": "Contributor Limited Networking",
    "Id": null,
    "IsCustom": true,
    "Description": "Role to allow contributor permissions while not allowing members to perform the following actions: Create or Update Virtual Network, Delete Virtual Network, Peer Virtual Networks, Create or Update Virtual Network Peering, Delete Virtual Network Peering, Create or Update Virtual Network Subnet, Delete Virtual Network Subnet.",
    "Actions": ["*"],
    "NotActions": [
        "Microsoft.Authorization/*/Delete",
        "Microsoft.Authorization/*/Write",
        "Microsoft.Network/virtualNetworks/peer/action",
        "Microsoft.Network/virtualNetworks/delete",
        "Microsoft.Network/virtualNetworks/write",
        "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write",
        "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/delete",
        "Microsoft.Network/virtualNetworks/subnets/delete",
        "Microsoft.Network/virtualNetworks/subnets/write"
    ],
    "AssignableScopes": [$AssignableScopes]
}
"@

New-Item -Path $env:TEMP -Name role.json -ItemType File -Value $ContributorLimitedNetworking -Force

New-AzRoleDefinition -InputFile "$env:TEMP\role.json"