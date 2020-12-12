<#
.SYNOPSIS
    Script to create a new Cloud Admin Account

.DESCRIPTION
    This script is used to create a new Cloud Admin Account.
    The current Cloud Admin password is retrieved from a Key Vault Secret.
    The script will prompt you to login in with your Azure Stack Operator Credentials.
    You must then select the Subscription where the Admin Key Vault is stored.
    Example: Default Provider Subscription
    You will be prompted for a username and password for the new account.
    After the account is created, the credentials will be added to the Admin Key Vault.

.PARAMETER AdminKeyVaultName
    Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    Example: 'Admin-KeyVault'

.PARAMETER CloudAdminSecretName
    Provide the Secret Name as it appears in the Admin Key Vault.
    Example: 'CloudAdminCredential'

.PARAMETER PrivilegedEndpoints
    Define list of Privileged Endpoints as an Array.
    Example: @('10.0.0.1','10.0.0.2','10.0.0.3')

.EXAMPLE
    .\New-CloudAdminAccount.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    # Example: 'Admin-KeyVault'
    [parameter(Mandatory=$false,HelpMessage='Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.')]
    [String]$AdminKeyVaultName = 'Admin-KeyVault',

    # Provide the Secret Name as it appears in the Admin Key Vault.
    # Example: 'CloudAdminCredential'
    [parameter(Mandatory=$false,HelpMessage='Provide the Secret Name as it appears in the Admin Key Vault.')]
    [String]$CloudAdminSecretName = 'CloudAdminCredential',

    # Define list of Privileged Endpoints as an Array.
    # Example: @("10.0.0.1","10.0.0.2","10.0.0.3")
    [parameter(Mandatory=$false,HelpMessage='Define list of Privileged Endpoints as an Array. Example: @("10.0.0.1","10.0.0.2","10.0.0.3")')]
    [Array]$PrivilegedEndpoints = @("10.0.0.1","10.0.0.2","10.0.0.3")
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
    $Subscriptions = Get-AzureRmSubscription
    if ($Subscriptions.Count -gt '1')
    {
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select the Subscription where the Admin Key Vault is located." -PassThru
        Select-AzureRmSubscription $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

try
{
    $Secret = Get-AzureKeyVaultSecret -VaultName $AdminKeyVaultName -Name $CloudAdminSecretName -ErrorAction Stop
    $CloudAdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $CloudAdminUserName, $Secret.SecretValue -ErrorAction Stop
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$NewCloudAdminCredentials = Get-Credential -Message 'Please provide the Username & Password for the new Cloud Admin Account'

Invoke-Command -ConfigurationName PrivilegedEndpoint `
    -ComputerName (Get-Random -InputObject $PrivilegedEndpoints) `
    -ScriptBlock { New-CloudAdminUser -UserName $Using:NewCloudAdminCredentials.UserName  -Password $Using:NewCloudAdminCredentials.Password }  `
    -Credential  $CloudAdminCredential

$KeyVault = Get-AzureRmKeyVault -VaultName $AdminKeyVaultName
Set-AzureKeyVaultSecret -VaultName $KeyVault.VaultName -Name $($NewCloudAdminCredentials.UserName) -SecretValue $NewCloudAdminCredentials.Password
