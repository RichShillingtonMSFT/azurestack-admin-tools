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
    $Subscriptions = Get-AzSubscription
    if ($Subscriptions.Count -gt '1')
    {
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
        Set-AzContext $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

$CloudAdminCredential = $host.ui.PromptForCredential("", 'Please provide the Cloud Admin Password to store in the Key Vault', "CloudAdmin", "")

$Location = (Get-AzLocation).Location

if (!(Get-AzKeyVault -VaultName $AdminKeyVaultName))
{
    if (!(Get-AzResourceGroup $AdminKeyVaultResourceGroupName -ErrorAction SilentlyContinue))
    {
        New-AzResourceGroup -Name $AdminKeyVaultResourceGroupName -Location $Location
    }

    $KeyVault = New-AzKeyVault -VaultName $AdminKeyVaultName -ResourceGroupName $AdminKeyVaultResourceGroupName -Location $Location
}
else 
{
    $KeyVault = Get-AzKeyVault -VaultName $AdminKeyVaultName -ResourceGroupName $AdminKeyVaultResourceGroupName
}

Set-AzKeyVaultSecret -VaultName $KeyVault.VaultName -Name $CloudAdminSecretName -SecretValue $CloudAdminCredential.Password