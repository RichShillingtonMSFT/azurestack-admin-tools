<#
.SYNOPSIS
    Script to create Offers, Plans & Quotas

.DESCRIPTION
    Use this script as a template for creating Offers, Plans & Quotas using PowerShell

.EXAMPLE
    .\Create-OffersPlansQuotasSample.ps1
#>

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

#region Standard IaaS Plan

#region Create Quota
$ComputeQuota = New-AzsComputeQuota -Name 'Standard_IaaS_Compute_Quota' -AvailabilitySetCount '10' `
    -CoresCount '25' -VMScaleSetCount '10' `
    -VirtualMachineCount '12' -StandardManagedDiskAndSnapshotSize '2048' `
    -PremiumManagedDiskAndSnapshotSize '2048' -Location $Location.Location

$NetworkQuota = New-AzsNetworkQuota -Name 'Standard_IaaS_Network_Quota' -MaxNicsPerSubscription '12' `
    -MaxPublicIpsPerSubscription '24' -MaxVirtualNetworkGatewayConnectionsPerSubscription '0' `
    -MaxVnetsPerSubscription '12' -MaxVirtualNetworkGatewaysPerSubscription '0' `
    -MaxSecurityGroupsPerSubscription '24' -MaxLoadBalancersPerSubscription '12' `
    -Location $Location.Location

$StorageQuota = New-AzsStorageQuota -Name 'Standard_IaaS_Storage_Quota' -CapacityInGb '500' `
    -NumberOfStorageAccounts '25' -Location $Location.Location

$KeyVaultQuota = Get-AzsKeyVaultQuota
#endregion

#region Plan
$Plan = New-AzsPlan -Name 'Standard_IaaS_Plan' -ResourceGroupName 'OfferAndPlans-RG' `
    -DisplayName 'Standard IaaS Plan' -Description 'Standard IaaS Plan' `
    -QuotaIds "$($ComputeQuota.Id)","$($NetworkQuota.Id)","$($StorageQuota.Id)","$($KeyVaultQuota.Id)" `
    -Location $Location.Location
#endregion

#region Offer
$Offer = New-AzsOffer -Name 'Standard_IaaS_Offer' -DisplayName 'Standard IaaS Offer' `
    -ResourceGroupName 'OfferAndPlans-RG' -BasePlanIds $Plan.Id `
    -Description 'Standard IaaS Offer' -State 'Private' -Location $Location.Location
#endregion

#endregion