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
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue

#region Find downloaded versions and compare to available
Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
$DownloadedMarketPlaceItems = (Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose).Name -replace "default/", ""
Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items downloaded"

$DownloadedMarketPlaceItemsDetails = @()
foreach ($DownloadedMarketPlaceItem in $DownloadedMarketPlaceItems)
{
    $MarketPlaceItemVersion = $DownloadedMarketPlaceItem.Split('-')[-1]
    $MarketPlaceItemName = $DownloadedMarketPlaceItem.Substring(0, $DownloadedMarketPlaceItem.lastIndexOf('-'))
    $DownloadedMarketPlaceItemsDetails += New-Object PSObject -Property ([ordered]@{ItemName=$MarketPlaceItemName;ItemVersion=$MarketPlaceItemVersion})
}

$RemovedDuplicates = $DownloadedMarketPlaceItemsDetails.ItemName | Select-Object -Unique
$Duplicates = (Compare-object –referenceobject $RemovedDuplicates –differenceobject $DownloadedMarketPlaceItemsDetails.ItemName).InputObject
if ($Duplicates.Count -ge 1)
{
    Write-Host "You have $($Duplicates.Count) Marketplace Items to cleanup" -ForegroundColor Yellow
    $DuplicateVersionDetails = @()
    foreach ($Duplicate in $Duplicates)
    {
        foreach ($DownloadedMarketPlaceItemDetail in $DownloadedMarketPlaceItemsDetails)
        {
            if ($DownloadedMarketPlaceItemDetail.ItemName -eq $Duplicate)
            {
                $DuplicateVersionDetails += $DownloadedMarketPlaceItemDetail
            }
        }
    }

    $DuplicateMarketPlaceVersions = @()
    foreach ($DuplicateVersion in $DuplicateVersionDetails.ItemName | Get-Unique)
    {
        $VersionList = New-Object PSObject

        $CurrentItem = $DuplicateVersionDetails | Where-Object {$_.ItemName -eq $DuplicateVersion}
        $ItemVersions = $CurrentItem.ItemVersion | ForEach-Object { New-Object System.Version ($_) } | Sort-Object -Descending
        $Property = [ordered]@{ItemName=$($CurrentItem[0].ItemName)}
        $VersionList | Add-Member -NotePropertyMembers $Property 
        $IsFirst = $True
        Foreach ($ItemVersion in $ItemVersions)
        {
            $VersionID = 0
            if ($IsFirst -eq $True)
            {
                $Property = [ordered]@{LatestVersion=$($ItemVersion)}
                $VersionList | Add-Member -NotePropertyMembers $Property
                $IsFirst = $False
                $VersionID++
            }
            else
            {
                $PropertyName = ('OldVersion' + $VersionID)
                $VersionList | Add-Member -NotePropertyMembers @{$PropertyName=$($ItemVersion)}
                $VersionID++
            }

        }
        $DuplicateMarketPlaceVersions += $VersionList
    }

    $ItemsToCleanup = $DuplicateMarketPlaceVersions | Out-GridView -Title "Please Select which Marketplace items you want to Cleanup" -PassThru

    foreach ($ItemToCleanup in $ItemsToCleanup)
    {
        $Versions = $ItemToCleanup.PSObject.Properties | Where-Object {($_.Name -ne 'ItemName' -and $_.Name -ne 'LatestVersion')}
        foreach ($Version in $Versions)
        {
            $ItemName = $ItemToCleanup.ItemName + '-' + $Version.Value
            Write-host "Cleaning up $ItemName" -ForegroundColor Yellow
            Write-host "This may take a minute..." -ForegroundColor Yellow
            Remove-AzsAzureBridgeDownloadedProduct -Name $ItemName -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose -Force
            Write-host "$ItemName has been removed." -ForegroundColor Green
        }
    }
}
else 
{
    Write-Host "You have no Marketplace items to clean up" -ForegroundColor Green    
}