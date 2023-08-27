<#
.SYNOPSIS
    Script to create a new User Subscription for Azure Stack Operators Tenant Managment

.DESCRIPTION
    This script can be used to create a new User Subscription for Azure Stack Operators Tenant Managment
    You must provide a UPN for the owner and a Subscription Name.

.PARAMETER NewSubscriptionOwner
    Specify the full UPN of the new Subscription Owner
    Example: 'joe.smith@contoso.com'

.PARAMETER NewSubscriptionName
    Provide a Name for the new Subscription
    Example: 'Azure Stack Operators Tenant Managment'

.EXAMPLE
    .\Create-AzureStackOperatorsTenantManagmentUserSubscription.ps1 -NewSubscriptionOwner 'joe.smith@contoso.com'
#>
[CmdletBinding()]
param
(
	# Specify the full UPN of the new Subscription Owner
	[Parameter(Mandatory=$true,HelpMessage="Specify the full UPN of the new Subscription Owner. Example joe.smith@contoso.com")]
	[String]$NewSubscriptionOwner,

    # Provide a Name for the new Subscription
	[Parameter(Mandatory=$false,HelpMessage="Provide a Name for the new Subscription. Example Development Testing")]
	[String]$NewSubscriptionName = 'Azure Stack Operators Tenant Managment'
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

$Offer = Get-AzsAdminManagedOffer | Where-Object {$_.Name -eq 'Operators-Tenant-Managment-Offer'}

Write-Host "Creating User Subscription $NewSubscriptionName and assigning $NewSubscriptionOwner as Owner" -ForegroundColor Green
New-AzsUserSubscription -Owner $NewSubscriptionOwner -OfferId $Offer.Id -Verbose -DisplayName $NewSubscriptionName