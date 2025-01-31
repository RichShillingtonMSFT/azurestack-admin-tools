﻿<#
.SYNOPSIS
    Script to get Azure Stack Update Progess

.DESCRIPTION
    Use this to get Azure Stack Update Progess and display it in a readable window from Privileged Endpoint without entering the CloudAdmin User Password.
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
    Example: @('10.0.0.1','10.0.0.2','10.0.0.3')

.EXAMPLE
    .\Get-AzureStackUpdateProgress.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'CloudAdmin@Azurestack.local',

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
    [Array]$PrivilegedEndpoints = @('10.0.0.1','10.0.0.2','10.0.0.3')
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

[XML]$Status = Invoke-Command $Session {Get-AzureStackUpdateStatus}

$Status.SelectNodes("//Step") | Select-Object Name,Description,Status | Where-Object {($_.Status -ne 'Success') -and ($_.Status -ne 'Skipped')} | Format-Table -Wrap -AutoSize

[Int]$TotalSteps = $($Status.SelectNodes("//Step")).Count

Write-Host "Total Steps - $TotalSteps"
Write-Host "Completed Successfully - $($($Status.SelectNodes("//Step") | Where-Object {$_.Status -eq 'Success'}).Count)" -ForegroundColor Green
Write-Host "Skipped Steps - $($($Status.SelectNodes("//Step") | Where-Object {$_.Status -eq 'Skipped'}).Count)" -ForegroundColor Yellow
Write-Host "Steps In Progress - $($($Status.SelectNodes("//Step") | Where-Object {$_.Status -eq 'InProgress'}).Count)" -ForegroundColor Green
Write-Host "Steps with Errors - $($($Status.SelectNodes("//Step") | Where-Object {$_.Status -eq 'Error'}).Count)" -ForegroundColor Red
Write-Host "Steps Remaining - $($($Status.SelectNodes("//Step") | Where-Object {$_.Status -eq $null}).Count)" -ForegroundColor Cyan