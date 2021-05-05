function Export-MarketPlaceItemsToCSV
{
    [CmdletBinding()]
    param
    (
        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )
    
    AzSHub-Login
    
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
}
Export-ModuleMember -Function Export-MarketPlaceItemsToCSV

function Restore-MarketPlaceItemsFromCSV
{
    [CmdletBinding()]
    param
    (
        # Specify the path to the Marketplace Items CSV File
        [Parameter(Mandatory=$true,HelpMessage="Specify the path to the Marketplace Items CSV File. Example C:\Temp\MarketPlaceItems.csv")]
        [String]$CSVFileLocation
    )

    $ErrorActionPreference = 'Stop'

    AzSHub-Login

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
}
Export-ModuleMember -Function Restore-MarketPlaceItemsFromCSV

function Invoke-MarketPlaceItemsUpdate
{
    [CmdletBinding()]
    param
    (

    )
    
    AzSHub-Login

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
}
Export-ModuleMember -Function Invoke-MarketPlaceItemsUpdate

function Invoke-MarketPlaceItemsCleanup
{
    [CmdletBinding()]
    param
    (

    )
    
    AzSHub-Login

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
}
Export-ModuleMember -Function Invoke-MarketPlaceItemsCleanup

function AzSHub-Login
{
    $AzureContextDetails = Get-AzureRmContext -ErrorAction SilentlyContinue
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
    }
}