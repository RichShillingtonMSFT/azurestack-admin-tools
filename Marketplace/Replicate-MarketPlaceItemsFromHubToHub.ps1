[CmdletBinding()]
param
(
    # Specify the Marketplace items storage account name
    [Parameter(Mandatory=$false,HelpMessage="Specify the Marketplace items container URL. Example https://operatorfilesa.blob.region.contoso.mil/marketplaceitems")]
    [String]$MarketplaceItemsContainerURL = "https://operatorfilesa.blob.region.contoso.mil/marketplaceitems",

    [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
)
#Requires -Module AzS.Syndication.Admin
Import-Module AzS.Syndication.Admin

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$RegionNames = @('region1','region2','region3')
$AzureStackDNSDomain = 'contoso.com'

foreach ($RegionName in $RegionNames)
{
    $AdminEnvironmentName = $RegionName + '-AzS-Admin'
    $AzureStackDomainFQDN = $RegionName + '.' + $AzureStackDNSDomain
    Add-AzEnvironment -Name $AdminEnvironmentName -ARMEndpoint ('https://adminmanagement.' + $AzureStackDomainFQDN) `
        -AzureKeyVaultDnsSuffix ('adminvault.' + $AzureStackDomainFQDN) `
        -AzureKeyVaultServiceEndpointResourceId ('https://adminvault.' + $AzureStackDomainFQDN)

    $UserEnvironmentName = $RegionName + '-AzS-User'
    Add-AzEnvironment -Name $UserEnvironmentName -ARMEndpoint ('https://management.' + $AzureStackDomainFQDN)
}

function AzSHub-Login
{
    $AzureContextDetails = Get-AzContext -ErrorAction SilentlyContinue
    if ($AzureContextDetails)
    {
        Write-Host "You are currently connected to Azure as $($AzureContextDetails.Account)" -ForegroundColor Green 
        Write-Host "Your current working Subsciption is $($AzureContextDetails.Subscription.Name) - $($AzureContextDetails.Subscription.Id)" -ForegroundColor Green 
        Write-Host "You are currently connected to Tenant ID is $($AzureContextDetails.Subscription.TenantId)" -ForegroundColor Green 

        # Azure connection choice
        $Continue = New-Object System.Management.Automation.Host.ChoiceDescription '&Continue'
        $Login = New-Object System.Management.Automation.Host.ChoiceDescription '&Login'
        $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Continue, $Login)
        $Title = 'Continue or Login?'
        $Message = 'Do you want to continue or login again and select a new environment?'
        $AzureConnectionChoice = $host.ui.PromptForChoice($title, $message, $options, 0)
    }
    if (($AzureConnectionChoice -eq 1) -or (!($AzureContextDetails)))
    {
        #region Enviornment Selection
        $Environments = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://adminmanagement.*"}
        $Environment = $Environments | Out-GridView -Title "Please Select Your Source Admin Enviornment." -PassThru
        #endregion

        #region Connect to Azure
        try
        {
            Add-AzAccount -EnvironmentName $($Environment.Name) -ErrorAction 'Stop'
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
    }
}

AzSHub-Login

$SourceStorageAccountName = $MarketplaceItemsContainerURL.Replace('https://','').Split('.')[0]
$SourceStorageAccountContainerName = $MarketplaceItemsContainerURL.Replace('https://','').Split('/')[1]

Write-Host "Looking for Storage Account $SourceStorageAccountName" -ForegroundColor Green
$SourceStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $SourceStorageAccountName}

Write-Host "Creating a SAS Token for the Storage Account Container" -ForegroundColor Green
$StartTime = Get-Date
$EndTime = $startTime.AddHours(24.0)
$SourceSASToken = New-AzStorageContainerSASToken -Context $SourceStorageAccount.Context -Container $SourceStorageAccountContainerName -Permission rwdl -StartTime $StartTime -ExpiryTime $EndTime -ErrorAction Stop
$SourceSourceUrl = $MarketplaceItemsContainerURL + $SourceSASToken

Write-Host "Getting folders in the Storage Account Container" -ForegroundColor Green
$SourceStorageAccountContainerFileList = Get-AzStorageBlob -Container $SourceStorageAccountContainerName -Context $SourceStorageAccount.Context
$SourceStorageAccountContainerFolderList = @()
foreach ($SourceStorageAccountContainerFile in $SourceStorageAccountContainerFileList)
{
    $SourceStorageAccountContainerFolderList += $SourceStorageAccountContainerFile.Name.Split('/')[0]
}
$SourceStorageAccountContainerFolderList = $SourceStorageAccountContainerFolderList | Select-Object -Unique
    
Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue
    
#region Find downloaded versions and compare to available
Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
$DownloadedMarketPlaceItems = Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose
Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items downloaded on the source Azure Stack Hub" -ForegroundColor Green
    
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
$CSVFileName = 'MarketPlaceItems.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation -Force

Write-host "Looking for the drive with the most free space." -ForegroundColor Green
$DriveLetter = (Get-Volume | Sort-Object -Property SizeRemaining | Select-Object -Last 1).DriveLetter
Write-host "Selected Drive $DriveLetter" -ForegroundColor Green
$MPTempLocation = New-Item -Path ($DriveLetter + ':\MPTemp') -ItemType Directory -Force

$CSVFileLocation = "$Env:USERPROFILE\Documents\MarketPlaceItems.csv"

AzSHub-Login

$MarketPlaceItemsList = Import-Csv $CSVFileLocation -ErrorAction Stop

Write-host "Looking for Azure Bridge Activation"
$ActivationResourceGroup = "azurestack-activation"
$BridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $ActivationResourceGroup -WarningAction SilentlyContinue

Write-Host "Checking for downloaded Marketplace Items" -ForegroundColor White
$DownloadedProducts = Get-AzsAzureBridgeDownloadedProduct -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup
Write-Host "You have $($DownloadedProducts.Count) downloaded Marketplace Items on the destination Azure Stack Hub" -ForegroundColor Green

[Int]$TotalItems = $MarketPlaceItemsList.Count
[Int]$ItemsToImportCount = '1'

$MissingBlobFolders = @()

foreach ($MarketPlaceItem in $MarketPlaceItemsList)
{
    Write-Host "Checking to see if item $($ItemsToImportCount) of $($TotalItems) $($MarketPlaceItem.Name.Split('/')[1]) has been imported." -ForegroundColor Green

    if (!($DownloadedProducts | Where-Object {$_.Name -eq $MarketPlaceItem.Name}))
    {
        Write-Host "Marketplace item $($MarketPlaceItem.Name.Split('/')[1]) was not found. Starting download..." -ForegroundColor Yellow

        $Blob = $SourceStorageAccountContainerFolderList | Where-Object {$_ -eq $($MarketPlaceItem.Name.Split('/')[1])}
        if ((!$Blob))
        {
            Write-Host "Marketplace Item $($MarketPlaceItem.Name.Split('/')[1]) Blob not found." -ForegroundColor Red
            $MissingBlobFolders += $($MarketPlaceItem.Name.Split('/')[1])
        }
        else
        {
            $BlobSourceURL = $MarketplaceItemsContainerURL + '/' + $Blob + $SourceSASToken
            $ENV:AZCOPY_DEFAULT_SERVICE_API_VERSION="2017-11-09"
            azcopy copy $BlobSourceURL $($MPTempLocation.FullName) --recursive=true
            Write-Host "Marketplace item $($MarketPlaceItem.Name.Split('/')[1]) download completed." -ForegroundColor Green
            Write-Host "Importing Marketplace item $($MarketPlaceItem.Name.Split('/')[1])" -ForegroundColor White
            try
            {
                Import-AzsMarketplaceItem -RepositoryDir $MPTempLocation.FullName -ErrorAction Stop
            }
            catch
            {
                if ($_.FullyQualifiedErrorId -like "Failed to import product*")
                {
                    Import-AzsMarketplaceItem -RepositoryDir $MPTempLocation.FullName -ErrorAction Stop
                }
                else
                {
                    Break
                }
            }
            Write-Host "Importing Marketplace item $($MarketPlaceItem.Name.Split('/')[1]) is complete." -ForegroundColor Green

            Write-Host "Cleaning up $($MarketPlaceItem.Name.Split('/')[1]) temporary files." -ForegroundColor White
            Remove-Item ($($MPTempLocation.FullName) + '\' + $($MarketPlaceItem.Name.Split('/')[1])) -Force -Recurse
        }
        $ItemsToImportCount ++
    }
    else
    {
        Write-Host "$($MarketPlaceItem.Name.Split('/')[1]) is already downloaded" -ForegroundColor Green
        $ItemsToImportCount ++
    }
}

if ($MissingBlobFolders.Count -ge '1')
{
    Write-Host "The following blob folders were not found in the Storage Account"
    $MissingBlobFolders
}