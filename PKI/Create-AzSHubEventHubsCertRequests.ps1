<#
.SYNOPSIS
    Script to generate Azure Stack Hub Deployment Certificate Request Files

.DESCRIPTION
    This script is used to generate Azure Stack Hub Deployment Certificate Request Files
    Requires Module Microsoft.AzureStack.ReadinessChecker
    After completion new .REQ files will be stored in the REQOutputDirectory specified.

.PARAMETER REQOutputDirectory
    Provide the directory to store the req Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStack\REQ"

.PARAMETER IdentitySystem
    Provide the identity system used.
    Example: AAD or ADFS"

.PARAMETER RegionName
    Provide the region name for your Azure Stack Stamp.
    Example: local

.PARAMETER ExternalFQDN
    Provide the external FQDN for the Azure Stack Stamp.
    Example: azurestack.external

.PARAMETER Subject
    Declare the subject for your Azure Stack Stamp.
    Example: "C=US,ST=Washington,L=Redmond,O=Microsoft,OU=Azure Stack Hub"

.EXAMPLE
    .\Create-AzSHubDeploymentCertRequests.ps1 `
        -REQOutputDirectory "$ENV:USERPROFILE\Documents\AzureStack\REQ" `
        -IdentitySystem 'AAD' `
        -RegionName 'local' `
        -ExternalFQDN 'azurestack.external' `
        -Subject 'C=US,ST=Washington,L=Redmond,O=Microsoft,OU=Azure Stack Hub'
#>
[CmdletBinding()]
Param
(
    # Provide the directory to store the req Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStack\REQ"
    [parameter(Mandatory=$false,HelpMessage='Provide the directory to store the req Files. Example: "$ENV:USERPROFILE\Documents\AzureStack\REQ"')]
    [String]$REQOutputDirectory,

    # Provide the identity system used.
    # Example: AAD or ADFS
    [parameter(Mandatory=$true,HelpMessage='Provide the identity system used. Example: AAD or ADFS')]
    [ValidateSet('AAD','ADFS')]
    [String]$IdentitySystem,

    # Provide the region name for your Azure Stack Stamp.
    # Example: local
    [parameter(Mandatory=$true,HelpMessage='Provide the region name for your Azure Stack Stamp. Example: local')]
    [String]$RegionName,

    # Provide the external FQDN for the Azure Stack Stamp.
    # Example: azurestack.external
    [parameter(Mandatory=$true,HelpMessage='Provide the region name for your Azure Stack Stamp. Example: azurestack.external')]
    [String]$ExternalFQDN,

    # Declare the subject for your Azure Stack Stamp.
    # Example: "C=US,ST=Washington,L=Redmond,O=Microsoft,OU=Azure Stack Hub"
    [parameter(Mandatory=$true,HelpMessage='Declare the subject for your Azure Stack Stamp. Example: "C=US,ST=Washington,L=Redmond,O=Microsoft,OU=Azure Stack Hub"')]
    [String]$Subject


)
#Requires -Module Microsoft.AzureStack.ReadinessChecker

if (!($REQOutputDirectory))
{
    $REQOutputDirectory = "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"
}

if (!(Test-Path $REQOutputDirectory))
{
    New-Item -ItemType Directory -Path $REQOutputDirectory -Force
}

# Generate certificate requests for other Azure Stack Hub services, change the value for -CertificateType
# EventHubs
New-AzsHubEventHubsCertificateSigningRequest -RegionName $RegionName -FQDN $ExternalFQDN -subject $Subject -OutputRequestPath $REQOutputDirectory
