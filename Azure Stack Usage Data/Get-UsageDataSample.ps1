
$Yesterday = (Get-Date).AddDays(-1)
$Yesterday = (Get-Date $Yesterday -Format "yyyy-MM-ddT00:00") + "+00:00Z"
$Now = (Get-Date -Format "yyyy-MM-ddT00:00") + "+00:00Z"

$Usage = Get-UsageAggregates -AggregationGranularity Daily -ReportedStartTime $Yesterday -ReportedEndTime $Now -ShowDetails:$true

$Usage = Get-AzsSubscriberUsage -ReportedStartTime $Yesterday -ReportedEndTime $Now

$Data = $Usage.InstanceData | ConvertFrom-Json

$UsageData = @()

foreach ($Resource in $Data.'Microsoft.Resources')
{
    $UsageData += New-Object PSObject -Property ([ordered]@{ResourceURI=$($Resource.resourceUri);Location=$($Resource.location);Tags=$($Resource.tags);AdditionalInfo=$($Resource.additionalInfo)})
}

$UsageData | Out-GridView
