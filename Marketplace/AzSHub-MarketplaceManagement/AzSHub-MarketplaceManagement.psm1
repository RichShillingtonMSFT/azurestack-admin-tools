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
    Write-Host "Please wait while I find the most recent Marketplace Items. This may take a minute..." -ForegroundColor Green
    $Progress = 0

    $ItemVersions = @()

    foreach ($AvailableMarketPlaceItem in $AvailableMarketPlaceItems)
    {
        $Progress++

        $AvailableMarketPlaceItemVersion = $AvailableMarketPlaceItem.Split('-')[-1] | ForEach-Object { New-Object System.Version ($_) }
        $AvailableMarketPlaceItemName = ($AvailableMarketPlaceItem.Substring(0, $AvailableMarketPlaceItem.lastIndexOf('-'))) + '-'

        Write-Progress -Activity "Looking for the most recent version of $AvailableMarketPlaceItemName" -Status "Progress:" -PercentComplete ($Progress/$AvailableMarketPlaceItems.count*100)
        $ItemVersions += New-Object PSObject -Property ([ordered]@{AvailableMarketPlaceItemName=$AvailableMarketPlaceItemName;AvailableMarketPlaceItemVersion=$AvailableMarketPlaceItemVersion})
    }

    #region Find the latest versions
    $AvailableMarketPlaceItemsLatestVersions = @()

    $Progress = 0
    foreach ($ItemVersion in $ItemVersions)
    {
        $Progress++
        Write-Progress -Activity "Looking for the most recent version of $($ItemVersion.AvailableMarketPlaceItemName)" -Status "Progress:" -PercentComplete ($Progress/$ItemVersions.count*100)
        $AllVersions = $ItemVersions | Where-Object {$_.AvailableMarketPlaceItemName -eq $ItemVersion.AvailableMarketPlaceItemName}

        if ($AllVersions.Count -gt 1)
        {
            $AvailableMarketPlaceItemsLatestVersions += $AllVersions | Sort-Object -Property AvailableMarketPlaceItemVersion -Descending | Select-Object -First 1
        }
        else 
        {

            $AvailableMarketPlaceItemsLatestVersions += $ItemVersion
        }
    }

    #endregion

    #region Find downloaded versions and compare to available
    Write-Host "Finding your downloaded Marketplace Items. This may take a minute..." -ForegroundColor Green
    $DownloadedMarketPlaceItems = (Get-AzsAzureBridgeDownloadedProduct -WarningAction SilentlyContinue -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -Verbose).Name -replace "default/", ""
    Write-Host "You have $($DownloadedMarketPlaceItems.count) Marketplace items downloaded"

    $DownloadedMarketPlaceItemVersions = @()
    $DownloadedMarketPlaceItemLatestVersions = @()

    foreach ($DownloadedMarketPlaceItem in $DownloadedMarketPlaceItems)
    {

        $ItemVersion = $DownloadedMarketPlaceItem.Split('-')[-1] | ForEach-Object { New-Object System.Version ($_) }
        $ItemName = ($DownloadedMarketPlaceItem.Substring(0, $DownloadedMarketPlaceItem.lastIndexOf('-'))) + '-'
        $DownloadedMarketPlaceItemVersions += New-Object PSObject -Property ([ordered]@{ItemName=$ItemName;ItemVersion=$ItemVersion})
    }

    foreach ($DownloadedMarketPlaceItemVersion in $DownloadedMarketPlaceItemVersions)
    {
        $Objects = $DownloadedMarketPlaceItemVersions | Where-Object {$_.ItemName -match $DownloadedMarketPlaceItemVersion.ItemName}
        if ($Objects.Count -gt 1)
        {
            $DownloadedMarketPlaceItemLatestVersions += $Objects | Sort-Object -Property ItemVersion -Descending | Select-Object -First 1
        }
        else 
        {
            $DownloadedMarketPlaceItemLatestVersions += $DownloadedMarketPlaceItemVersion
        }

    }

    $AvailableUpdates = @()
    $AvailableUpdates += New-Object PSObject -Property ([ordered]@{AvailableMarketPlaceItemName='ALL';AvailableMarketPlaceItemVersion=''})

    foreach ($DownloadedMarketPlaceItemLatestVersion in $DownloadedMarketPlaceItemLatestVersions)
    {
        $AvailableVersion = $AvailableMarketPlaceItemsLatestVersions | Where-Object {$_.AvailableMarketPlaceItemName -eq $DownloadedMarketPlaceItemLatestVersion.ItemName}
        if ($AvailableVersion.AvailableMarketPlaceItemVersion -gt $DownloadedMarketPlaceItemLatestVersion.ItemVersion)
        {
            $AvailableUpdates += $AvailableVersion
        }
    }
    
    if ($AvailableUpdates.Count -gt 1)
    {
        $AvailableUpdates = $AvailableUpdates | Sort-Object -Property AvailableMarketPlaceItemName -Unique
        Write-Host "You have $($AvailableUpdates.Count -1) update(s) available" -ForegroundColor Yellow

        #region Update Items
        $ItemsToUpdate = $AvailableUpdates | Out-GridView -Title "Please Select which Marketplace items you want to update" -PassThru

        if ($ItemsToUpdate.AvailableMarketPlaceItemName -eq 'All')
        {
            foreach ($ItemToUpdate in $AvailableUpdates | Where-Object {$_.AvailableMarketPlaceItemName -ne 'All'})
            {
                Write-Host "Downloading $($ItemToUpdate.AvailableMarketPlaceItemName) version $($ItemToUpdate.AvailableMarketPlaceItemVersion)" -ForegroundColor Green
                Invoke-AzsAzureBridgeProductDownload -ActivationName $($BridgeActivation.Name) -Name $($ItemToUpdate.AvailableMarketPlaceItemName + $ItemToUpdate.AvailableMarketPlaceItemVersion.ToString()) -ResourceGroupName $ActivationResourceGroup -Force -AsJob -Confirm:$false -Verbose -WarningAction SilentlyContinue
            }
        }
        else 
        {
            foreach ($ItemToUpdate in $ItemsToUpdate)
            {
                Write-Host "Downloading $($ItemToUpdate.AvailableMarketPlaceItemName) version $($ItemToUpdate.AvailableMarketPlaceItemVersion)" -ForegroundColor Green
                Invoke-AzsAzureBridgeProductDownload -ActivationName $($BridgeActivation.Name) -Name $($ItemToUpdate.AvailableMarketPlaceItemName + $ItemToUpdate.AvailableMarketPlaceItemVersion.ToString()) -ResourceGroupName $ActivationResourceGroup -AsJob -Force -Confirm:$false -Verbose -WarningAction SilentlyContinue
            }
        }
        #endregion
    }
    if ($AvailableUpdates.Count -le 1)
    {
        Write-Host "You have no outdated Marketplace items. Nice work keeping it up to date!" -ForegroundColor Green
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
    $Duplicates = (Compare-object -ReferenceObject $RemovedDuplicates -DifferenceObject $DownloadedMarketPlaceItemsDetails.ItemName).InputObject
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
                Remove-AzsAzureBridgeDownloadedProduct -Name $ItemName -ActivationName $($BridgeActivation.Name) -ResourceGroupName $ActivationResourceGroup -AsJob -Verbose -Force
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