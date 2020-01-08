<#
.SYNOPSIS
    Script to add the Azure Stack User Environment for PowerShell

.DESCRIPTION
    This script will add the Azure Stack User Environment to PowerShell
    Be sure to use unique names if you plan on managing multiple stamps

.PARAMETER UserEnvironmentName
    Provide the Name to use for the Azure Stack User Environment.
    Example: AzureStackUser

.PARAMETER AzureStackDomainFQDN
    Provide the Azure Stack Domain FQDN
    Example: blabla.cloud.contoso.com

.EXAMPLE
    .\Add-AzureStackUserEnvironment.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the Name to use for the Azure Stack User Environment.
    # Example: AzureStackUser
    [parameter(Mandatory=$true,HelpMessage='Provide the Name to use for the Azure Stack User Environment. Example: AzureStackUser')]
    [String]$UserEnvironmentName,

    # Provide the Azure Stack Domain FQDN
    # Example: blabla.cloud.contoso.com
    [parameter(Mandatory=$true,HelpMessage='Provide the Azure Stack Domain FQDN. Example: blabla.cloud.contoso.com')]
    [String]$AzureStackDomainFQDN
)

Add-AzureRmEnvironment -Name $UserEnvironmentName -ARMEndpoint ('https://management.' + $AzureStackDomainFQDN)