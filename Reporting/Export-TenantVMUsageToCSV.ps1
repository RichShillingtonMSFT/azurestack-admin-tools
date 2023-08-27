<#
.SYNOPSIS
    Script to export Azure Stack Hub IaaS VM Usage Details to CSV

.DESCRIPTION
    This script will roll through each Subscription you have read access to.
    It will then export the details of each VM to a CSV file.
    The details include but are not limited to:

    SubscriptionName
    SubscriptionId
    VMName
    VMSku
    OSPublisher
    OSOffer
    OSSku
    MaxResourceVolumeMB
    OSDiskSizeGB
    vCPUs
    MemoryGB
    MaxDataDiskCount
    vCPUsAvailable
    GPUs
    ACUs
    vCPUsPerCore
    DataDiskSizeInGB

    The default export location is \UserProfile\Documents\

.PARAMETER FileSaveLocation
    Specify the output location for the CSV File
    Example: 'C:\Temp'
    Default location is \UserProfile\Documents\

.PARAMETER ResourceManagerUrl
    Specify the Resource Manager Url
    Example: 'https://management.hub1.contoso.com'

.EXAMPLE
    .\Export-TenantVMUsageToCSV.ps1 -ResourceManagerUrl 'https://management.hub1.contoso.com' -FileSaveLocation 'C:\Temp'
#>
[CmdletBinding()]
param
(
	# Specify the output location for the CSV File
	[Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	[String]$FileSaveLocation = "$env:USERPROFILE\Documents\",

	# Specify the Resource Manager Url
	[Parameter(Mandatory=$true,HelpMessage="Specify the Resource Manager Url. Example https://management.hub1.contoso.com")]
	[String]$ResourceManagerUrl
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


function Invoke-CreateAuthHeader
{
    $AzureContext = Get-AzContext
    $AzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $ProfileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($AzureProfile)
    $Token = $ProfileClient.AcquireAccessToken($AzureContext.Subscription.TenantId)
    $AuthHeader = @{
        'Content-Type'='application/json'
        'Authorization'='Bearer ' + $Token.AccessToken
    }

    return $AuthHeader
}

$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("SubscriptionName","string") | Out-Null
$DataTable.Columns.Add("SubscriptionId","string") | Out-Null
$DataTable.Columns.Add("VMName","string") | Out-Null
$DataTable.Columns.Add("VMSku","string") | Out-Null
$DataTable.Columns.Add("OSPublisher","string") | Out-Null
$DataTable.Columns.Add("OSOffer","string") | Out-Null
$DataTable.Columns.Add("OSSku","string") | Out-Null
$DataTable.Columns.Add("MaxResourceVolumeMB","string") | Out-Null
$DataTable.Columns.Add("OSDiskSizeGB","string") | Out-Null
$DataTable.Columns.Add("vCPUs","string") | Out-Null
$DataTable.Columns.Add("MemoryGB","string") | Out-Null
$DataTable.Columns.Add("MaxDataDiskCount","string") | Out-Null
$DataTable.Columns.Add("vCPUsAvailable","string") | Out-Null
$DataTable.Columns.Add("GPUs","string") | Out-Null
$DataTable.Columns.Add("ACUs","string") | Out-Null
$DataTable.Columns.Add("vCPUsPerCore","string") | Out-Null
$DataTable.Columns.Add("DataDisk0SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk1SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk2SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk3SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk4SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk5SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk6SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk7SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk8SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk9SizeInGB","string") | Out-Null
$DataTable.Columns.Add("DataDisk10SizeInGB","string") | Out-Null

$Subscriptions = Get-AzSubscription

foreach ($Subscription in $Subscriptions)
{
    Set-AzContext $Subscription

    #region Get SKUs
    $restUri = $ResourceManagerUrl + '/subscriptions/' + $Subscription.Id + '/providers/Microsoft.Compute/skus?' + 'api-version=2017-03-30'
    $AuthHeader = Invoke-CreateAuthHeader
    $Skus = Invoke-RestMethod -Uri $restUri -Method Get -Headers $AuthHeader
    #endregion

    #region Get VMs
    $restUri = $ResourceManagerUrl + '/subscriptions/' + $Subscription.Id + '/providers/Microsoft.Compute/virtualMachines?' + 'api-version=2020-06-01'
    $AuthHeader = Invoke-CreateAuthHeader
    $VMs = Invoke-RestMethod -Uri $restUri -Method Get -Headers $AuthHeader
    #endregion

    foreach ($VM in $VMs.value)
    {
        $SizeDetails = $Skus.value | Where-Object {$_.Name -eq $VM.properties.hardwareProfile.vmSize}

        $NewRow = $DataTable.NewRow()
        $NewRow.SubscriptionName = $($Subscription.Name)
        $NewRow.SubscriptionId = $($Subscription.Id)
        $NewRow.VMName = $($VM.name)
        $NewRow.VMSku = $($vm.properties.hardwareProfile.vmSize)
        $NewRow.OSPublisher = $($VM.properties.storageProfile.imageReference.publisher)
        $NewRow.OSOffer = $($VM.properties.storageProfile.imageReference.offer)
        $NewRow.OSSku = $($VM.properties.storageProfile.imageReference.sku)
        $NewRow.MaxResourceVolumeMB = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "MaxResourceVolumeMB"}).Value)
        $NewRow.OSDiskSizeGB = $($VM.properties.storageProfile.osDisk.diskSizeGB)
        $NewRow.vCPUs = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "vCPUs"}).Value)
        $NewRow.MemoryGB = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "MemoryGB"}).Value)
        $NewRow.MaxDataDiskCount = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "MaxDataDiskCount"}).Value)
        $NewRow.vCPUsAvailable = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "vCPUsAvailable"}).Value)
        $NewRow.GPUs = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "GPUs"}).Value)
        $NewRow.ACUs = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "ACUs"}).Value)
        $NewRow.vCPUsPerCore = $(($SizeDetails.capabilities | Where-Object {$_.Name -like "vCPUsPerCore"}).Value)
    
        $DataDisks = $vm.properties.storageProfile.dataDisks
        $TotalDataDiskCount = $DataDisks.Count
        $DataDiskCount = 0
        foreach ($DataDisk in $DataDisks)
        {
            $NewRow.('DataDisk' + $DataDiskCount + 'SizeInGB') = $($DataDisk.diskSizeGB)
            $DataDiskCount ++
        }

        $DataTable.Rows.Add($NewRow)
    }

}

$CSVFileName = 'AzureStackVMUsage' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
