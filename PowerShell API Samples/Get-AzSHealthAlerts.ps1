# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

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
    $Subscriptions = Get-AzSubscription
    if ($Subscriptions.Count -gt '1')
    {
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription for Policy Evaluation." -PassThru
        Set-AzContext $Subscription
        $SubscriptionID = $Subscription.Id
    }
    else
    {
        $Subscription = $Subscriptions
        Select-AzSubscription $Subscription
        $SubscriptionID = $Subscription.Id
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion


$Location = (Get-AzLocation).DisplayName
$SystemResourceGroupName = 'system.' + $Location


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

# Get Region Health
function Get-RegionHealth ($SubscriptionID,$SystemResourceGroupName,$Location)
{
    $restUri = $($Environment.ResourceManagerUrl) + "/subscriptions/$SubscriptionID/resourceGroups/$SystemResourceGroupName/providers/Microsoft.InfrastructureInsights.Admin/regionHealths/$Location/Alerts?api-version=2016-05-01&$Filter"
    $AuthHeader = Invoke-CreateAuthHeader
    $Response = Invoke-RestMethod -Uri $restUri -Method GET -Headers $AuthHeader
    return $Response
}

$Health = Get-RegionHealth -SubscriptionID $SubscriptionID -SystemResourceGroupName $SystemResourceGroupName -Location $Location
$ActiveAlerts = $Health.value | Where-Object {$_.Properties.State -eq 'Active'}

$ActiveAlerts.Properties | Out-GridView
