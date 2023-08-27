<#
.SYNOPSIS
    Script to change the password for a Cloud Admin Account and store it in Key Vault

.DESCRIPTION
    This script is used to create a new Cloud Admin Account.
    The current Cloud Admin Password is retrieved from a Key Vault Secret.
    The script will prompt you to login in with your Azure Stack Operator Credentials.
    You must then select the Subscription where the Admin Key Vault is stored.
    Example: Default Provider Subscription
    You will be prompted to enter a username and password for the new Cloud Admin Account.

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'AzureStack\CloudAdmin'

.EXAMPLE
    .\Change-DefaultCloudAdminPassword.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'AzureStack\CloudAdmin'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'AzureStack\CloudAdmin'
)

$RegionInfo = @(
    [PSCustomObject]@{RegionName = 'Region1'; DRRegion = 'Region2'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'; TenantID = 'GUID'}
    [PSCustomObject]@{RegionName = 'Region2'; DRRegion = 'Region3'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'; TenantID = 'GUID'}
    [PSCustomObject]@{RegionName = 'Region3'; DRRegion = 'Region1'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'; TenantID = 'GUID'}
 )

$securePassword = ConvertTo-SecureString -String '' -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'SID', $securePassword

foreach ($Region in $RegionInfo[1])
{
    $KeyVaultName = $($Region.RegionName) + '-CloudAdmin-KeyVault'
    $CloudAdminSecretName = $($Region.RegionName) + '-CloudAdminCredential'

    # Connect to DR to get current CA account.
    # For Region2 test, connect to Region3
 
    # Enviornment Selection
    $Environment = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://management.$($Region.DRRegion)*"}

    #region Connect to Azure
    try
    {
        Connect-AzAccount -Environment $($Environment.Name) -ServicePrincipal -Credential $credential -TenantId $($Region.TenantID) -ErrorAction 'Stop'
    }
    catch
    {
        Write-Error -Message $_.Exception
        break
    }

    try 
    {
        $Subscription = Get-AzSubscription -SubscriptionName 'Subscription Name'
        Set-AzContext $Subscription
    }
    catch
    {
        Write-Error -Message $_.Exception
        break
    }

    $Location = Get-AzLocation
    #endregion

    # Get current cloud admin password
    $CurrentCloudAdminPassword = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CloudAdminSecretName -ErrorAction Stop).SecretValue
    $CurrentCloudAdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $CloudAdminUserName, $CurrentCloudAdminPassword

    # Generate New Cloud Admin Password
    Add-Type -AssemblyName System.Web
    $NewCloudAdminPassword = ConvertTo-SecureString -String ([System.Web.Security.Membership]::GeneratePassword(28,8)) -AsPlainText -Force

    Write-Host "Connnecting to Privileged Endpoint $($Region.PrivilegedEndpointIP)" -ForegroundColor Green
    $PEPSession = New-PSSession -ComputerName $($Region.PrivilegedEndpointIP) -ConfigurationName PrivilegedEndpoint -Credential $CurrentCloudAdminCredential -SessionOption (New-PSSessionOption -Culture en-US -UICulture en-US)

    $CloudAdminUserNameTemp = $CloudAdminUserName.Split('\')[1]
    Write-Host "Changing password for User $($CloudAdminUserName) on Privileged Endpoint $($Region.PrivilegedEndpointIP)" -ForegroundColor Green
    Invoke-Command -Session $PEPSession -ScriptBlock {Set-CloudAdminUserPassword -UserName $Using:CloudAdminUserNameTemp -CurrentPassword $Using:CurrentCloudAdminPassword -NewPassword $Using:NewCloudAdminPassword}

    Write-Host "Removing PSSession from Privileged Endpoint $($PrivilegedEndpoint)" -ForegroundColor Green
    Remove-PSSession $PEPSession

    # Set the new secret value
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CloudAdminSecretName -SecretValue $NewCloudAdminPassword | Out-Null
}

