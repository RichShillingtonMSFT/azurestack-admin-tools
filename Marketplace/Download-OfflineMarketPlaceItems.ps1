$DownloadsFolder = "C:\MPItems"

$InstalledLocations = @()
$ModulePaths = $env:PSModulePath.Split(';')

foreach ($ModulePath in $ModulePaths)
{
    $ModulePath.TrimEnd('\')
    $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az")
    if ($TestResults)
    {
        $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az")
    }
}

[String]$AzureStackToolsMasterLocation = $InstalledLocations[0]


Import-Module "$AzureStackToolsMasterLocation\Syndication\AzureStack.MarketplaceSyndication.psm1"

#region Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru
#endregion

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
        Select-AzSubscription $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

$products = Select-AzsMarketplaceItem

$products | Export-AzsMarketplaceItem  -RepositoryDir $DownloadsFolder
