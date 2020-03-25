<#
.SYNOPSIS
    Script to register Azure Stack

.DESCRIPTION
    Use this script to register Azure Stack

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'CloudAdmin@azurestack.local'

.PARAMETER PrivilegedEndpoints
    Define list of Privileged Endpoints as an Array.
    Example: @("AZS-ERCS01","AZS-ERCS02","AZS-ERCS03")

.PARAMETER RegistrationName
    Registration Name for the Azure Stack. 
    Example: Stamp1

.PARAMETER BillingModel
    Billing Model for the Azure Stack. 
    Example: 'Capacity','Custom','Development','PayAsYouUse'

.EXAMPLE
    .\Register-AzureStack.ps1 -RegistrationName 'Stamp1' -BillingModel 'Capacity'
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'CloudAdmin@azurestack.local',

    # Define list of Privileged Endpoints as an Array.
    # Example: @("AZS-ERCS01","AZS-ERCS02","AZS-ERCS03")
    [parameter(Mandatory=$false,HelpMessage='Define list of Privileged Endpoints as an Array. Example: @("AZS-ERCS01","AZS-ERCS02","AZS-ERCS03")')]
    [Array]$PrivilegedEndpoints = @("AZS-ERCS01","AZS-ERCS02","AZS-ERCS03"),

    # Registration Name for the Azure Stack. 
    # Example: Stamp1'
    [parameter(Mandatory=$true,HelpMessage='Registration Name for the Azure Stack. Example: Stamp1')]
    [String]$RegistrationName,

    # Billing Model for the Azure Stack. 
    # Example: 'Capacity','Custom','Development','PayAsYouUse'
    [parameter(Mandatory=$true,HelpMessage='Billing Model for the Azure Stack. Example: Capacity')]
    [ValidateSet('Capacity','Custom','Development','PayAsYouUse')]
    [String]$BillingModel
)

$CloudAdminCredential = Get-Credential -Credential $CloudAdminUserName

#region Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru
#endregion

#region Connect to Azure
try
{
    #$AzureRMAccount = Connect-AzureRmAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
    $AzureRMAccount = Add-AzureRmAccount -EnvironmentName $($Environment.Name) -ErrorAction 'Stop'
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
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
        Select-AzureRmSubscription $Subscription
        $SubscriptionID = $Subscription.SubscriptionID
    }
    else
    {
        $SubscriptionID = $Subscriptions.SubscriptionID
        Select-AzureRmSubscription $Subscriptions
    }

    $AzContext = Get-AzureRmContext
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

$InstalledLocations = @()
$ModulePaths = $env:PSModulePath.Split(';')

foreach ($ModulePath in $ModulePaths)
{
    $ModulePath.TrimEnd('\')
    $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master")
    if ($TestResults)
    {
        $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master")
    }
}

if ($InstalledLocations.Count -gt '1')
{
    [String]$AzureStackToolsMasterLocation = $InstalledLocations[0]
}
else
{
    [String]$AzureStackToolsMasterLocation = $InstalledLocations
}

Import-Module $AzureStackToolsMasterLocation\Registration\RegisterWithAzure.psm1 -Force -Verbose

Set-AzsRegistration -PrivilegedEndpointCredential $CloudAdminCredential -PrivilegedEndpoint (Get-Random -InputObject $PrivilegedEndpoints) `
-RegistrationName $RegistrationName -BillingModel $BillingModel `
-UsageReportingEnabled -MarketplaceSyndicationEnabled -AzureContext $AzContext -Verbose