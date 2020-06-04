$DownloadsFolder = "D:\MarketPlaceDownloads"

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

[String]$AzureStackToolsMasterLocation = $InstalledLocations[0]


Import-Module "$AzureStackToolsMasterLocation\Syndication\AzureStack.MarketplaceSyndication.psm1"

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
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

Export-AzSOfflineMarketplaceItem -destination $DownloadsFolder -azCopyDownloadThreads "25"
