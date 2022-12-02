<#
.SYNOPSIS
    Script to convert CER files to PFX files

.DESCRIPTION
    This script is used to convert CER files to PFX files.
    Requires Module Microsoft.AzureStack.ReadinessChecker
    After completion new .PFX files will be stored in the PFXExportPath specified.

.PARAMETER CERPath
    Provide the directory containing the CER Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStack\CER"

.PARAMETER PFXExportPath
    Provide the output directory for the PFX Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStack\PFX"

.EXAMPLE
    .\Prepare-AzSHubCertificates.ps1 -CERPath "$ENV:USERPROFILE\Documents\AzureStack\CER" `
        -PFXExportPath "$ENV:USERPROFILE\Documents\AzureStack\PFX"
#>
[CmdletBinding()]
Param
(
    # Provide the directory containing the CER Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStack\CER"
    [parameter(Mandatory=$true,HelpMessage='Provide the directory containing the CER Files.')]
    [String]$CERPath,

    # Provide the output directory for the PFX Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStack\PFX"
    [parameter(Mandatory=$false,HelpMessage='Provide the output directory for the PFX Files.')]
    [String]$PFXExportPath
)
#Requires -Module Microsoft.AzureStack.ReadinessChecker

Import-Module Microsoft.AzureStack.ReadinessChecker

if (!($PFXExportPath))
{
    $PFXExportPath = "$env:USERPROFILE\Documents\AzureStack\PFX"
}

$PFXPassword = Read-Host -AsSecureString -Prompt "PFX Password"

if (!(Test-Path $PFXExportPath))
{
    New-Item -ItemType Directory -Path $PFXExportPath -Force
}

ConvertTo-AzsPFX -Path $CERPath -pfxPassword $PFXPassword -ExportPath $PFXExportPath