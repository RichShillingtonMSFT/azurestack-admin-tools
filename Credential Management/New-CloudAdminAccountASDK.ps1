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

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'CloudAdmin@azurestack.local'

.PARAMETER AdminKeyVaultName
    Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    Example: 'Admin-KeyVault'

.PARAMETER CloudAdminSecretName
    Provide the Secret Name as it appears in the Admin Key Vault.
    Example: 'CloudAdminCredential'

.PARAMETER PrivilegedEndpoint
    Provide the Privileged Endpoint Name or IP.
    Example: 'AZS-ERCS01'

.EXAMPLE
    .\New-CloudAdminAccountASDK.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'CloudAdmin@azurestack.local',
    
    # Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    # Example: 'Admin-KeyVault'
    [parameter(Mandatory=$false,HelpMessage='Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.')]
    [String]$AdminKeyVaultName = 'Admin-KeyVault',

    # Provide the Secret Name as it appears in the Admin Key Vault.
    # Example: 'CloudAdminCredential'
    [parameter(Mandatory=$false,HelpMessage='Provide the Secret Name as it appears in the Admin Key Vault.')]
    [String]$CloudAdminSecretName = 'CloudAdminCredential',

    # Define Privileged Endpoint
    # Example: 'AZS-ERCS01'
    [parameter(Mandatory=$false,HelpMessage='Define Privileged Endpoint. Example: AZS-ERCS01')]
    [String]$PrivilegedEndpoint = 'AZS-ERCS01'
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

try
{
    $Secret = Get-AzKeyVaultSecret -VaultName $AdminKeyVaultName -Name $CloudAdminSecretName -ErrorAction Stop
    $CloudAdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $CloudAdminUserName, $Secret.SecretValue -ErrorAction Stop
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$NewCloudAdminCredentials = Get-Credential -Message 'Please provide the Username & Password for the new Cloud Admin Account'

Invoke-Command -ConfigurationName PrivilegedEndpoint `
    -ComputerName $PrivilegedEndpoint `
    -ScriptBlock { New-CloudAdminUser -UserName $Using:NewCloudAdminCredentials.UserName  -Password $Using:NewCloudAdminCredentials.Password }  `
    -Credential  $CloudAdminCredential

$KeyVault = Get-AzKeyVault -VaultName $AdminKeyVaultName
Set-AzKeyVaultSecret -VaultName $KeyVault.VaultName -Name $($NewCloudAdminCredentials.UserName) -SecretValue $NewCloudAdminCredentials.Password
