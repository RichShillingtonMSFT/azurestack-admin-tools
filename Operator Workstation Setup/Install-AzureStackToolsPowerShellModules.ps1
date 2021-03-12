<#
.SYNOPSIS
    Script to install Azure Stack Tools.

.DESCRIPTION
    This script is used to install the Azure Stack Tools PowerShell Module and the compatible Azure Module dependencies.
    All Azure and Azure Stack Modules will be removed.

.PARAMETER Version
    Provide the version of Azure Stack you are using.
    Example: '1910'

.EXAMPLE
    .\Install-AzureStackToolsPowerShellModules.ps1 -Version '1910'
    or
    .\Install-AzureStackToolsPowerShellModules.ps1 -Version '2002' -AzModules
#>
[CmdletBinding()]
Param
(
    # Provide the version of Azure Stack you are using.
    # Example: '1910'
    [parameter(Mandatory=$true,HelpMessage='Provide the version of Azure Stack you are using. Example: 1910')]
    [ValidatePattern('^\d{4}$')]
    [Int]$Version,

    # Switch to install Az Pre-release Modules
    [Switch]$AzModules
)

if (($Version -lt '2002') -and ($AzModules -eq $true))
{
    Write-Warning "You must have version 2002 with the latest hotfix installed prior to using AzModules"
    break
}

#Requires -Version 5
#Requires -RunAsAdministrator
#Requires -Module PowerShellGet
#Requires -Module PackageManagement

$VerbosePreference = 'Continue'

#region Find and Remove Azure Modules
Write-Output "Checking for existing Azure Modules"
try
{
    $ModuleTest = Get-Module -ListAvailable | Where-Object {($_.Name -like "Az.*") -or ($_.Name -like "Azure*") -or ($_.Name -like "Azs.*") -and ($_.Name -ne 'AzureStackInstallerCommon')}
    if ($ModuleTest)
    {
        Write-Warning "Found Azure Modules"
        Write-host "All Azure Modules will be removed! Do you want to continue? (Default is No)" -ForegroundColor Yellow 
        $Readhost = Read-Host " ( Y / N ) " 
        Switch ($ReadHost) 
        { 
            Y {Write-Warning "Uninstalling Azure Modules"} 
            N {Write-Host "No, Ending Install"; Exit} 
            Default {Write-Host "Default, Ending Install"; Exit} 
        }

        Get-Module -Name Azure* -ListAvailable | Uninstall-Module -Force -Verbose -ErrorAction Continue
        Get-Module -Name Azs.* -ListAvailable | Uninstall-Module -Force -Verbose -ErrorAction Continue
        Get-Module -Name Az.* -ListAvailable | Uninstall-Module -Force -Verbose -ErrorAction Continue

    }
    else
    {
        Write-Host "Azure Modules not found. Continuing" -ForegroundColor Green
    }
}
catch [exception]
{
    Write-Host $_.Exception -ForegroundColor Red
}
#endregion

Register-PSRepository -Default -ErrorAction SilentlyContinue
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

#region Find and Remove Azure Stack Tools
$InstalledLocations = @()
$ModulePaths = $env:PSModulePath.Split(';')

foreach ($ModulePath in $ModulePaths)
{
    $ModulePath.TrimEnd('\')
    $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master")
    if ($TestResults)
    {
        $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master")
    }
    $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az")
    if ($TestResults)
    {
        $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az")
    }
    $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack")
    if ($TestResults)
    {
        $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack")
    }
}

if ($InstalledLocations.Count -gt '0')
{
    Foreach ($InstalledLocation in $InstalledLocations)
    {
        Remove-Item $InstalledLocation -Recurse -Force -Verbose
    }
}
else
{
    Write-Host "Azure Stack Tools Modules not found. Continuing" -ForegroundColor Green
}
#endregion

# Set TLS Protocol 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Install Require Azure Modules
If (($Version -ge '2002') -and ($AzModules -eq $false))
{
    # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
    Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
    Install-Module -Name AzureRM.BootStrapper -Force -Verbose

    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "Installing and importing the API Version Profile required by Azure Stack"
    Use-AzureRmProfile -Profile 2019-03-01-hybrid -Force -Verbose

    $LoadedAzureModules = Get-Module | Where-Object {$_.Name -like "Azure*"}
    foreach ($LoadedAzureModule in $LoadedAzureModules)
    {
        Write-Host "Removing module $($LoadedAzureModule.Name) from memory"
        Remove-Module $LoadedAzureModule.Name -Force -Verbose
    }

    Write-Host "Installing AzureStack Module"
    Install-Module -Name AzureStack -RequiredVersion 1.8.2 -Force -WarningAction SilentlyContinue -Verbose

    Write-Host "Installing Azs.Syndication.Admin Module"
    Install-Module -Name Azs.Syndication.Admin -RequiredVersion 0.1.140
}

If (($Version -ge '2002') -and ($AzModules -eq $true))
{
    # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
    Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
    Install-Module -Name Az.BootStrapper -AllowPrerelease -Force -Verbose

    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "Installing and importing the API Version Profile required by Azure Stack"
    Use-AzProfile -Profile 2019-03-01-hybrid -Force -Verbose

    $LoadedAzureModules = Get-Module | Where-Object {$_.Name -like "Azure*"}
    foreach ($LoadedAzureModule in $LoadedAzureModules)
    {
        Write-Host "Removing module $($LoadedAzureModule.Name) from memory"
        Remove-Module $LoadedAzureModule.Name -Force -Verbose
    }

    Write-Host "Installing AzureStack Module"
    Install-Module -Name AzureStack -RequiredVersion '2.0.2-preview' -AllowPrerelease -Force -WarningAction SilentlyContinue -Verbose

    Write-Host "Installing Azs.Syndication.Admin Module"
    Install-Module -Name Azs.Syndication.Admin -RequiredVersion 0.1.140
}

If ($Version -eq '1910')
{
    # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
    Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
    Install-Module -Name AzureRM.BootStrapper -Force -Verbose

    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "Installing and importing the API Version Profile required by Azure Stack"
    Use-AzureRmProfile -Profile 2019-03-01-hybrid -Force -Verbose

    $LoadedAzureModules = Get-Module | Where-Object {$_.Name -like "Azure*"}
    foreach ($LoadedAzureModule in $LoadedAzureModules)
    {
        Write-Host "Removing module $($LoadedAzureModule.Name) from memory"
        Remove-Module $LoadedAzureModule.Name -Force -Verbose
    }

    Write-Host "Installing AzureStack Module"
    Install-Module -Name AzureStack -RequiredVersion 1.8.0 -Force -WarningAction SilentlyContinue -Verbose

    Write-Host "Installing Azs.Syndication.Admin Module"
    Install-Module -Name Azs.Syndication.Admin -RequiredVersion 0.1.140
}

if (($Version -gt '1903') -and ($Version -le '1908'))
{
    # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
    Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
    Install-Module -Name AzureRM.BootStrapper -Verbose

    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "Installing and importing the API Version Profile required by Azure Stack"
    Use-AzureRmProfile -Profile 2019-03-01-hybrid -Force -Verbose

    $LoadedAzureModules = Get-Module | Where-Object {$_.Name -like "Azure*"}
    foreach ($LoadedAzureModule in $LoadedAzureModules)
    {
        Write-Host "Removing module $($LoadedAzureModule.Name) from memory"
        Remove-Module $LoadedAzureModule.Name -Force -Verbose
    }

    Write-Host "Installing AzureStack Module"
    Install-Module -Name AzureStack -RequiredVersion 1.7.2 -Force -WarningAction SilentlyContinue -Verbose
}

if ($Version -lt '1903')
{
    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "Installing AzureRM Module"
    Install-Module -Name AzureRM -RequiredVersion 2.4.0 -Force -Verbose

    Write-Host "Installing AzureStack Module"
    Install-Module -Name AzureStack -RequiredVersion 1.7.1 -Force -WarningAction SilentlyContinue -Verbose
}

Write-Host "Installing Microsoft.AzureStack.ReadinessChecker Module"
Install-Module Microsoft.AzureStack.ReadinessChecker -Force -WarningAction SilentlyContinue -Verbose
#endregion

#region Download, Install and Import AzureStack-Tools Module
Write-Host "Installing Azure Stack Tools Master"
Set-Location 'C:\Program Files\WindowsPowerShell\Modules'
if (($Version -ge '2002') -and ($AzModules -eq $true))
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
    invoke-webrequest https://github.com/Azure/AzureStack-Tools/archive/az.zip -OutFile az.zip
    Expand-Archive 'az.zip' -DestinationPath 'C:\Program Files\WindowsPowerShell\Modules' -Force
    Remove-Item 'az.zip'
}
else 
{
    Invoke-WebRequest 'https://github.com/Azure/AzureStack-Tools/archive/master.zip' -OutFile 'master.zip' -UseBasicParsing
    Expand-Archive 'master.zip' -DestinationPath 'C:\Program Files\WindowsPowerShell\Modules' -Force
    Remove-Item 'master.zip'
}
#endregion

Write-Host "Setup Complete" -ForegroundColor Green