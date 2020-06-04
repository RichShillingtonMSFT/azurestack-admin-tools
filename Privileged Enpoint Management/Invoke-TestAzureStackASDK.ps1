<#
.SYNOPSIS
    Script to run Test-AzureStack on a Privileged Endpoint

.DESCRIPTION
    This script run Test-AzureStack on a Privileged Endpoint without entering the CloudAdmin User Password.
    The Password is retrieved from a Key Vault Secret.
    The script will prompt you to login in with your Azure Stack Operator Credentials.
    You must then select the Subscription where the Admin Key Vault is stored.
    Example: Default Provider Subscription

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'CloudAdmin@azurestack.local'

.PARAMETER AdminKeyVaultName
    Provide the name of the Admin Key Vault where the CloudAdmin Credentials are stored.
    Example: 'Admin-KeyVault'

.PARAMETER CloudAdminSecretName
    Provide the Secret Name as it appears in the Admin Key Vault.
    Example: 'CloudAdminCredential'

.PARAMETER PrivilegedEndpoints
    Define list of Privileged Endpoints as an Array.
    Example: @('AZS-ERCS01')

.EXAMPLE
    .\Invoke-TestAzureStackASDK.ps1
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

    # Define list of Privileged Endpoints as an Array.
    # Example: @('AZS-ERCS01')
    [parameter(Mandatory=$false,HelpMessage='Define list of Privileged Endpoints as an Array. Example: @("10.0.0.1","10.0.0.2","10.0.0.3")')]
    [Array]$PrivilegedEndpoints = @('AZS-ERCS01')
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

$Session = New-PSSession -ComputerName (Get-Random -InputObject $PrivilegedEndpoints) -ConfigurationName PrivilegedEndpoint -Credential $CloudAdminCredential
Invoke-Command $Session {Test-AzureStack}