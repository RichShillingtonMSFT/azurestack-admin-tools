<#
.SYNOPSIS
    Script to integrate Azure Stack Hub ADFS with your ADFS Server.

.DESCRIPTION
    This script will integrate Azure Stack Hub ADFS with your AD & ADFS Server.
    You need to provde the Service Admin Owner's UPN, Privileged Endpoint's IP Address, the Region Name and your ADFS Endpoints URL.
    The script will prompt you for the Graph Service Account & Cloud Admin Credentials.

.PARAMETER StackHubRegionName
    # Provide the Region Name of the Stack Hub. Example: HUB01.
    # Example: 'HUB01'

.PARAMETER ADDomainDNSName
    # Provide your Active Directory DNS Domain Name.
    # Example: 'Contoso.com'

.PARAMETER ADFSMetadataURL
    # Provide the ADFS Metadata URL for your Primary ADFS Server.
    # Example: 'sts.azurestack.Contoso.com'

.PARAMETER ServiceAdminOwnerUPN
    # Provide the Service Admin Owner UPN.
    # Example: 'ServiceAdmin@Contoso.com'

.PARAMETER PrivilegedEndpointIPAddress
    # Provide the IP Address of the Privileged Endpoint.
    # Example: IPs for the Privileged Endpoint can be found under Region Management > Properties in the Admin Portal or in the AzureStackStampInformation.json file.

.EXAMPLE
    .\Integrate-AzureStackHubADFSWithYourAD.ps1 -StackHubRegionName 'HUB01' `
        -ADDomainDNSName 'Contoso.com' `
        -ADFSMetadataURL 'sts.azurestack.Contoso.com' `
        -ServiceAdminOwnerUPN 'ServiceAdmin@Contoso.com' `
        -PrivilegedEndpointIPAddress '192.168.0.224'
#>
[CmdletBinding()]
Param
(
    # Provide the Region Name of the Stack Hub. Example: HUB01.
    # Example: 'HUB01'
    [parameter(Mandatory=$true,HelpMessage='Provide the Region Name of the Stack Hub. Example: HUB01')]
    [String]$StackHubRegionName,

    # Provide your Active Directory DNS Domain Name.
    # Example: 'Contoso.com'
    [parameter(Mandatory=$true,HelpMessage='Provide your Active Directory DNS Domain Name. Example: Contoso.com')]
    [String]$ADDomainDNSName,

    # Provide the ADFS Metadata URL for your Primary ADFS Server.
    # Example: 'sts.azurestack.Contoso.com'
    [parameter(Mandatory=$true,HelpMessage='Provide the ADFS Metadata URL for your Primary ADFS Server. Example: sts.azurestack.Contoso.com')]
    [String]$ADFSMetadataURL,

    # Provide the Service Admin Owner UPN.
    # Example: 'ServiceAdmin@Contoso.com'
    [parameter(Mandatory=$true,HelpMessage='Provide the Service Admin Owner UPN. Example: ServiceAdmin@Contoso.com')]
    [String]$ServiceAdminOwnerUPN,

    # Provide the IP Address of the Privileged Endpoint.
    # Example: IPs for the Privileged Endpoint can be found under Region Management > Properties in the Admin Portal or in the AzureStackStampInformation.json file.
    [parameter(Mandatory=$true,HelpMessage='Provide the IP Address of the Privileged Endpoint. Example: 192.168.0.224')]
    [String]$PrivilegedEndpointIPAddress
)

$GraphServiceCredential = Get-Credential -Message 'Please provide the Graph Service Account Credential Without the Domain Name'

$ADFSMetadataEndpoint = 'https://' + $ADFSMetadataURL + '/FederationMetadata/2007-06/FederationMetadata.xml'

$PEPCredentials = Get-Credential -Message 'Please provide CloudAdmin Credentials'

$PEPSession = New-PSSession -ComputerName $PrivilegedEndpointIPAddress -ConfigurationName PrivilegedEndpoint -Credential $PEPCredentials -SessionOption (New-PSSessionOption -Culture en-US -UICulture en-US)

$DirectoryServiceInformation = @(
    [PSCustomObject]@{
        CustomADGlobalCatalog = $ADDomainDNSName
        CustomADAdminCredential = $GraphServiceCredential
        SkipRootDomainValidation = $true
        ValidateParameters = $true
        Force = $true
    }
)

Invoke-Command -Session $PEPSession -ScriptBlock {Register-DirectoryService -CustomCatalog $Using:DirectoryServiceInformation}

Invoke-Command -Session $PEPSession -ScriptBlock {Register-CustomADFS -CustomAdfsName $Using:ADFSMetadataURL -CustomADFSFederationMetadataEndpointUri $Using:ADFSMetadataEndpoint}

Invoke-Command -Session $PEPSession -ScriptBlock {Set-ServiceAdminOwner -ServiceAdminOwnerUPN $Using:ServiceAdminOwnerUPN}
