<#
.SYNOPSIS
    Script to get Azure Stack Startup Progess

.DESCRIPTION
    Use this to get Azure Stack Startup Progess from Privileged Endpoint.

.PARAMETER PrivilegedEndpoints
    Define list of Privileged Endpoints as an Array.
    Example: @('AZS-ERCS01')

.EXAMPLE
    .\Get-AzureStackStartupProgressASDK.ps1
#>
[CmdletBinding()]
Param
(
    # Define list of Privileged Endpoints as an Array.
    # Example: @("10.0.0.1","10.0.0.2","10.0.0.3")
    [parameter(Mandatory=$false,HelpMessage='Define list of Privileged Endpoints as an Array. Example: @("10.0.0.1","10.0.0.2","10.0.0.3")')]
    [Array]$PrivilegedEndpoints = @('AZS-ERCS01')
)


$CloudAdminCredentials = (Get-Credential -Message "Enter your Cloud Admin credentials.")

$Session = New-PSSession -ComputerName (Get-Random -InputObject $PrivilegedEndpoints) -ConfigurationName PrivilegedEndpoint -Credential $CloudAdminCredentials

[xml]$Status = (Invoke-Command $Session {Get-ActionStatus Start-AzureStack}).ProgressAsXml

$Status.Action.Steps.Step | Select-Object Name,Description,Status