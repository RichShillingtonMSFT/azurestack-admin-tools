<#
.SYNOPSIS
    Script to install Azure Stack Tools Offline.

.DESCRIPTION
    This script is used to install the Azure Stack Tools PowerShell Module and the compatible Azure Module dependencies from an Offline Repo.
    All Azure and Azure Stack Modules will be removed.

.PARAMETER SourceLocation
    Provide the path to the downloaded module files.
    Example: 'C:\Downloads'

.PARAMETER RepoName
    Provide a name to use for the local repository location.
    Example: 'MyNuGetSource'

.EXAMPLE
    .\Install-OfflineAzureStackToolsPowerShellModules.ps1 -SourceLocation 'C:\Downloads' -RepoName 'MyNuGetSource'
#>
[CmdletBinding()]
Param
(
    # Provide the path to the downloaded module files.
    # Example: 'C:\Downloads'
    [parameter(Mandatory=$true,HelpMessage='Provide the path to the downloaded module files. Example: C:\Downloads')]
    [String]$SourceLocation,

    # Provide a name to use for the local repository location.
    # Example: 'MyNuGetSource'
    [parameter(Mandatory=$true,HelpMessage='Provide a name to use for the local repository location. Example: MyNuGetSource')]
    [String]$RepoName
)

#Requires -Version 5
#Requires -RunAsAdministrator
#Requires -Module PowerShellGet
#Requires -Module PackageManagement

$VerbosePreference = 'Continue'

Register-PSRepository -Name $RepoName -SourceLocation $SourceLocation -InstallationPolicy Trusted -Verbose

#region Find and Remove Azure Modules
Write-Output "Checking for existing Azure Modules"
try
{
    $ModuleTest = Get-Module -ListAvailable | Where-Object {($_.Name -like "Az.*") -or ($_.Name -like "Azure.*") -or ($_.Name -like "AzureRM.*") -or ($_.Name -like "Azs.*")}
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

        foreach ($Module in $ModuleTest)
        {
            Uninstall-Module -Name $Module.Name -Force -Verbose
        }
    }
}
catch [exception]
{
    Write-Host "Azure Modules not found. Continuing" -ForegroundColor Green
}
#endregion

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

#region Install Require Azure Modules
Write-Host "Installing the AzureRM module."
Install-Module -Name AzureRM -Repository $RepoName -Force -Verbose

Write-Host "Installing AzureStack Module"
Install-Module -Name AzureStack -Repository $RepoName -Force -Verbose

Write-Host "Installing Microsoft.AzureStack.ReadinessChecker Module"
Install-Module Microsoft.AzureStack.ReadinessChecker -Repository $RepoName -Force -Verbose
#endregion

#region Download, Install and Import AzureStack-Tools Module
Write-Host "Installing Azure Stack Tools Master"
Set-Location $SourceLocation
Expand-Archive 'master.zip' -DestinationPath 'C:\Program Files\WindowsPowerShell\Modules' -Force -Verbose
#endregion

Write-Host "Setup Complete" -ForegroundColor Green