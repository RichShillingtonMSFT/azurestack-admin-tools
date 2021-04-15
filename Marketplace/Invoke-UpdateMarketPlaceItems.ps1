#region Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select Your Azure Stack Admin Enviornment." -PassThru
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
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select Your Default Provider Subscription." -PassThru
        Select-AzureRmSubscription $Subscription
    }
    else
    {
        Select-AzureRmSubscription $Subscriptions
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup 

#region Get all available Marketplace items
Write-Host "Finding all available Marketplace items" -ForegroundColor Green
$RegEx = '\-[0-9]'

$AvailableMarketPlaceItems = (Get-AzsAzureBridgeProduct -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -ErrorAction SilentlyContinue -Verbose -WarningAction SilentlyContinue | Where-Object {$_.Name -match $RegEx}).Name -replace "default/", ""

#region Find the latest versions
$AvailableMarketPlaceItemsLatestVersions = @()
$AvailableMarketPlaceItemsLatestVersions += 'All'

Write-Host "Please wait while I find the most recent Marketplace Items. This may take a minute..." -ForegroundColor Green
$Progress = 0
foreach ($AvailableMarketPlaceItem in $AvailableMarketPlaceItems)
{
    $Progress++
    $AvailableMarketPlaceItemName = $($AvailableMarketPlaceItem.Substring(0, $AvailableMarketPlaceItem.lastIndexOf('-')))
    Write-Progress -Activity "Looking for the most recent version of $AvailableMarketPlaceItemName" -Status "Progress:" -PercentComplete ($Progress/$AvailableMarketPlaceItems.count*100)
    $AllVersions = $AvailableMarketPlaceItems | Where-Object {$_ -like "$AvailableMarketPlaceItemName*"}
    if ($AllVersions.Count -gt 1)
    { 
        Write-Host "Found $($AllVersions.Count) versions"
        $AvailableMarketPlaceItemsLatestVersions += $(($AllVersions | Sort-Object -Descending)[0]).ToString()
    }
    else 
    {
        $AvailableMarketPlaceItemsLatestVersions += $AvailableMarketPlaceItem
    }
}

$AvailableMarketPlaceItemsLatestVersions = $AvailableMarketPlaceItemsLatestVersions | Select-Object -Unique
#endregion

#region Find downloaded versions and compare to available
Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
$DownloadedMarketPlaceItems = (Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose).Name -replace "default/", ""
Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items downloaded"

$MarketPlaceItemsWithUpdates = @()
$MarketPlaceItemsWithUpdates += New-Object PSObject -Property ([ordered]@{UpdateName='ALL';UpdateVersion=''})
$Progress = 0
foreach ($DownloadedMarketPlaceItem in $DownloadedMarketPlaceItems)
{
    $Progress++
    $CurrentMarketPlaceItemVersion = $DownloadedMarketPlaceItem.Split('-')[-1]
    $CurrentMarketPlaceItemName = $DownloadedMarketPlaceItem.Substring(0, $DownloadedMarketPlaceItem.lastIndexOf('-'))
    Write-Progress -Activity "Checking to see if $CurrentMarketPlaceItemName needs an update" -Status "Progress:" -PercentComplete ($Progress/$DownloadedMarketPlaceItems.count*100)

    $AvailableUpdate = $AvailableMarketPlaceItemsLatestVersions | Where-Object {$_ -like "$CurrentMarketPlaceItemName*"}
    $AvailableUpdateVersion = $AvailableUpdate.Split('-')[-1]
    $AvailableUpdateName = $AvailableUpdate.Substring(0, $AvailableUpdate.lastIndexOf('-'))

    if ($CurrentMarketPlaceItemVersion -lt $AvailableUpdateVersion)
    {
        Write-Host "There is an update for $CurrentMarketPlaceItemName" -ForegroundColor Green
        Write-Host "You have version $CurrentMarketPlaceItemVersion" -ForegroundColor Green
        Write-Host "The available version for $AvailableUpdateName is $AvailableUpdateVersion" -ForegroundColor Green
        $MarketPlaceItemsWithUpdates += New-Object PSObject -Property ([ordered]@{UpdateName=$AvailableUpdateName;UpdateVersion=$AvailableUpdateVersion})
    }
    else 
    {
        Write-Host "No update available for $CurrentMarketPlaceItemName version $CurrentMarketPlaceItemVersion"    
    }
    
}
#endregion    

#region Update Items
$ItemsToUpdate = $MarketPlaceItemsWithUpdates | Out-GridView -Title "Please Select which Marketplace items you want to update" -PassThru

$Progress = 0
if ($ItemsToUpdate.UpdateName -eq 'All')
{
    Write-Host "You have selected $($MarketPlaceItemsWithUpdates.Count -1) updates to download"
    foreach ($MarketPlaceItemToUpdate in $MarketPlaceItemsWithUpdates | Where-Object {$_.UpdateName -ne 'All'})
    {
        $Progress++
        Write-Host "Downloading $($MarketPlaceItemToUpdate.UpdateName) version $($MarketPlaceItemToUpdate.UpdateVersion)"
        Write-Progress -Activity "Downloading $($MarketPlaceItemToUpdate.UpdateName) version $($MarketPlaceItemToUpdate.UpdateVersion)" -Status "Progress:" -PercentComplete ($Progress/$($MarketPlaceItemsWithUpdates.Count -1)*100)
        Invoke-AzsAzureBridgeProductDownload -ActivationName $($BridgeActivation.Name) -Name $($MarketPlaceItemToUpdate.UpdateName + '-' + $MarketPlaceItemToUpdate.UpdateVersion) -ResourceGroupName $ActivationResourceGroup -Force -Confirm:$false -Verbose -WarningAction SilentlyContinue
    }
}
else 
{
    foreach ($ItemToUpdate in $ItemsToUpdate)
    {
        $Progress++
        Write-Host "Downloading $($ItemToUpdate.UpdateName) version $($ItemToUpdate.UpdateVersion)"
        Write-Progress -Activity "Downloading $($ItemToUpdate.UpdateName) version $($ItemToUpdate.UpdateVersion)" -Status "Progress:" -PercentComplete ($Progress/$($ItemToUpdate.Count -1)*100)
        Invoke-AzsAzureBridgeProductDownload -ActivationName $($BridgeActivation.Name) -Name $($ItemToUpdate.UpdateName + '-' + $ItemToUpdate.UpdateVersion) -ResourceGroupName $ActivationResourceGroup -Force -Confirm:$false -Verbose -WarningAction SilentlyContinue
    }
}
#endregion