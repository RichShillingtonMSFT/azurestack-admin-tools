function Initialize-AzureRMAccount
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Profile.Models.PSAzureEnvironment] $AzureEnvironment = (Get-AzureRMEnvironment -Name 'AzS-Admin' -ErrorAction Stop),

        [Parameter()]
        [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior] $Prompt = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Never
    )

    $ErrorActionPreference='Stop'

    $ctx = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new(
    $AzureEnvironment.ActiveDirectoryAuthority,
    $false,
    [Microsoft.IdentityModel.Clients.ActiveDirectory.TokenCache]::new())

    function GetToken($resource)
    {
        $ErrorActionPreference='Stop'
        $cred = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential]::new()
        return $ctx.AcquireToken($resource, '1950a258-227b-4e31-a9cf-717495945fc2', 'urn:ietf:wg:oauth:2.0:oob', $Prompt)
    }

    $params = @{
        AccessToken = (GetToken $AzureEnvironment.ActiveDirectoryServiceEndpointResourceId).AccessToken
        GraphAccessToken = (GetToken $AzureEnvironment.GraphEndpointResourceId).AccessToken
        EnvironmentName = $AzureEnvironment.Name
        AccountId = $env:USERNAME
    }

    Add-AzureRMAccount @params -Force -Verbose
}

Initialize-AzureRMAccount -Prompt Auto