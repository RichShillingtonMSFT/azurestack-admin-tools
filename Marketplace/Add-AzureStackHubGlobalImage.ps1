<#
.SYNOPSIS
    Script to upload & create platform images on multiple Azure Stack Hubs

.DESCRIPTION
    This script will create a temporary Storage Account in the Admin Environment.
    It will then upload the vhd file from the path specified.
    It will then loop through each Hub Region specified and add the platform image.
    Finally it will remove the temporary Resource Group & Storage Account.

.PARAMETER HubRegions
    Specify the region of the Hub. 
    Example: 'HQ1','HQ2','HQ3'

.PARAMETER AzureStackDNSDomain
    Specify the DNS Domain of the Stack Hubs.
    Example: 'contoso.com'

.PARAMETER ImagePublisher
    Provide a Name for the Image Publisher. 
    Example: 'Contoso'

.PARAMETER ImageOffer
    Provide a Name for the Image Offer. 
    Example: 'WindowsServer'

.PARAMETER ImageSku
    Provide a Name for Image Sku. 
    Example: '2019-SessionHost'

.PARAMETER ImageVersion
    Provide a version number for the Image. 
    Example: '17763.4010.3004'

.PARAMETER ImagePath
    Provide the full path to the Image VHD. 
    Example: 'C:\Temp\Image.vhd'

.EXAMPLE
    .\Add-AzureStackHubGlobalImage.ps1 -HubRegions 'HQ1','HQ2','HQ3' `
        -AzureStackDNSDomain 'Contoso.com' `
        -ImagePublisher 'Contoso' `
        -ImageOffer 'WindowsServer' `
        -ImageSku '2019-SessionHost' `
        -ImageVersion '17763.4010.3004' `
        -ImagePath 'C:\Temp\Image.vhd'
#>
[CmdletBinding()]
param
(
	# Specify the region of the Hub
	[Parameter(Mandatory=$true,HelpMessage="Specify the regions of the Hub. Example: 'HQ1','HQ2','HQ3'")]
	[String[]]$HubRegions,

	# Specify the DNS Domain of the Stack Hubs
	[Parameter(Mandatory=$true,HelpMessage="Specify the DNS Domain of the Stack Hubs. Example: 'contoso.com'")]
	[String]$AzureStackDNSDomain,

    # Provide a Name for the Image Publisher
	[Parameter(Mandatory=$true,HelpMessage="Provide a Name for the Image Publisher. Example: Contoso")]
	[String]$ImagePublisher,

    # Provide a Name for the Image Offer
	[Parameter(Mandatory=$true,HelpMessage="Provide a Name for the Image Offer. Example: WindowsServer")]
	[String]$ImageOffer,

    # Provide a Name for Image Sku
	[Parameter(Mandatory=$true,HelpMessage="Provide a Name for Image Sku. Example: 2019-SessionHost")]
	[String]$ImageSku,

    # Provide a version number for the Image
	[Parameter(Mandatory=$true,HelpMessage="Provide a version number for the Image. Example: 17763.4131.230430")]
	[String]$ImageVersion,

    # Provide the Image OS Type
	[Parameter(Mandatory=$true,HelpMessage="Provide the Image OS Type. Example: Windows or Linux")]
    [ValidateSet('Windows','Linux')]
	[String]$ImageOSType,

    # Provide the full path to the Image VHD 
	[Parameter(Mandatory=$true,HelpMessage="Provide the full path to the Image VHD. Example: C:\Temp\Image.vhd")]
	[String]$ImagePath
)

# Get VHD File Name from Image Path
$VHDFileName = $ImagePath.Split('\') | Select-Object -Last 1

#region Add Stack Hub Endpoints
foreach ($HubRegion in $HubRegions)
{
    $AdminEnvironmentName = $HubRegion + '-AzS-Admin'
    $AzureStackDomainFQDN = $HubRegion + '.' + $AzureStackDNSDomain
    Add-AzEnvironment -Name $AdminEnvironmentName -ARMEndpoint ('https://adminmanagement.' + $AzureStackDomainFQDN) `
        -AzureKeyVaultDnsSuffix ('adminvault.' + $AzureStackDomainFQDN) `
        -AzureKeyVaultServiceEndpointResourceId ('https://adminvault.' + $AzureStackDomainFQDN)

    $UserEnvironmentName = $HubRegion + '-AzS-User'
    Add-AzEnvironment -Name $UserEnvironmentName -ARMEndpoint ('https://management.' + $AzureStackDomainFQDN)
}
#endregion

# Enviornment Selection
$Environments = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://adminmanagement*"}
$Environment = $Environments | Out-GridView -Title "Please Select Azure Stack Admin Environment." -PassThru

#region Connect to Azure
try
{
    Connect-AzAccount -Environment $($Environment.Name) -DeviceCode -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

try 
{
    $Subscription = Get-AzSubscription -SubscriptionName 'Default Provider Subscription'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$Location = Get-AzLocation
#endregion

#region Test for AzCopy
$AzCopyTest = Invoke-Command -ScriptBlock {AzCopy --help}
if (!($AzCopyTest))
{
    Write-Host "AzCopy.exe was not found." -ForegroundColor Red
    Write-Host "Please provide the path to AzCopy.exe" -ForegroundColor Yellow
}
#endregion

#region Create Temp Storage Account & Container
Write-Host "Creating temporary Resource Group" -ForegroundColor Green
$TemporaryResourceGroup = New-AzResourceGroup -Name Image-Transfer-Tmp-Rg -Location $Location.Location

Write-Host "Creating temporary Storage Account" -ForegroundColor Green
$TemporaryStorageAccount = New-AzStorageAccount -ResourceGroupName $TemporaryResourceGroup.ResourceGroupName `
    -Name ((((New-Guid).Guid).ToLower().Replace('-','') -replace "[0-9]") + (((New-Guid).Guid).ToLower().Replace('-','') -replace "[0-9]") | Select-Object -First 23) `
    -Location $Location.Location `
    -SkuName Standard_LRS

Write-Host "Creating temporary Storage Account Container" -ForegroundColor Green
$TemporaryStorageAccountContainer = New-AzStorageContainer -Name images -Context $TemporaryStorageAccount.Context -Permission Off
#endregion

#region Create Container SAS Token
Write-Host "Creating a SAS Token for the Storage Account Container" -ForegroundColor Green
$StartTime = Get-Date
$EndTime = $startTime.AddHours(24.0)
$SASToken = New-AzStorageContainerSASToken -Context $TemporaryStorageAccount.Context -Container images -Permission rwdl -StartTime $StartTime -ExpiryTime $EndTime -ErrorAction Stop
$DestinationUrl = $($TemporaryStorageAccountContainer.Context.BlobEndPoint) + $($TemporaryStorageAccountContainer.Name) + '/' + $VHDFileName + $SASToken
#endregion

#region Use AzCopy to upload the image to the storage account
Write-Host "Copying the image to the Storage Account Container. Please wait..." -ForegroundColor Green
$ENV:AZCOPY_DEFAULT_SERVICE_API_VERSION="2017-11-09"
azcopy copy $ImagePath $DestinationUrl
#endregion

#region Loop through each region and add the platform image
foreach ($HubRegion in $HubRegions)
{
    Write-Host "Creating the image $ImageSku in region $HubRegion" -ForegroundColor Green
    if ($HubRegion -ne $Location.Location)
    {
        $TempEnvironment = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://adminmanagement.$HubRegion.*"}
        Connect-AzAccount -Environment $($TempEnvironment.Name) -DeviceCode -ErrorAction 'Stop'
        $TempSubscription = Get-AzSubscription -SubscriptionName 'Default Provider Subscription'
        Set-AzContext $TempSubscription
        $TempLocation = Get-AzLocation
        Add-AzsPlatformImage -Offer $ImageOffer -Publisher $ImagePublisher -Sku $ImageSku -Version $ImageVersion -OSUri $DestinationUrl -OsType $ImageOSType -Location $TempLocation.Location -AsJob
    }
    else
    {
        Add-AzsPlatformImage -Offer $ImageOffer -Publisher $ImagePublisher -Sku $ImageSku -Version $ImageVersion -OSUri $DestinationUrl -OsType $ImageOSType -Location $Location.Location -AsJob
    }
}

Get-Job | Wait-Job
#endregion

#region Cleanup our mess
Write-Host "Returning to the original Admin Subscription to clean up" -ForegroundColor Green
$Contexts = Get-AzContext -ListAvailable
$NewContext = $Contexts | Where-Object {($_.Environment.Name -eq $($Environment.Name)) -and ($_.Subscription.Name -eq 'Default Provider Subscription')}
Set-AzContext $NewContext
$Location = Get-AzLocation

Write-Host "Removing temporary Storage Account" -ForegroundColor Green
Remove-AzStorageAccount -ResourceGroupName $TemporaryStorageAccount.ResourceGroupName -Name $TemporaryStorageAccount.StorageAccountName -Force

Write-Host "Removing temporary Resource Group" -ForegroundColor Green
Remove-AzResourceGroup -Name $TemporaryResourceGroup.ResourceGroupName -Force
#endregion