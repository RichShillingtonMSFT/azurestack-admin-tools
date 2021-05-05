[CmdletBinding()]
param
(
	# Specify the path to the Marketplace Items CSV File
	[Parameter(Mandatory=$true,HelpMessage="Specify the output location for the CSV File. Example C:\Temp\MarketPlaceItems.csv")]
	[String]$CSVFileLocation
)

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
$ErrorActionPreference = 'Stop'
$MarketPlaceItemsList = Import-Csv $CSVFileLocation -ErrorAction Stop

Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue

Write-Host "Checking for downloaded Marketplace Items" -ForegroundColor White
$DownloadedProducts = Get-AzsAzureBridgeDownloadedProduct -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup
Write-Host "You have $($DownloadedProducts.Count) downloaded Marketplace Items" -ForegroundColor Green

foreach ($MarketPlaceItem in $MarketPlaceItemsList)
{
    Write-Host "Checking to see if you already have $($MarketPlaceItem.GalleryItemIdentity)" -ForegroundColor White

    if (!($DownloadedProducts | Where-Object {$_.Name -eq $MarketPlaceItem.Name}))
    {
        Write-Host "Marketplace item $($MarketPlaceItem.GalleryItemIdentity) was not found. Starting download..." -ForegroundColor Yellow
        Invoke-AzsAzureBridgeProductDownload -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Name ($($MarketPlaceItem.Name).Replace('default/', '')) -Force -Confirm:$false -AsJob
        Write-Host "Marketplace item $($MarketPlaceItem.GalleryItemIdentity) download started." -ForegroundColor Green
    }
    else
    {
        Write-Host "$($MarketPlaceItem.GalleryItemIdentity) is already downloaded" -ForegroundColor Green
    }
}

Write-Host "Marketplace items restore complete" -ForegroundColor Green