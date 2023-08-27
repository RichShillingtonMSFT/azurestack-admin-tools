<#
.SYNOPSIS
    Script to upload Marketplace items that are not currently in the Azure Stack Hub Marketplace.

.DESCRIPTION
    This can be used to upload Marketplace items that are not currently in the Azure Stack Hub Marketplace.
    The script will connect to the Default Provider Subscription and pull a list of imported Marketplace items.
    It will then check the productdetails.json of each Marketplace item in the folder provided and determine if it has been uploaded already.
    If the item is not currently in the Marketplace, it will be uploaded.

.PARAMETER StackHubRegionName
    Provide the folder path containing the Marketplace items
    Example: 'A:\MPItems'

.EXAMPLE
    .\Upload-MissingMarketplaceItems.ps1 -MarketPlaceItemsFolder 'A:\MPItems'
#>
[CmdletBinding()]
Param
(
    # Provide the folder path containing the Marketplace items.
    # Example: A:\MPItems
    [parameter(Mandatory=$true,HelpMessage='Provide the folder path containing the Marketplace items. Example: A:\MPItems')]
    [String]$MarketPlaceItemsFolder
)
#Requires -Module AzS.Syndication.Admin
Import-Module AzS.Syndication.Admin

# Enviornment Selection
$Environments = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://adminmanagement.*"}
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

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
    $Subscription = Get-AzSubscription -SubscriptionName 'Default Provider Subscription'
    Set-AzContext $Subscription
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue
    
#region Find downloaded versions and compare to available
Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
$DownloadedMarketPlaceItems = Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose
Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items imported"

$MPItemsOnStamp = @()
foreach ($DownloadedMarketPlaceItem in $DownloadedMarketPlaceItems)
{
    $MPItemsOnStamp += ($DownloadedMarketPlaceItem.Id).Split('/') | Select-Object -Last 1
}

$ItemsToBeImported = @()

$MPItemsInFolderJSONFiles = Get-ChildItem -Path $MarketPlaceItemsFolder -Include *.json -Recurse
foreach ($MPItemInFolderJSONFile in $MPItemsInFolderJSONFiles)
{
    $ItemDetails = Get-Content $MPItemInFolderJSONFile.FullName | ConvertFrom-Json
    $ItemName = ($ItemDetails.ResourceId).Split('/') | Select-Object -Last 1
    if ($MPItemsOnStamp -notcontains $ItemName)
    {
        $ItemsToBeImported += $ItemName
    }
}

$Items = Get-ChildItem $MarketPlaceItemsFolder | Where-Object {$_.Name -in $ItemsToBeImported}
Write-Host "There are $($Items.Count) Marketplace items to be imported" -ForegroundColor Yellow

[Int]$ImportCount = 1
foreach ($Item in $Items)
{
    Write-Host "Importing item $ImportCount of $($Items.Count)" -ForegroundColor Green
    Import-AzsMarketplaceItem -RepositoryDir $MarketPlaceItemsFolder -ProductName $Item.Name -ErrorAction Continue
    $ImportCount ++
}