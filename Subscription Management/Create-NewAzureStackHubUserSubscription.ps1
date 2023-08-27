<#
.SYNOPSIS
    Script to create a new User Subscription

.DESCRIPTION
    This script can be used to create a new User Subscription
    You must provide a UPN for the owner and a Subscription Name.
    You will be prompted to select the offer to use.

.PARAMETER NewSubscriptionOwner
    Specify the full UPN of the new Subscription Owner
    Example: 'joe.smith@contoso.com'

.PARAMETER NewSubscriptionName
    Provide a Name for the new Subscription
    Example: 'Development Testing'

.EXAMPLE
    .\Create-NewAzureStackHubUserSubscription.ps1 -NewSubscriptionOwner 'joe.smith@contoso.com' -NewSubscriptionName 'Development'
#>
[CmdletBinding()]
param
(
	# Specify the full UPN of the new Subscription Owner
	[Parameter(Mandatory=$true,HelpMessage="Specify the full UPN of the new Subscription Owner. Example joe.smith@contoso.com")]
	[String]$NewSubscriptionOwner,

    # Provide a Name for the new Subscription
	[Parameter(Mandatory=$true,HelpMessage="Provide a Name for the new Subscription. Example Development Testing")]
	[String]$NewSubscriptionName
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


$Offers = Get-AzsAdminManagedOffer
$Offer = $Offers | Select-Object -Property Name,Description | Out-GridView -Title "Please Select the Offer to assign to the new Subscription." -PassThru
$Offer = $Offers | Where-Object {$_.Name -eq $Offer.Name}

$UserSubscriptions = Get-AzsUserSubscription
if ($UserSubscriptions.DisplayName -contains $NewSubscriptionName)
{
    Write-Host "The subscription name you provided is in use. Please provide a new Subscription Name" -ForegroundColor Red
    Write-Host "Current User Subscriptions:" -ForegroundColor Yellow
    foreach ($UserSubscriptionsDisplayName in $UserSubscriptions.DisplayName)
    {
        Write-Host "$UserSubscriptionsDisplayName" -ForegroundColor Yellow
    }

    do {
    $NewSubscriptionName = Read-Host 'Please provide a new Subscription Name'
    }
    until ($UserSubscriptions.DisplayName -notcontains $NewSubscriptionName)
}

Write-Host "Creating User Subscription $NewSubscriptionName and assigning $NewSubscriptionOwner as Owner" -ForegroundColor Green
New-AzsUserSubscription -Owner $NewSubscriptionOwner -OfferId $Offer.Id -Verbose -DisplayName $NewSubscriptionName