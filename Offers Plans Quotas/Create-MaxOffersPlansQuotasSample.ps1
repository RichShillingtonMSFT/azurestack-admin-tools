<#
.SYNOPSIS
    Script to create Offers, Plans & Quotas

.DESCRIPTION
    Use this script as a template for creating Offers, Plans & Quotas using PowerShell

.EXAMPLE
    .\Create-OffersPlansQuotasSample.ps1
#>
[CmdletBinding()]
Param
(
    [String]$ResourceGroupName = 'offers.plans.quotas.rg'
)

# Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack Admin Enviornment." -PassThru

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
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select the Default Provider Subscription." -PassThru
        Select-AzureRmSubscription $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$Location = Get-AzureRmLocation
#endregion

$ResourceGroup = Get-AzureRMResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$ResourceGroup)
{
    New-AzureRMResourceGroup -Name $ResourceGroupName -Location $Location.Location
}

#region Maximum IaaS Plan

#region Create Quota
$ComputeQuota = New-AzsComputeQuota -Name 'Maximum_IaaS_Compute_Quota' -AvailabilitySetCount '10' `
    -CoresCount '2500' -VMScaleSetCount '1000' `
    -VirtualMachineCount '1200' -StandardManagedDiskAndSnapshotSize '204800' `
    -PremiumManagedDiskAndSnapshotSize '204800' -Location $Location.Location

$NetworkQuota = New-AzsNetworkQuota -Name 'Maximum_IaaS_Network_Quota' -MaxNicsPerSubscription '1200' `
    -MaxPublicIpsPerSubscription '2400' -MaxVirtualNetworkGatewayConnectionsPerSubscription '100' `
    -MaxVnetsPerSubscription '1200' -MaxVirtualNetworkGatewaysPerSubscription '1000' `
    -MaxSecurityGroupsPerSubscription '2400' -MaxLoadBalancersPerSubscription '1200' `
    -Location $Location.Location

$StorageQuota = New-AzsStorageQuota -Name 'Maximum_IaaS_Storage_Quota' -CapacityInGb '50000' `
    -NumberOfStorageAccounts '2500' -Location $Location.Location

$KeyVaultQuota = Get-AzsKeyVaultQuota
#endregion

#region Plan
$Plan = New-AzsPlan -Name 'Maximum_IaaS_Plan' -ResourceGroupName $ResourceGroupName `
    -DisplayName 'Maximum IaaS Plan' -Description 'Maximum IaaS Plan' `
    -QuotaIds "$($ComputeQuota.Id)","$($NetworkQuota.Id)","$($StorageQuota.Id)","$($KeyVaultQuota.Id)" `
    -Location $Location.Location
#endregion

#region Offer
New-AzsOffer -Name 'Maximum_IaaS_Offer' -DisplayName 'Maximum IaaS Offer' `
    -ResourceGroupName $ResourceGroupName -BasePlanIds $Plan.Id `
    -Description 'Maximum IaaS Offer' -State 'Private' -Location $Location.Location
#endregion

#endregion