<#
.SYNOPSIS
    Script to download Azure Stack Tools and Modules.

.DESCRIPTION
    This script is used to download Azure Stack Tools and the compatible Azure Module dependencies.

.PARAMETER Version
    Provide the version of Azure Stack you are using.
    Example: '1910'

.PARAMETER Path
    Provide the path to save the module files.
    Example: 'C:\Downloads'

.EXAMPLE
    .\Download-AzureStackToolsPowerShellModules.ps1 -Version '1910' -Path 'C:\Downloads'
#>
[CmdletBinding()]
Param
(
    # Provide the version of Azure Stack you are using.
    # Example: '1910'
    [parameter(Mandatory=$true,HelpMessage='Provide the version of Azure Stack you are using. Example: 1910')]
    [ValidatePattern('^\d{4}$')]
    [Int]$Version,

    # Provide the path to save the module files.
    # 'C:\Downloads'
    [parameter(Mandatory=$true,HelpMessage='Provide the path to save the module files. C:\Downloads')]
    [String]$Path
)

#Requires -Version 5
#Requires -Module PowerShellGet
#Requires -Module PackageManagement

$VerbosePreference = 'Continue'

$PathTest = Test-Path $Path
if (!$PathTest)
{
    New-Item -Path $Path -ItemType Directory
}

Import-Module -Name PowerShellGet -ErrorAction Stop
Import-Module -Name PackageManagement -ErrorAction Stop

#region Download Require Azure Modules
If ($Version -ge '2002')
{
    Write-Host "Downloading AzureRM Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureRM -Path $Path -Force -RequiredVersion 2.5.0

    Write-Host "Downloading AzureStack Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureStack -Path $Path -Force -RequiredVersion 1.8.1

    Write-Host "Downloading Azs.Syndication.Admin Module"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name  Azs.Syndication.Admin -Path $Path -Force -RequiredVersion 0.1.140
}

If ($Version -eq '1910')
{
    Write-Host "Downloading AzureRM Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureRM -Path $Path -Force -RequiredVersion 2.5.0

    Write-Host "Downloading AzureStack Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureStack -Path $Path -Force -RequiredVersion 1.8.0

    Write-Host "Downloading Azs.Syndication.Admin Module"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name  Azs.Syndication.Admin -Path $Path -Force -RequiredVersion 0.1.140
}

if (($Version -gt '1903') -and ($Version -le '1908'))
{
    Write-Host "Downloading AzureRM Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureRM -Path $Path -Force -RequiredVersion 2.5.0

    Write-Host "Downloading AzureStack Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureStack -Path $Path -Force -RequiredVersion 1.7.2

    Write-Host "Downloading Azs.Syndication.Admin Module"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name  Azs.Syndication.Admin -Path $Path -Force -RequiredVersion 0.1.140
}

if ($Version -lt '1903')
{
    Write-Host "Downloading AzureRM Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureRM -Path $Path -Force -RequiredVersion 2.4.0
    
    Write-Host "Downloading AzureStack Package"
    Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name AzureStack -Path $Path -Force -RequiredVersion 1.7.1
}

Write-Host "Downloading Microsoft.AzureStack.ReadinessChecker Package"
Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name Microsoft.AzureStack.ReadinessChecker -Path $Path -Force

Write-Host "Downloading PowerShellGet Package"
Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name PowerShellGet -Path $Path -Force

Write-Host "Downloading NuGet Package"
Save-Package -ProviderName NuGet -Source https://www.powershellgallery.com/api/v2 -Name NuGet -Path $Path -Force
#endregion

#region Download, Install and Import AzureStack-Tools Module
Write-Host "Installing Azure Stack Tools Master"
Set-Location $Path
Invoke-WebRequest 'https://github.com/Azure/AzureStack-Tools/archive/master.zip' -OutFile 'master.zip' -UseBasicParsing
#endregion

Write-Host "Download Complete" -ForegroundColor Green