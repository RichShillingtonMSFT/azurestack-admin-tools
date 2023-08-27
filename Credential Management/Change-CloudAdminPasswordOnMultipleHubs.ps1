<#
.SYNOPSIS
    Script to change the Cloud Admin Password on multiple Azure Stack Hubs

.DESCRIPTION
    This script will allow you to change your Cloud Admin Password across multiple Azure Stack Hubs.
    It will create a PowerShell Remote Sessions to each Privileged Endpoint and set your password.
    IMPORTANT: Only provide one Privileged Endpoint per Azure Stack Hub.

.PARAMETER PrivilegedEndpoints
    Provide list of your Privileged Endpoints
    Example: 'xxx.xxx.xxx.xxx','xxx.xxx.xxx.xxx'

.PARAMETER CloudAdminDomain
    Provide your Cloud Admin Domain
    Example: 'AzureStack'

.PARAMETER CloudAdminUserName
    Provide your Cloud Admin User Name
    Example: 'Joe.Smith'

.PARAMETER CurrentCloudAdminPassword
    Provide your old Cloud Admin Password
    Example: Provide password as a SecureString

.PARAMETER NewCloudAdminPassword
    Provide your new Cloud Admin Password
    Example: Provide password as a SecureString

.EXAMPLE
    .\Change-CloudAdminPasswordOnMultipleHubs.ps1 -PrivilegedEndpoints 'xxx.xxx.xxx.xxx','xxx.xxx.xxx.xxx' `
        -CloudAdminDomain 'AzureStack' `
        -CloudAdminUserName 'Joe.Smith' `
        -CurrentCloudAdminPassword [SecureString] `
        -NewCloudAdminPassword [SecureString]
#>
[CmdletBinding()]
param
(
	# Provide list of your Privileged Endpoints
    # Add this back after WM01 is rebuilt'xxx.xxx.xxx.xxx'
	[Parameter(Mandatory=$false,HelpMessage="Provide list of your Privileged Endpoints")]
	[Array]$PrivilegedEndpoints = @('xxx.xxx.xxx.xxx','xxx.xxx.xxx.xxx','xxx.xxx.xxx.xxx'),

    # Provide your Cloud Admin Domain
	[Parameter(Mandatory=$true,HelpMessage="Provide your Cloud Admin Domain")]
	[String]$CloudAdminDomain,

    # Provide your Cloud Admin User Name
	[Parameter(Mandatory=$true,HelpMessage="Provide your Cloud Admin User Name")]
	[String]$CloudAdminUserName,

    # Provide your old Cloud Admin Password
	[Parameter(Mandatory=$true,HelpMessage="Provide your OLD Cloud Admin Password")]
	[SecureString]$CurrentCloudAdminPassword,

	# Provide your new Cloud Admin Password
	[Parameter(Mandatory=$true,HelpMessage="Provide your NEW Cloud Admin Password")]
	[SecureString]$NewCloudAdminPassword
)

[Array]$TrustedHosts = ((Get-Item WSMan:\localhost\Client\TrustedHosts).value).Split(',')

if (((Compare-Object -ReferenceObject $TrustedHosts -DifferenceObject $PrivilegedEndpoints).SideIndicator -contains '=>') -or ($TrustedHosts -ne "*"))
{
    Write-Host "One of your Privileged Endpoints in not defined in Trusted Hosts." -ForegroundColor Red
    Write-Host 'Run Set-Item WSMan:\localhost\Client\TrustedHosts -Value "[PrivilegedEndpointIP]" -Concatenate'
}

$PEPCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($CloudAdminDomain + '\' + $CloudAdminUserName), $CurrentCloudAdminPassword

foreach ($PrivilegedEndpoint in $PrivilegedEndpoints)
{
    Write-Host "Connnecting to Privileged Endpoint $($PrivilegedEndpoint)" -ForegroundColor Green
    $PEPSession = New-PSSession -ComputerName $PrivilegedEndpoint -ConfigurationName PrivilegedEndpoint -Credential $PEPCredentials -SessionOption (New-PSSessionOption -Culture en-US -UICulture en-US)

    Write-Host "Setting Password for $($CloudAdminUserName) on Privileged Endpoint $($PrivilegedEndpoint)" -ForegroundColor Green
    Invoke-Command -Session $PEPSession -ScriptBlock {Set-CloudAdminUserPassword -UserName $Using:CloudAdminUserName -CurrentPassword $Using:CurrentCloudAdminPassword -NewPassword $Using:NewCloudAdminPassword}

    Write-Host "Removing PSSession from Privileged Endpoint $($PrivilegedEndpoint)" -ForegroundColor Green
    Remove-PSSession $PEPSession
}