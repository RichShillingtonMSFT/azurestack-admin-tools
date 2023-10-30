<#
.SYNOPSIS
    Script to create User Subscriptions with custom offers, plans & quotas

.DESCRIPTION
    Use this script to create User Subscriptions with custom offers, plans & quotas

.EXAMPLE
    .\Create-NewUserSubscriptionWithAccompanyingOffer.ps1 `
        -NewSubscriptionName 'Development Subscription' `
        -NewSubscriptionOwnerUPN 'fred@contoso.com' `
        -ComputeQuotaVirtualMachineCount '100'
        -IncludeEventHubs `
        -IncludeAzureSiteRecovery
#>
[CmdletBinding()]
Param
(
    # Provide a name for the new subscription
	[Parameter(Mandatory=$true,HelpMessage="Provide a name for the new subscription")]
    [String]$NewSubscriptionName,

    # Provide the full UPN for the Subscription Owner
	[Parameter(Mandatory=$true,HelpMessage="Provide the full UPN for the Subscription Owner")]
    [MailAddress]$NewSubscriptionOwnerUPN,

    # Provide a name for the new subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide a name for the Offers, Plans & Quotas Resource Group")]
    [String]$OffersPlansQuotasResourceGroupName = 'offers.plans.quotas.rg',

    # Provide a Compute Quota Cores Count
	[Parameter(Mandatory=$true,HelpMessage="Provide a Compute Quota Cores Count")]
    [Int]$ComputeQuotaCoresCount,

    # Provide a Compute Quota Virtual Machine Count
	[Parameter(Mandatory=$true,HelpMessage="Provide a Compute Quota Virtual Machine Count")]
    [Int]$ComputeQuotaVirtualMachineCount,

    # Provide a Compute Quota Availability Set Count
	[Parameter(Mandatory=$false,HelpMessage="Provide a Compute Quota Availability Set Count")]
    [Int]$ComputeQuotaAvailabilitySetCount = '10',

    # Provide a Compute Quota Virtual Machine Scale Set Count
	[Parameter(Mandatory=$false,HelpMessage="Provide a Compute Quota Virtual Machine Scale Set Count")]
    [Int]$ComputeQuotaVirtualMachineScaleSetCount = '10',

    # Provide a Compute Quota Standard Managed Disk And Snapshot Size Subscription Total in MB
	[Parameter(Mandatory=$true,HelpMessage="Provide a Compute Quota Standard Managed Disk And Snapshot Size Subscription Total in MB")]
    [Int]$ComputeQuotaStandardManagedDiskAndSnapshotSize,

    # Provide a Compute Quota Premium Managed Disk And Snapshot Size Subscription Total in MB
	[Parameter(Mandatory=$true,HelpMessage="Provide a Compute Quota Premium Managed Disk And Snapshot Size Subscription Total in MB")]
    [Int]$ComputeQuotaPremiumManagedDiskAndSnapshotSize,

    # Provide the Maximum NICs Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum NICs Count for the Subscription")]
    [Int]$MaxNicsPerSubscription = '500',

    # Provide the Maximum Public IPs Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Public IPs Count for the Subscription")]
    [Int]$MaxPublicIpsPerSubscription = '1',

    # Provide the Maximum Virtual Network Gateways Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Virtual Network Gateway Count for the Subscription")]
    [Int]$MaxVirtualNetworkGatewaysPerSubscription = '1',

    # Provide the Maximum Virtual Network Gateway Connections Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Virtual Network Gateway Connections Count for the Subscription")]
    [Int]$MaxVirtualNetworkGatewayConnectionsPerSubscription = '5',

    # Provide the Maximum Virtual Networks Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Virtual Networks Count for the Subscription")]
    [Int]$MaxVirtualNetworksPerSubscription = '50',

    # Provide the Maximum Network Security Group Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Network Security Group Count for the Subscription")]
    [Int]$MaxNetworkSecurityGroupsPerSubscription = '1000',

    # Provide the Maximum Load Balancer Count for the Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide the Maximum Load Balancer Count for the Subscription")]
    [Int]$MaxLoadBalancersPerSubscription = '10',

    # Provide the Maximum Number of Storage Accounts per Subscription
	[Parameter(Mandatory=$true,HelpMessage="Provide the Maximum Number of Storage Accounts per Subscription")]
    [Int]$MaxNumberOfStorageAccountsPerSubscriptionCount,

    # Provide the Maximum Storage Account Capacity in GB per Subscription
	[Parameter(Mandatory=$true,HelpMessage="Provide the Maximum Storage Account Capacity in GB per Subscription")]
    [Int]$MaxStorageAccountCapacityPerSubscriptionCount,

    [Parameter(Mandatory=$false,HelpMessage="Switch to Include Event Hubs")]
    [Switch]$IncludeEventHubs,

    [Parameter(Mandatory=$false,HelpMessage="Switch to Include Azure Site Recovery")]
    [Switch]$IncludeAzureSiteRecovery,

    [Parameter(Mandatory=$false,HelpMessage="Provide the Azure Stack DNS Domain. Example: contoso.com")]
    [String]$AzureStackDNSDomain,

    [Parameter(Mandatory=$false,HelpMessage="Provide your Azure Stack Region Names. Example: HUB01,HUB02,HUB03")]
    [Array]$AzureStackRegionNames,
)
DynamicParam 
{
    if ($IncludeEventHubs)
    {
        $NewEventHubQuotaCoreCountAttribute = New-Object System.Management.Automation.ParameterAttribute
        $NewEventHubQuotaCoreCountAttribute.Mandatory = $true
        $NewEventHubQuotaCoreCountAttribute.HelpMessage = "Provide the Maximum Event Hubs Core Count"
        $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        $attributeCollection.Add($NewEventHubQuotaCoreCountAttribute)
        $NewEventHubQuotaCoreCountParam = New-Object System.Management.Automation.RuntimeDefinedParameter('NewEventHubQuotaCoreCount', [Int16], $attributeCollection)
        $paramDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $paramDictionary.Add('NewEventHubQuotaCoreCount', $NewEventHubQuotaCoreCountParam)
        return $paramDictionary
   }
}

Process
{
    #region Add Azure Stack Environments
    foreach ($AzureStackRegion in $AzureStackRegionNames)
    {
        $AzureStackAdminEnvironmentName = $AzureStackRegion + '-AzS-Admin'
        $AzureStackFQDN = $AzureStackRegion + '.' + $AzureStackDNSDomain
        Add-AzEnvironment -Name $AzureStackAdminEnvironmentName -ARMEndpoint ('https://adminmanagement.' + $AzureStackFQDN) `
            -AzureKeyVaultDnsSuffix ('adminvault.' + $AzureStackFQDN) `
            -AzureKeyVaultServiceEndpointResourceId ('https://adminvault.' + $AzureStackFQDN)

        $AzureStackUserEnvironmentName = $AzureStackRegion + '-AzS-User'
        Add-AzEnvironment -Name $AzureStackUserEnvironmentName -ARMEndpoint ('https://management.' + $AzureStackFQDN)
    }
    #endregion

    #region Connect to Azure
    $Environments = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://adminmanagement.*"}
    $Environment = $Environments | Out-GridView -Title "Please Select the Azure Stack Admin Enviornment." -PassThru
    try
    {
        Connect-AzAccount -Environment $($Environment.Name)
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

    $Location = Get-AzLocation
    #endregion

    #region Rest API Header Function
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
    #endregion

    #region Check for Resource Group
    $OffersPlansQuotasResourceGroup = Get-AzResourceGroup -Name $OffersPlansQuotasResourceGroupName -ErrorAction SilentlyContinue
    if (!$OffersPlansQuotasResourceGroup)
    {
        New-AzResourceGroup -Name $OffersPlansQuotasResourceGroupName -Location $Location.Location
    }
    #endregion

    #region Create Variables
    $CleanSubscriptionName = $NewSubscriptionName -replace '\W','-'
    $NewComputeQuotaName = ($CleanSubscriptionName + '_Compute_Quota')
    $NewNetworkQuotaName = ($CleanSubscriptionName + '_Network_Quota')
    $NewStorageQuotaName = ($CleanSubscriptionName + '_Storage_Quota')
    $NewPlanName = ($CleanSubscriptionName + '_Plan')
    $NewPlanDisplayName = ($CleanSubscriptionName  + ' Plan')
    $NewPlanDescription = "Plan created for Subscription $($NewSubscriptionName)"
    $NewOfferName = ($CleanSubscriptionName + '_Offer')
    $NewOfferDisplayName = ($NewSubscriptionName + ' Offer')
    $NewOfferDescription = "Offer created for Subscription $($NewSubscriptionName)"
    $NewOfferState = 'Private'
    #endregion

    #region Create Quotas
    $Quotas = @()

    # Create Compute Quota
    $ComputeQuota = New-AzsComputeQuota -Name $NewComputeQuotaName -AvailabilitySetCount $ComputeQuotaAvailabilitySetCount `
        -CoresCount $ComputeQuotaCoresCount -VMScaleSetCount $ComputeQuotaVirtualMachineScaleSetCount `
        -VirtualMachineCount $ComputeQuotaVirtualMachineCount -StandardManagedDiskAndSnapshotSize $ComputeQuotaStandardManagedDiskAndSnapshotSize `
        -PremiumManagedDiskAndSnapshotSize $ComputeQuotaPremiumManagedDiskAndSnapshotSize -Location $Location.Location

    $Quotas += $ComputeQuota.Id

    # Create Network Quota
    $NetworkQuota = New-AzsNetworkQuota -Name $NewNetworkQuotaName -MaxNicsPerSubscription $MaxNicsPerSubscription `
        -MaxPublicIpsPerSubscription $MaxPublicIpsPerSubscription -MaxVirtualNetworkGatewayConnectionsPerSubscription $MaxVirtualNetworkGatewayConnectionsPerSubscription `
        -MaxVnetsPerSubscription $MaxVirtualNetworksPerSubscription -MaxVirtualNetworkGatewaysPerSubscription $MaxVirtualNetworkGatewaysPerSubscription `
        -MaxSecurityGroupsPerSubscription $MaxNetworkSecurityGroupsPerSubscription -MaxLoadBalancersPerSubscription $MaxLoadBalancersPerSubscription `
        -Location $Location.Location

    $Quotas += $NetworkQuota.Id

    # Create Storage Quota
    $StorageQuota = New-AzsStorageQuota -Name $NewStorageQuotaName -CapacityInGb $MaxStorageAccountCapacityPerSubscriptionCount `
        -NumberOfStorageAccounts $MaxNumberOfStorageAccountsPerSubscriptionCount `
        -Location $Location.Location

    $Quotas += $StorageQuota.Id

    # Get Keyvault Quota
    $Quotas += $((Get-AzsKeyVaultQuota).Id)

    if ($IncludeEventHubs)
    {
        $NewEventHubQuotaName = ($CleanSubscriptionName + '_EventHubs_Quota')
        $EventHubJSON = @"
        {
            "name": "$($NewEventHubQuotaName)",
            "type": "Microsoft.EventHub.Admin/quotas",
            "location": "$($Location.DisplayName)",
            "properties": {
                "coresCount": "$($NewEventHubQuotaCoreCount)"
            }
        }
"@

        $restUri = $($Environment.ResourceManagerUrl) + "/subscriptions/$($Subscription.Id)/providers/Microsoft.EventHub.Admin/locations/$($Location.DisplayName)/quotas/$($NewEventHubQuotaName)?api-version=2018-01-01-preview"
        $AuthHeader = Invoke-CreateAuthHeader
        $Response = Invoke-RestMethod -Uri $restUri -Method PUT -Headers $AuthHeader -Body $EventHubJSON
        $Quotas += $($Response.id)
    }

    if ($IncludeAzureSiteRecovery)
    {
        $Quotas += "/subscriptions/$($Subscription.Id)/providers/Microsoft.DataReplication.Admin/locations/$($Location.DisplayName)/quotas/Unlimited"
    }
    #endregion

    #region Creata Plan
    $NewPlan = New-AzsPlan -Name $NewPlanName -ResourceGroupName $OffersPlansQuotasResourceGroupName `
        -DisplayName $NewPlanDisplayName -Description $NewPlanDescription `
        -QuotaIds $Quotas `
        -Location $Location.Location
    #endregion

    #region Create Offer
    $NewOffer = New-AzsOffer -Name $NewOfferName -DisplayName $NewOfferDisplayName `
        -ResourceGroupName $OffersPlansQuotasResourceGroupName -BasePlanIds $NewPlan.Id `
        -Description $NewOfferDescription -State $NewOfferState -Location $Location.Location
    #endregion

    #region Create User Subscription
    $NewUserSubscription = New-AzsUserSubscription -Owner $NewSubscriptionOwnerUPN -DisplayName $NewSubscriptionName -OfferId $NewOffer.Id
    #endregion

    #region Connect to New User Subscription
    $NewSubscriptionEnvironment = Get-AzEnvironment | Where-Object {$_.ResourceManagerUrl -like "https://management.$($Enviornment.Name -replace "-.*$")*"}
    Connect-AzAccount -Enviornment $($NewSubscriptionEnvironment.Name)
    $NewSubscription = Get-AzSubscription -SubscriptionId $NewUserSubscription.SubscriptionId
    Set-AzContext $NewSubscription
    #endregion

    #region Create Resource Group & Storage Account for Activity Logs
    $DiagnosticsResourceGroupName = $($NewSubscription.Name).replace(' ','') + '-activitylogs-rg'
    $DiagnosticsResourceGroup = New-AzResourceGroup -Name $DiagnosticsResourceGroupName -location $Location.Location
    if (($NewSubscription.Name).Length -lt 12)
    {
        $Substring = ($NewSubscription.Name).Length
    }
    if (($NewSubscription.Name).Length -ge 12)
    {
        $Substring = 12
    }
    $DiagnosticsStorageAccountName = $(($NewSubscription.Name).ToLower().replace(' ','')).Substring(0, $Substring) + 'activitylog'
    $DiagnosticsStorageAccount = New-AzStorageAccount -ResourceGroupName $DiagnosticsResourceGroup.ResourceGroupName -Name $DiagnosticsStorageAccountName -SkuName Standard_LRS -Location $Location.Location -EnableHttpsTrafficOnly:$true
    #endregion

    #region Set Activity Logs to Archive to Storage Account
    $ActivvityLogJSON = @"
    {
        "name": "activitylogs",
        "properties": {
            "metrics": [],
            "storageAccountId": "$($DiagnosticsStorageAccount.Id)",        
            "logs": [
                {
                    "category": "Administrative",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "Security",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "ServiceHealth",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "Alert",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "Recommendation",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "Policy",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "Autoscale",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                },
                {
                    "category": "ResourceHealth",
                    "enabled": true,
                    "retentionPolicy": {
                        "days": 0,
                        "enabled": false
                    }
                }
            ]
        }
    }
"@

    $restUri = $($NewSubscriptionEnvironment.ResourceManagerUrl) + "/subscriptions/$($NewSubscription.SubscriptionId)/providers/Microsoft.Insights/diagnosticSettings/activitylogs?api-version=2017-05-01-preview"
    $AuthHeader = Invoke-CreateAuthHeader
    $Response = Invoke-RestMethod -Uri $restUri -Method PUT -Headers $AuthHeader -Body $ActivvityLogJSON
    $Response
}
