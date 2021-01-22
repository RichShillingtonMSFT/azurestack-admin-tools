<#
.SYNOPSIS
    Script to export Azure Stack SKUs To CSV

.DESCRIPTION
    This script will find all available Publishers
    Check each Publisher for any Offers
    Check each Offer for available SKUs
    Then export the list to a CSV file
    The default export location is \UserProfile\Documents\

.PARAMETER FileSaveLocation
    Specify the output location for the CSV File
    Example: 'C:\Temp'
    Default location is \UserProfile\Documents\

.EXAMPLE
    .\Export-AzureStackSKUsToCSV.ps1 -FileSaveLocation 'C:\Temp'
#>
[CmdletBinding()]
param
(
	# Specify the output location for the CSV File
	[Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	[String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
)

# Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzureRmAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
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
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
        Select-AzureRmSubscription $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

# Location Selection
$Locations = Get-AzureRmLocation
$Location = ($Locations | Out-GridView -Title "Please Select a location." -PassThru).Location

$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("PublisherName","string") | Out-Null
$DataTable.Columns.Add("Location","string") | Out-Null
$DataTable.Columns.Add("Offer","string") | Out-Null
$DataTable.Columns.Add("Sku","string") | Out-Null

$Publishers = Get-AzureRmVMImagePublisher -Location $Location
Write-Host "Found $($Publishers.Count) Publishers"

foreach ($Publisher in $Publishers)
{
    Write-Host "Working on Publisher $($Publisher.PublisherName)" -ForegroundColor White

    $Offers = Get-AzureRmVMImageOffer -Location $Location -PublisherName $Publisher.PublisherName

    if ($($Offers.Count) -gt '0')
    {
        Write-Host "Publisher $($Publisher.PublisherName) has $($Offers.Count) Offers" -ForegroundColor Yellow

        foreach ($Offer in $Offers)
        {
            Write-Host "Working on Offer $($Offer.Offer)" -ForegroundColor Cyan

            $SKUs = Get-AzureRmVMImageSku -Location $Location -PublisherName $Publisher.PublisherName -Offer $Offer.Offer

            if ($($SKUs.Count) -gt '0')
            {
                Write-Host "Publisher $($Publisher.PublisherName), Offer $($Offer.Offer), contains $($SKUs.Count) SKUs"  -ForegroundColor Green

                foreach ($SKU in $SKUs)
                {
                    Write-Host "Working on SKU $($SKU.Skus)" -ForegroundColor Magenta

                    $NewRow = $DataTable.NewRow()
                    $NewRow.PublisherName = $($Publisher.PublisherName)
                    $NewRow.Location = $Location
                    $NewRow.Offer = $($Offer.Offer)
                    $NewRow.Sku = $($SKU.Skus)
                    $DataTable.Rows.Add($NewRow)
                }
            }
            else
            {
                 Write-Host "Publisher $($Publisher.PublisherName) Offer $($Offers.Offer) contains $($SKUs.Count) SKUs" -ForegroundColor Red
                 Continue
            }
        }
    }
    else
    {
        Write-Host "Publisher $($Publisher.PublisherName) has $($Offers.Count) Offers" -ForegroundColor Red
        Continue
    }
}

$CSVFileName = 'AzureStackSkus' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation