<#
.SYNOPSIS
    Script to convert CER files to PFX files

.DESCRIPTION
    This script is used to convert CER files to PFX files.
    Requires Module Microsoft.AzureStack.ReadinessChecker
    After completion new .PFX files will be stored in the PFXExportPath specified.

.PARAMETER CERPath
    Provide the directory containing the CER Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"

.PARAMETER PFXExportPath
    Provide the output directory for the PFX Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\PFX"

.EXAMPLE
    .\Prepare-AzSHubCertificates.ps1 -CERPath "$ENV:USERPROFILE\Documents\AzureStackCSR\CER" `
        -PFXExportPath "$ENV:USERPROFILE\Documents\AzureStackCSR\PFX"
#>
[CmdletBinding()]
Param
(
    # Provide the directory containing the CER Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"
    [parameter(Mandatory=$true,HelpMessage='Provide the directory containing the CER Files.')]
    [String]$CERPath,

    # Provide the output directory for the PFX Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\PFX"
    [parameter(Mandatory=$false,HelpMessage='Provide the output directory for the PFX Files.')]
    [String]$PFXExportPath
)
#Requires -Module Microsoft.AzureStack.ReadinessChecker

Import-Module Microsoft.AzureStack.ReadinessChecker

if (!($PFXExportPath))
{
    $PFXExportPath = "$env:USERPROFILE\Documents\AzureStackPFX"
}

$PFXPassword = Read-Host -AsSecureString -Prompt "PFX Password"

if (!(Test-Path $PFXExportPath))
{
    New-Item -ItemType Directory -Path $PFXExportPath -Force
}

ConvertTo-AzsPFX -Path $CERPath -pfxPassword $PFXPassword -ExportPath $PFXExportPath