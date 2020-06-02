$ResourceGroupName = 'system.local'

#region Enviornment Selection
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru
#endregion

#region Connect to Azure
try
{
    Add-AzureRmAccount -EnvironmentName $($Environment.Name) -ErrorAction 'Stop'
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
    else
    {
        Select-AzureRmSubscription $Subscriptions
    }

    $AzureContext = Get-AzureRmContext
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

function Invoke-CreateAuthHeader
{
    $AzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $ProfileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($AzureProfile)
    $Token = $ProfileClient.AcquireAccessToken($AzureContext.Subscription.TenantId)
    $AuthHeader = @{
        'Content-Type'='application/json'
        'Authorization'='Bearer ' + $Token.AccessToken
    }

    return $AuthHeader
}

#region Get Scale Unit Data
function Get-ScaleUnitData ($SubscriptionID, $ResourceGroupName)
{
    $restUri = $($Environment.ResourceManagerUrl) + "/subscriptions/$SubscriptionID/resourcegroups/$ResourceGroupName/providers/Microsoft.Fabric.Admin/fabricLocations/local/scaleUnits?api-version=2016-05-01"
    $AuthHeader = Invoke-CreateAuthHeader
    $Results = Invoke-RestMethod -Uri $restUri -Method GET -Headers $AuthHeader
    return $Results
}

$ScaleUnitData = Get-ScaleUnitData -SubscriptionID $($Subscription.Id) -ResourceGroupName $ResourceGroupName

$ScaleUnitData.value
$ScaleUnitData.value.Properties
$ScaleUnitData.value.Properties.totalCapacity
#endregion