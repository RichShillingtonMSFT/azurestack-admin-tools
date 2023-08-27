<#
.SYNOPSIS
    Script to configure ADFS Relying Party Trust with Azure Stack Hub.

.DESCRIPTION
    This script should be run on the Primary ADFS Server.
    You must run this in an elevated PowerShell window.
    You must also be able to connect to the ADFS Metadata URL over HTTPS from the ADFS Server.

.PARAMETER StackHubRegionName
    Provide the Region Name of the Stack Hub.
    Example: HUB01

.PARAMETER StackHubExternalDomainName
    Provide the Stack Hub External Domain Name.
    Example: contoso.com

.EXAMPLE
    .\Configure-ADFSServerWithASHMetadataUrl.ps1 -StackHubRegionName 'HUB01' -StackHubExternalDomainName 'contoso.com'
#>
[CmdletBinding()]
Param
(
    # Provide the Region Name of the Stack Hub. Example: HUB01.
    # Example: 'HUB01'
    [parameter(Mandatory=$true,HelpMessage='Provide the Region Name of the Stack Hub. Example: HUB01')]
    [String]$StackHubRegionName,

    # Provide the Stack Hub External Domain Name.
    # Example: 'contoso.com'
    [parameter(Mandatory=$false,HelpMessage='Provide the Stack Hub External Domain Name. Example: contoso.com')]
    [String]$StackHubExternalDomainName = 'contoso.com'
)

$StackHubADFSMetadataEndpoint = 'https://adfs.' + $StackHubRegionName + '.' + $StackHubExternalDomainName + '/FederationMetadata/2007-06/FederationMetadata.xml'

$ClaimsRules = @'
@RuleTemplate = "LdapClaims"
@RuleName = "Name claim"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
=> issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"), query = ";userPrincipalName;{0}", param = c.Value);

@RuleTemplate = "LdapClaims"
@RuleName = "UPN claim"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
=> issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"), query = ";userPrincipalName;{0}", param = c.Value);

@RuleTemplate = "LdapClaims"
@RuleName = "ObjectID claim"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid"]
=> issue(Type = "http://schemas.microsoft.com/identity/claims/objectidentifier", Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType);

@RuleName = "Family Name and Given claim"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
=> issue(store = "Active Directory", types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"), query = ";sn,givenName;{0}", param = c.Value);

@RuleTemplate = "PassThroughClaims"
@RuleName = "Pass through all Group SID claims"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
=> issue(claim = c);

@RuleTemplate = "PassThroughClaims"
@RuleName = "Pass through all windows account name claims"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname"]
=> issue(claim = c);
'@

$ClaimsRulesFile = New-Item -Path $env:TEMP -ItemType File -Name 'ClaimsIssuanceRules.txt' -Force
Add-Content -Path $ClaimsRulesFile.FullName -Value $ClaimsRules | Set-Content

Add-ADFSRelyingPartyTrust -Name $StackHubRegionName -MetadataUrl $StackHubADFSMetadataEndpoint `
 -IssuanceTransformRulesFile $ClaimsRulesFile.FullName -AutoUpdateEnabled:$true `
 -MonitoringEnabled:$true -Enabled:$true `
 -AccessControlPolicyName 'Permit everyone' -TokenLifeTime 1440

Set-ADFSProperties -IgnoreTokenBinding $true