[CmdletBinding()]
param
(
	# Specify the output location for the CSV File
	[Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	[String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
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

Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue

#region Find downloaded versions and compare to available
Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
$DownloadedMarketPlaceItems = Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose
Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items downloaded"

# Create Data Table Structure
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("DisplayName","string") | Out-Null
$DataTable.Columns.Add("PublisherDisplayName","string") | Out-Null
$DataTable.Columns.Add("PublisherIdentifier","string") | Out-Null
$DataTable.Columns.Add("Offer","string") | Out-Null
$DataTable.Columns.Add("OfferVersion","string") | Out-Null
$DataTable.Columns.Add("Sku","string") | Out-Null
$DataTable.Columns.Add("GalleryItemIdentity","string") | Out-Null
$DataTable.Columns.Add("Name","string") | Out-Null

foreach ($DownloadedMarketPlaceItem in $DownloadedMarketPlaceItems)
{
    $NewRow = $DataTable.NewRow()
    $NewRow.DisplayName = $($DownloadedMarketPlaceItem.DisplayName)
    $NewRow.PublisherDisplayName = $($DownloadedMarketPlaceItem.PublisherDisplayName)
    $NewRow.PublisherIdentifier = $($DownloadedMarketPlaceItem.PublisherIdentifier)
    $NewRow.Offer = $($DownloadedMarketPlaceItem.Offer)
    $NewRow.OfferVersion = $($DownloadedMarketPlaceItem.OfferVersion)
    $NewRow.Sku = $($DownloadedMarketPlaceItem.Sku)
    $NewRow.GalleryItemIdentity = $($DownloadedMarketPlaceItem.GalleryItemIdentity)
    $NewRow.Name = $($DownloadedMarketPlaceItem.Name)
    $DataTable.Rows.Add($NewRow)
}

# Export Data Table to CSV
$AzureStackName = $BridgeActivation.AzureRegistrationResourceIdentifier.Split('/') | Select-Object -Last 1
$CSVFileName = 'MarketPlaceItems-' + $AzureStackName + '-' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
