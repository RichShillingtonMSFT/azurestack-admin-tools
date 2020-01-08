<#
.SYNOPSIS
    Script to add the Azure Stack Admin Environment for PowerShell

.DESCRIPTION
    This script will add the Azure Stack Admin Environment to PowerShell
    Be sure to use unique names if you plan on managing multiple stamps

.PARAMETER AdminEnvironmentName
    Provide the Name to use for the Azure Stack Admin Environment.
    Example: AzureStackAdmin

.PARAMETER AzureStackDomainFQDN
    Provide the Azure Stack Domain FQDN
    Example: blabla.cloud.contoso.com

.EXAMPLE
    .\Add-AzureStackAdminEnvironment.ps1
#>
[CmdletBinding()]
Param
(
    # Provide the Name to use for the Azure Stack Admin Environment.
    # Example: AzureStackAdmin
    [parameter(Mandatory=$true,HelpMessage='Provide the Name to use for the Azure Stack Admin Environment. Example: AzureStackAdmin')]
    [String]$AdminEnvironmentName,

    # Provide the Azure Stack Domain FQDN
    # Example: blabla.cloud.contoso.com
    [parameter(Mandatory=$true,HelpMessage='Provide the Azure Stack Domain FQDN. Example: blabla.cloud.contoso.com')]
    [String]$AzureStackDomainFQDN
)

Add-AzureRmEnvironment -Name $AdminEnvironmentName -ARMEndpoint ('https://adminmanagement.' + $AzureStackDomainFQDN) `
    -AzureKeyVaultDnsSuffix ('adminvault.' + $AzureStackDomainFQDN) `
    -AzureKeyVaultServiceEndpointResourceId ('https://adminvault.' + $AzureStackDomainFQDN)
