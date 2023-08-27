<#
.SYNOPSIS
    Script to add the Azure Stack Operators Group as an Owner of the Default Provider Subscription.

.DESCRIPTION
    This script must be run on a workstation with access to the Admin Management ARM Endpoint.
    You must also have the credentials of the Service Admin Account.
    You will need to query Active Directory using Get-ADGroup to retrieve the SID of the Group you wish to add.
    When prompted for the Environment, be sure to select the ADMIN Enviornment.
    The script will select the Default Provider Subscription as default.

.PARAMETER StackHubRegionName
    Provide the Region Name of the Stack Hub.
    Example: HUB01

.PARAMETER StackHubExternalDomainName
    Provide the Stack Hub External Domain Name.
    Example: Contoso.com

.PARAMETER GroupObjectSID
    Provide Active Directory Group Objects SID.
    Example: 'S-2-5-29-2541370298-4173678118-997948033-4567'

.EXAMPLE
    .\Add-OperatorsGroupToOwnerRoleDefaultProviderSubscription.ps1 `
        -StackHubRegionName 'HUB01' `
        -StackHubExternalDomainName 'Contoso.com' `
        -GroupObjectSID 'S-2-5-29-2541370298-4173678118-997948033-4567'
#>
[CmdletBinding()]
Param
(
    # Provide the Region Name of the Stack Hub. Example: HUB01.
    # Example: 'HUB01'
    [parameter(Mandatory=$true,HelpMessage='Provide the Region Name of the Stack Hub. Example: HUB01')]
    [String]$StackHubRegionName,

    # Provide the Stack Hub External Domain Name.
    # Example: 'Contoso.com'
    [parameter(Mandatory=$false,HelpMessage='Provide the Stack Hub External Domain Name. Example: Contoso.com')]
    [String]$StackHubExternalDomainName = 'Contoso.com',

    # Provide Active Directory Group Objects SID.
    # Example: 'S-2-5-29-2541370298-4173678118-997948033-4567'
    [parameter(Mandatory=$false,HelpMessage='Provide Active Directory Group Objects SID. Example: S-2-5-29-2541370298-4173678118-997948033-4567')]
    [String]$GroupObjectSID = 'S-2-5-29-2541370298-4173678118-997948033-4567'
)

# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack Admin Enviornment." -PassThru

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
    $Subscription = Get-AzSubscription -SubscriptionName 'Default Provider Subscription'
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

$Scope = '/subscriptions/' + $Subscription

$ResourceManagerUrl = 'https://adminmanagement.' + $StackHubRegionName + '.' + $StackHubExternalDomainName

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