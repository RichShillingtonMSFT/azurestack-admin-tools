<#
.SYNOPSIS
    Script to register Graph Directory

.DESCRIPTION
    Use this to register the Graph Directory for Azure Stack ADFS implementations

.PARAMETER CloudAdminUserName
    Provide the User Name of the Cloud Admin.
    Example: 'CloudAdmin@azurestack.local'

.PARAMETER ADForestFQDN
    Provide FQDN of the Active Directory Forest.
    Example: blabla.contoso.com

.PARAMETER PrivilegedEndpoints
    Define list of Privileged Endpoints as an Array.
    Example: @('10.0.0.1','10.0.0.2','10.0.0.3')

.EXAMPLE
    .\Register-GraphDirectory.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the User Name of the Cloud Admin.
    # Example: 'CloudAdmin@azurestack.local'
    [parameter(Mandatory=$false,HelpMessage='Provide the User Name of the Cloud Admin.')]
    [String]$CloudAdminUserName = 'CloudAdmin@azurestack.local',

    # Provide FQDN of the Active Directory Forest.
    # Example: blabla.contoso.com
    [parameter(Mandatory=$true,HelpMessage='Provide FQDN of the Active Directory Forest. Example: blabla.contoso.com')]
    [String]$ADForestFQDN,

    # Define list of Privileged Endpoints as an Array.
    # Example: @("10.0.0.1","10.0.0.2","10.0.0.3")
    [parameter(Mandatory=$false,HelpMessage='Define list of Privileged Endpoints as an Array. Example: @("10.0.0.1","10.0.0.2","10.0.0.3")')]
    [Array]$PrivilegedEndpoints = @("10.0.0.1","10.0.0.2","10.0.0.3")
)

$CloudAdminCredential = Get-Credential -Credential $CloudAdminUserName
$Session = New-PSSession -ComputerName (Get-Random -InputObject $PrivilegedEndpoints) -ConfigurationName PrivilegedEndpoint -Credential $CloudAdminCredential

Invoke-Command $Session {Register-DirectoryService -CustomADGlobalCatalog $Using:ADForestFQDN}
