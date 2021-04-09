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

#Requires -Version 5
#Requires -RunAsAdministrator
#Requires -Module PowerShellGet
#Requires -Module PackageManagement

$VerbosePreference = 'Continue'

if (($Version -lt '2002') -and ($AzModules -eq $true))
{
    Write-Warning "You must have version 2002 with the latest hotfix installed prior to using AzModules"
    break
}

if ($Version -lt '1910')
{
    # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
    Write-Host "YOU REALLY NEED TO UPDATE YOUR STACK!" -ForegroundColor Red
    Write-Host "Update your stack to a supported version and try again!" -ForegroundColor Red
    break
}

# Set TLS Protocol 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Register-PSRepository -Default -ErrorAction SilentlyContinue
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

$PowerShellGetAvailable = Find-Module -Name 'PowerShellGet'
$PowerShellGetInstalled = Get-Module -ListAvailable | Where-Object {$_.Name -eq 'PowerShellGet'}

if ($PowerShellGetInstalled.Count -gt 1)
{
    $PowerShellGetInstalled = $PowerShellGetInstalled | Sort-Object Version | Select-Object -Last 1
}

if ($PowerShellGetAvailable.Version -gt $PowerShellGetInstalled.Version)
{
    Install-Module $PowerShellGetAvailable.Name -RequiredVersion $PowerShellGetAvailable.Version -AllowClobber -Force

    if ($AzModules)
    {
        Start-Process PowerShell.exe -Verb RunAs -WindowStyle Maximized -ArgumentList "-command &", "$PSScriptRoot\Install-AzureStackToolsPowerShellModules.ps1" ,"-Version $Version", "-AzModule"
    }
    else
    {
        Start-Process PowerShell.exe -Verb RunAs -WindowStyle Maximized -ArgumentList "-command &", "$PSScriptRoot\Install-AzureStackToolsPowerShellModules.ps1", "-Version $Version"
    }
    
    Exit
}

elseif ($PowerShellGetAvailable.Version -eq $PowerShellGetInstalled.Version)
{
    Remove-Module -Name $PowerShellGetAvailable.Name -Force
    Import-Module -Name $PowerShellGetAvailable.Name -RequiredVersion $PowerShellGetAvailable.Version -Force

#region Find and Remove Azure Modules
    Write-Output "Checking for existing Azure Modules"
    try
    {
        $ModuleTest = Get-Module -ListAvailable -ErrorAction SilentlyContinue| Where-Object {($_.Name -like "Az.*") -or ($_.Name -like "Azure*") -or ($_.Name -like "Azs.*") -and ($_.Name -ne 'AzureStackInstallerCommon')}
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

            $AzureModules = Get-Module -ListAvailable -ErrorAction SilentlyContinue | Where-object {$_.Name -like "Azure*"}
            foreach ($AzureModule in $AzureModules)
            {
                Uninstall-Module -Name $AzureModule.Name -AllVersions -Verbose -Force -ErrorAction Stop
            }

            $AzSModules = Get-Module -ListAvailable -ErrorAction SilentlyContinue | Where-object {$_.Name -like "Azs.*"}
            foreach ($AzSModule in $AzSModules)
            {
                Uninstall-Module -Name $AzSModule.Name -AllVersions -Verbose -Force -ErrorAction Stop
            }

            $AzModules = Get-Module -ListAvailable -ErrorAction SilentlyContinue | Where-object {$_.Name -like "Az.*"}
            foreach ($AzModule in $AzModules)
            {
                Uninstall-Module -Name $AzModule.Name -AllVersions -Verbose -Force -ErrorAction Stop
            }
            
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

#region Find and Remove Azure Stack Tools
    $InstalledLocations = @()
    $ModulePaths = $env:PSModulePath.Split(';')

    foreach ($ModulePath in $ModulePaths)
    {
        $ModulePath.TrimEnd('\')
        $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master") -ErrorAction SilentlyContinue
        if ($TestResults)
        {
            $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-master")
        }
        $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az") -ErrorAction SilentlyContinue
        if ($TestResults)
        {
            $InstalledLocations += ($ModulePath.TrimEnd('\') + "\AzureStack-Tools-az")
        }
        $TestResults = Test-Path ($ModulePath.TrimEnd('\') + "\AzureStack") -ErrorAction SilentlyContinue
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


#region Install Require Azure Modules
    If (($Version -ge '2002') -and ($AzModules -eq $false))
    {
        # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
        Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
        Install-Module -Name AzureRM.BootStrapper -Force -Verbose

        # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
        Write-Host "Installing and importing the API Version Profile required by Azure Stack"
        Use-AzureRmProfile -Profile 2019-03-01-hybrid -Force -Verbose

        Write-Host "Installing AzureStack Module"
        Install-Module -Name AzureStack -RequiredVersion 1.8.2 -AllowClobber -SkipPublisherCheck -Force -WarningAction SilentlyContinue -Verbose

    }

    If (($Version -ge '2002') -and ($AzModules -eq $true))
    {
        # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
        Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
        Install-Module -Name Az.BootStrapper -AllowPrerelease -AllowClobber -Force -Verbose

        # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
        Write-Host "Installing and importing the API Version Profile required by Azure Stack"
        Use-AzProfile -Profile 2019-03-01-hybrid -Force -Verbose -ErrorAction SilentlyContinue

        Write-Host "Installing AzureStack Module"
        Install-Module -Name AzureStack -RequiredVersion '2.0.2-preview' -AllowPrerelease -AllowClobber -Force -WarningAction SilentlyContinue -Verbose
    }

    If ($Version -eq '1910')
    {
        # Install the AzureRM.BootStrapper module. Select Yes when prompted to install NuGet
        Write-Host "Installing the AzureRM.BootStrapper module. Select Yes if prompted to install NuGet"
        Install-Module -Name AzureRM.BootStrapper -AllowClobber -Force -Verbose

        # Install and import the API Version Profile required by Azure Stack into the current PowerShell session.
        Write-Host "Installing and importing the API Version Profile required by Azure Stack"
        Use-AzureRmProfile -Profile 2019-03-01-hybrid -Force -Verbose

        Write-Host "Installing AzureStack Module"
        Install-Module -Name AzureStack -RequiredVersion 1.8.0 -Force -WarningAction SilentlyContinue -Verbose
    }

#region Download, Install and Import AzureStack-Tools Module
    Write-Host "Installing Azure Stack Tools Master"
    if (($Version -ge '2002') -and ($AzModules -eq $true))
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
        invoke-webrequest https://github.com/Azure/AzureStack-Tools/archive/az.zip -OutFile $Env:Temp\az.zip -UseBasicParsing
        Expand-Archive $Env:Temp\az.zip -DestinationPath 'C:\Program Files\WindowsPowerShell\Modules' -Force
        Remove-Item "$Env:Temp\az.zip"
    }
    if ($AzModules -eq $false)
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest 'https://github.com/Azure/AzureStack-Tools/archive/master.zip' -OutFile $Env:Temp\master.zip -UseBasicParsing
        Expand-Archive $Env:Temp\master.zip -DestinationPath 'C:\Program Files\WindowsPowerShell\Modules' -Force
        Remove-Item "$Env:Temp\master.zip"
    }

#endregion
}
Write-Host "Setup Complete" -ForegroundColor Green