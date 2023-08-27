<#
.SYNOPSIS
    Script to export Azure Stack Hub Storage Account Usage Details to CSV

.DESCRIPTION
    This script will roll through each Subscription you have read access to.
    It will then export the details of each Storage Account to a CSV file.
    The details include:

    SubscriptionName
    SubscriptionId
    StorageAccountName
    StorageAccountResourceGroupName
    StorageAccountCreationDateTime
    ContainerCount
    TotalSizeInGB

    The default export location is \UserProfile\Documents\

.PARAMETER FileSaveLocation
    Specify the output location for the CSV File
    Example: 'C:\Temp'
    Default location is \UserProfile\Documents\

.EXAMPLE
    .\Export-TenantStorageAccountUsageToCSV.ps1 -FileSaveLocation 'C:\Temp'
#>
[CmdletBinding()]
param
(
	# Specify the output location for the CSV File
	[Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	[String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
)

# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack Admin Enviornment." -PassThru

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

$Location = Get-AzLocation
#endregion

$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("SubscriptionName","string") | Out-Null
$DataTable.Columns.Add("SubscriptionId","string") | Out-Null
$DataTable.Columns.Add("StorageAccountName","string") | Out-Null
$DataTable.Columns.Add("StorageAccountResourceGroupName","string") | Out-Null
$DataTable.Columns.Add("StorageAccountCreationDateTime","DateTime") | Out-Null
$DataTable.Columns.Add("StorageAccountSkuName","string") | Out-Null
$DataTable.Columns.Add("StorageAccountSkuTier","string") | Out-Null
$DataTable.Columns.Add("ContainerCount","Int") | Out-Null
$DataTable.Columns.Add("TotalSizeInGB","Int") | Out-Null
$DataTable.Columns.Add("BlobEnpoint","String") | Out-Null
$DataTable.Columns.Add("QueueEnpoint","String") | Out-Null
$DataTable.Columns.Add("TableEnpoint","String") | Out-Null

$Subscriptions = Get-AzSubscription
Write-output "Found $($Subscriptions.Count) Subscriptions"

[Int]$SubscriptionCount = 1

foreach ($Subscription in $Subscriptions)
{
    Set-AzContext $Subscription

    Write-output "Checking for Storage Accounts in Subscription $SubscriptionCount of $($Subscriptions.Count)"
    
    $StorageAccounts = Get-AzStorageAccount

    [Int]$StorageAccountCount = $($StorageAccounts.Count)

    Write-output "Found $StorageAccountCount Storage Accounts"

    if ($StorageAccountCount -ge 1)
    {
        [Int]$StorageAccountProgress = 1

        foreach ($StorageAccount in $StorageAccounts)
        {
            $NewRow = $DataTable.NewRow()
            $NewRow.SubscriptionName = $($Subscription.Name)
            $NewRow.SubscriptionId = $($Subscription.Id)
            $NewRow.StorageAccountName = $($StorageAccount.StorageAccountName)
            $NewRow.StorageAccountResourceGroupName = $($StorageAccount.ResourceGroupName)
            $NewRow.StorageAccountCreationDateTime = $($StorageAccount.CreationTime)
            $NewRow.StorageAccountSkuName = $($StorageAccount.value.Sku.Name)
            $NewRow.StorageAccountSkuTier = $($StorageAccount.value.Sku.Tier)

            $StorageBlobUsage = @()

            Write-output "Checking Storage Account $StorageAccountProgress of $StorageAccountCount for Containers"
            $Containers = Get-AzStorageContainer -Context $StorageAccount.Context

            $ContainerCount = $Containers.Count

            if ($ContainerCount -ge 1)
            {
                Write-output "Found $ContainerCount Containers"
                $ContainerProgress = 1
                $NewRow.ContainerCount = $ContainerCount

                foreach ($Container in $Containers)
                {
                    Write-output "Gathering Blob data from Container $ContainerProgress of $ContainerCount"

                    $Blobs =  $Container | Get-AzStorageBlob

                    [Int]$BlobCount = $Blobs.Count

                    if ($BlobCount -ge 1)
                    {
                        [Int]$BlobProgress = 1

                        Write-output "Found $BlobCount Blobs in container $ContainerProgress of $ContainerCount" 
                        foreach ($Blob in $Blobs)
                        {
                            Write-output "Checking size of Blob $BlobProgress of $BlobCount in container $ContainerProgress of $ContainerCount" 

                            $StorageBlobUsage += $Blob.Length

                            $BlobProgress ++
                        }
                    }

                    $ContainerProgress ++
                }
            }

            $NewRow.TotalSizeInGB = $($StorageBlobUsage | Measure-Object -Sum).Sum/1GB

            $NewRow.BlobEndpoint = $StorageAccount.value.Properties.primaryEndpoints.blob
            $NewRow.QueueEndpoint = $StorageAccount.value.Properties.primaryEndpoints.queue
            $NewRow.TableEndpoint = $StorageAccount.value.Properties.primaryEndpoints.table

            $DataTable.Rows.Add($NewRow)
        }
    }

    $SubscriptionCount ++
}

$CSVFileName = 'AzureStackStorageAccountUsage' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
