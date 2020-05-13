<#
.SYNOPSIS
    Script to register Azure Stack

.DESCRIPTION
    Use this to register Azure Stack SDK for development use

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'CloudAdmin@azurestack.local'

.PARAMETER PrivilegedEndpoint
    Define Privileged Endpoint.
    Example: 'AZS-ERCS01'

.EXAMPLE
    .\Register-AzureStackSDK.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'CloudAdmin@azurestack.local',

    # Define Privileged Endpoint
    # Example: 'AZS-ERCS01'
    [parameter(Mandatory=$false,HelpMessage='Define Privileged Endpoint. Example: AZS-ERCS01')]
    [String]$PrivilegedEndpoint = 'AZS-ERCS01'
)

$CloudAdminCredential = Get-Credential -Credential $CloudAdminUserName

#region Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru
#endregion

#region Connect to Azure
try
{
    Add-AzureRmAccount -EnvironmentName $($Environment.Name) -ErrorAction 'Stop'
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
    }
    else
    {
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

#region Location Selection
$Locations = Get-AzureRmLocation
$Location = ($Locations | Out-GridView -Title "Please Select a location." -PassThru).Location
#endregion

#region Find Modules & import them
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
#endregion

Set-AzsRegistration -PrivilegedEndpointCredential $CloudAdminCredential -PrivilegedEndpoint $PrivilegedEndpoint `
    -RegistrationName $env:COMPUTERNAME -BillingModel Development -ResourceGroupLocation $Location `
    -UsageReportingEnabled -MarketplaceSyndicationEnabled -AzureContext $AzContext -Verbose