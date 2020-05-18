<#
.SYNOPSIS
    Script to configure Azure Stacks AAD Home Directory.

.DESCRIPTION
    Use this to configure Azure Stacks AAD Home Directory.
    Run this script again at any time to check the status of the Azure Stack applications in your directory.
    If your Azure Stack Administrator installs new services or updates in the future, you may need to run this script again.

.EXAMPLE
    .\Invoke-UpdateAzureADTenantPermissions.ps1
#>
[CmdletBinding()]
Param
()

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

Import-Module $AzureStackToolsMasterLocation\Connect\AzureStack.Connect.psm1 -Force -Verbose
Import-Module $AzureStackToolsMasterLocation\Identity\AzureStack.Identity.psm1 -Force -Verbose
#endregion

Update-AzsHomeDirectoryTenant -AdminResourceManagerEndpoint $($AzContext.Environment.ResourceManagerUrl) `
   -DirectoryTenantName $($AzContext.Environment.ActiveDirectoryServiceEndpointResourceId).Split('/')[2].Replace('adminmanagement.','') -Verbose