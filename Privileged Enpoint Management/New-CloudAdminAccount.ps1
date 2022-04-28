<#
.SYNOPSIS
    Script to create a new Cloud Admin Account

.DESCRIPTION
    This script is used to create a new Cloud Admin Account.
    The current Cloud Admin Password is retrieved from a Key Vault Secret.
    The script will prompt you to login in with your Azure Stack Operator Credentials.
    You must then select the Subscription where the Admin Key Vault is stored.
    Example: Default Provider Subscription
    You will be prompted to enter a username and password for the new Cloud Admin Account.

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
    Example: @('10.0.0.1','10.0.0.2','10.0.0.3')

.EXAMPLE
    .\New-CloudAdminAccount.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName,

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
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select the Subscription where the Admin Key Vault is located." -PassThru
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
    $Secret = Get-AzureKeyVaultSecret -VaultName $AdminKeyVaultName -Name $CloudAdminSecretName -ErrorAction Stop
    $CloudAdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $CloudAdminUserName, $Secret.SecretValue -ErrorAction Stop
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$NewCloudAdminCredentials = Get-Credential -Message "Please enter the Username and Password for the new Cloud Admin Account"

$Session = New-PSSession -ComputerName (Get-Random -InputObject $PrivilegedEndpoints) -ConfigurationName PrivilegedEndpoint -Credential $CloudAdminCredential

Invoke-Command -Session $session {New-CloudAdminUser -UserName $Using:NewCloudAdminCredentials.UserName -Password $Using:NewCloudAdminCredentials.Password}

if ($Session)
{
    Remove-PSSession -Session $session
}
