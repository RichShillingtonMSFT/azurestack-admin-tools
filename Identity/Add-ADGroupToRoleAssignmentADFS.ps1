[CmdletBinding()]
Param
(
    # Provide the Scope for the Role Assignment. Example: "/subscriptions/9c09ada1-2b7a-49cd-9185-f10125ae9cad"
    # Example: AzureStackAdmin
    [parameter(Mandatory=$true,HelpMessage='Provide the Scope for the Role Assignment. Example: "/subscriptions/9c09ada1-2b7a-49cd-9185-f10125ae9cad"')]
    [String]$Scope,

    # Provide the Active Directory SID of the Group you want to assign. 
    # Example: "5a061d3b-d02a-4277-94cf-db27c5219b48"
    [parameter(Mandatory=$true,HelpMessage='Provide the Active Directory SID of the Group you want to assign. Example: "5a061d3b-d02a-4277-94cf-db27c5219b48"')]
    [String]$GroupObjectSID,

    # Provide the Role Definition ID you want to add the group to. 
    # Example: "ed378474-9ff4-4455-9c36-4bbb504b7c03"
    [parameter(Mandatory=$true,HelpMessage='Provide the Role Definition ID you want to add the group to. Example: "ed378474-9ff4-4455-9c36-4bbb504b7c03"')]
    [String]$RoleDefinitionID,

    # Provide the Subscription ID where you want to add the Role Assignment. 
    # Example: "c7122d1d-a201-4c09-b396-54b36a0d94f1"
    [parameter(Mandatory=$true,HelpMessage='Provide the Subscription ID where you want to add the Role Assignment. Example: "c7122d1d-a201-4c09-b396-54b36a0d94f1"')]
    [String]$SubscriptionID,
    
    # Provide the Resource Manager Url. 
    # Example: https://adminmanagement.local.azurestack.external or https://management.local.azurestack.external
    [parameter(Mandatory=$true,HelpMessage='Provide the Resource Manager Url. Example: https://adminmanagement.local.azurestack.external or https://management.local.azurestack.external')]
    [String]$ResourceManagerUrl
)  

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

Add-ADGroup -GroupObjectSID $GroupObjectSID -RoleDefinitionID $RoleDefinitionID -Scope $Scope -SubscriptionID $SubscriptionID -Guid $Guid

