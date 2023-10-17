[CmdletBinding()]
parameters
(
    [parameter(Mandatory=$true,HelpMessage='Provide the prefix required. Example: Dev-* ')]
    [String]$RequiredPrefix,

    [parameter(Mandatory=$true,HelpMessage='Provide the Subscription Name where the policy will be applied. Example: Dev-* ')]
    [String]$SubscriptionName,

    [parameter(Mandatory=$true,HelpMessage='Provide the Azure Stack Hub Region Name. Example: HUB01 ')]
    [String]$RegionName,

    [parameter(Mandatory=$true,HelpMessage='Provide the Azure Stack DNS Domain. Example: contoso.local ')]
    [String]$AzureStackDNSDomain
)

Import-Module 'C:\Program Files\WindowsPowerShell\Modules\AzureStack-Tools-az\Policy\AzureStack.Policy.psm1'

$AzureStackDomainFQDN = $RegionName + '.' $AzureStackDNSDomain
$UserEnvironmentName = $RegionName + '-AzS-User'
Add-AzEnvironment -Name $UserEnvironmentName -ARMEndpoint ('https://management.' + $AzureStackDomainFQDN)

$PolicyName = 'Enforce_Name_Prefix'
$PolicyDisplayName = 'Enforce Naming Prefix'
$PolicyDescription = 'This policy will ensure that all Virtual Machines, Storage Accounts & Key Vaults begin with the specified prefix.'
$PolciyParameters = @{'prefix' = "$RequiredPrefix"}

$Policy = @'
{
    "mode": "All",
    "parameters": {
      "prefix" : {
        "type" : "string",
        "metadata" : {
          "description" : "Provide the required prefix. This can include a wildcard. Example: Dev-*"
        }
      }
    },
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "name",
            "notLike": "[parameters('prefix')]"
          },
          {
            "anyOf" : [
              {
                "field": "type",
                "equals": "Microsoft.KeyVault/vaults"
              },
              {
                "field": "type",
                "equals": "Microsoft.Storage/storageAccounts"
              },
              {
                "field": "type",
                "equals": "Microsoft.Compute/virtualMachines"
              }
            ]
          }
        ]
      },
      "then": {
        "effect": "deny"
      }
    }
}
'@

Connect-AzAccount -Environment $UserEnvironmentName

try
{
    $Subscription = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop
}
catch
{
    Write-host "Could not find Subscription $($SubscriptionName)" -ForegroundColor Red
    Write-host "Ensure the Subscription Name is correct and you have the proper permissions to access it, then try again." -ForegroundColor Red
    break
}

Set-AzContext $Subscription

New-AzPolicyDefinition -Name $PolicyName -DisplayName $PolicyDisplayName -Description $PolicyDescription -Policy $Policy

$PolicyDefinition = Get-AzPolicyDefinition -Name $PolicyName

New-AzPolicyAssignment -Name $PolicyName -PolicyDefinition $PolicyDefinition -Scope "/subscriptions/$($Subscription.Id)" -PolciyParameterObject $PolciyParameters
