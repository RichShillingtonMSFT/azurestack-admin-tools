$DownloadsFolder = "D:\MarketPlaceDownloads"

#region Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru
#endregion

#region Connect to Azure
try
{
    $AzureRMAccount = Connect-AzureRmAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
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
        $TenantID = $Subscription.TenantId
    }
    else
    {
        $SubscriptionID = $Subscriptions.SubscriptionID
        $TenantID = $Subscriptions.TenantId
    }
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

Import-Module "$AzureStackToolsMasterLocation\Syndication\AzureStack.MarketplaceSyndication.psm1"

$Credential = Get-Credential -Message "Enter the azure stack operator credential:"
Import-AzSOfflineMarketplaceItem -origin $DownloadsFolder -AzsCredential $Credential