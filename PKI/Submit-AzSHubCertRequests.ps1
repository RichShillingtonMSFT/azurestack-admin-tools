<#
.SYNOPSIS
    Script is to submit certificate requests to the a Microsoft Certificate Authority

.DESCRIPTION
    This script is to submit certificate requests to the a Microsoft Certificate Authority.
    This is intended to be run on an issuing CA.
    After the submissions .CER files will be stored in the CEROutputDirectory specified.

.PARAMETER CEROutputDirectory
    Provide the output directory for the CER Files.
    Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"

.EXAMPLE
    .\Submit-AzSHubCertRequests.ps1 -CEROutputDirectory "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"
#>
[CmdletBinding()]
Param
(
    # Provide the output directory for the CER Files.
    # Example: "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"
    [parameter(Mandatory=$false,HelpMessage='Provide the output directory for the CER Files.')]
    [String]$CEROutputDirectory
)

if (!($CEROutputDirectory))
{
    $CEROutputDirectory = "$ENV:USERPROFILE\Documents\AzureStackCSR\CER"
}

if (!(Test-Path $CEROutputDirectory))
{
    New-Item -ItemType Directory -Path $CEROutputDirectory -Force
}

$REQFiles = Get-ChildItem -Path $CERDirectory -Filter *.req

foreach ($REQFile in $REQFiles)
{
    $CerFileName = $REQFile.Name.Substring(0,$REQFile.Name.IndexOf('_Cert')) + '.cer'
    certreq -submit -attrib "CertificateTemplate:AzureStack" -config - $REQFile.FullName.ToString() $CEROutputDirectory\$CerFileName
}

$RSPFiles = Get-ChildItem -Path $CEROutputDirectory -Filter *.rsp
foreach ($RSPFile in $RSPFiles)
{
    Remove-Item $RSPFile.FullName -Force
}