<#
.SYNOPSIS
    Script to create the Admin Key Vault

.DESCRIPTION
    This script is used to create the Admin Key Vault in the Default Provider Subscription.
    If the Resource Group and/or Key Vault does not exist, it will be created.
    The script will create a secret to store the Cloud Admin Password.
    The script will prompt you to login in with your Azure Stack Operator Credentials.

.PARAMETER AdminKeyVaultName
    Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    Example: 'Admin-KeyVault'

.PARAMETER AdminKeyVaultResourceGroupName
    Provide the Resource Group Name for the Admin Key Vault where the CloudAdmin Credentials will be stored.
    Example: 'RG-Admin-KV'

.PARAMETER CloudAdminSecretName
    Provide the Secret Name as it appears in the Admin Key Vault.
    Example: 'CloudAdminCredential'

.EXAMPLE
    .\Create-AzureStackAdminKeyVault.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    # Example: 'Admin-KeyVault'
    [parameter(Mandatory=$false,HelpMessage='Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.')]
    [String]$AdminKeyVaultName = 'Admin-KeyVault',

    # Provide the Resource Group Name for the Admin Key Vault where the CloudAdmin Credentials will be stored.
    # Example: 'RG-Admin-KV'
    [parameter(Mandatory=$false,HelpMessage='Provide the Resource Group Name for the Admin Key Vault where the CloudAdmin Credentials will be stored.')]
    [String]$AdminKeyVaultResourceGroupName = 'RG-Admin-KV',

    # Provide the Secret Name as it appears in the Admin Key Vault.
    # Example: 'CloudAdminCredential'
    [parameter(Mandatory=$false,HelpMessage='Provide the Secret Name as it appears in the Admin Key Vault.')]
    [String]$CloudAdminSecretName = 'CloudAdminCredential'
)

# Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack Admin Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzureRmAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

try 
{
    $Subscription = Get-AzureRmSubscription -SubscriptionName 'Default Provider Subscription'
    Select-AzureRmSubscription $Subscription
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

$CloudAdminCredential = $host.ui.PromptForCredential("", 'Please provide the Cloud Admin Password to store in the Key Vault', "CloudAdmin", "")

$Location = Get-AzsLocation -WarningAction SilentlyContinue

if (!(Get-AzureRmKeyVault -VaultName $AdminKeyVaultName))
{
    if (!(Get-AzureRmResourceGroup $AdminKeyVaultResourceGroupName -ErrorAction SilentlyContinue))
    {
        New-AzureRmResourceGroup -Name $AdminKeyVaultResourceGroupName -Location $Location.Name
    }

    $KeyVault = New-AzureRmKeyVault -VaultName $AdminKeyVaultName -ResourceGroupName $AdminKeyVaultResourceGroupName -Location $Location.Name
}
else 
{
    $KeyVault = Get-AzureRmKeyVault -VaultName $AdminKeyVaultName -ResourceGroupName $AdminKeyVaultResourceGroupName
}

Set-AzureKeyVaultSecret -VaultName $KeyVault.VaultName -Name $CloudAdminSecretName -SecretValue $CloudAdminCredential.Password