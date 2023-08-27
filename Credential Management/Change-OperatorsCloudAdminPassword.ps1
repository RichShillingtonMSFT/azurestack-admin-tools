<#
.SYNOPSIS
    Script to change the password for your Cloud Admin Accounts

.DESCRIPTION
    This script is used to change the password for your Cloud Admin Accounts.

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'AzureStack\CloudAdmin'

.EXAMPLE
    .\Change-OperatorsCloudAdminPassword.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'AzureStack\CloudAdmin'
    [parameter(Mandatory=$true,HelpMessage='Provide the User Name of the Cloud Admin. Example: AzureStack\Joe.Smith')]
    [String]$CloudAdminUserName
)

$RegionInfo = @(
    [PSCustomObject]@{RegionName = 'region1'; DRRegion = 'region2'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'}
    [PSCustomObject]@{RegionName = 'region2'; DRRegion = 'region3'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'}
    [PSCustomObject]@{RegionName = 'region3'; DRRegion = 'region1'; PrivilegedEndpointIP = 'xxx.xxx.xxx.xxx'}
 )


$CurrentCredentials = Get-Credential -Message 'Please enter your CURRENT Cloud Admin Account Password' -UserName $CloudAdminUserName

$NewCredentials = Get-Credential -Message 'Please enter your New Cloud Admin Account Password' -UserName $CloudAdminUserName

foreach ($Region in $RegionInfo)
{
    Write-Host "Connnecting to Privileged Endpoint $($Region.PrivilegedEndpointIP)" -ForegroundColor Green
    $PEPSession = New-PSSession -ComputerName $($Region.PrivilegedEndpointIP) -ConfigurationName PrivilegedEndpoint -Credential $CurrentCredentials -SessionOption (New-PSSessionOption -Culture en-US -UICulture en-US)

    $CloudAdminUserNameTemp = $CurrentCredentials.UserName.Split('\')[1]
    Write-Host "Changing password for User $($CloudAdminUserName) on Privileged Endpoint $($Region.PrivilegedEndpointIP)" -ForegroundColor Green
    Invoke-Command -Session $PEPSession -ScriptBlock {Set-CloudAdminUserPassword -UserName $Using:CloudAdminUserNameTemp -CurrentPassword $Using:CurrentCredentials.Password -NewPassword $Using:NewCredentials.Password}

    Write-Host "Removing PSSession from Privileged Endpoint $($PrivilegedEndpoint)" -ForegroundColor Green
    Remove-PSSession $PEPSession
}

