<#
    .SYNOPSIS
    Pulls Hard Drive information from the HPE BMC of each Node in a given system and exports it to CSV

    .EXAMPLE
    Export-HPEAzSHubDiskInfoToCSV.ps1 -NumberOfNodes '4' -FirstBMCNodeIP '10.0.1.2'

    .NOTES
    The script starts with the HLH and then proceeds through each of the nodes.
#>
[CmdletBinding()]
param(

    # Path to the switch config folder
    [Parameter(Mandatory = $true)]
    [ValidateRange(4, 16)]
    [int]$NumberOfNodes,

    [Parameter(Mandatory = $true)]
    [String]$FirstBMCNodeIP,
        
    [Parameter(Mandatory = $false)]
    [String]$FileSaveLocation

)

#region Functions & variables
function Enable-SelfSignedCerts {
param()

try {
    Write-Verbose -Message "Enable SelfSigned Certs"
    # Ignore certificate validation and use TLS 1.2
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
        $certCallback = 
        @"
        using System;
        using System.Net;
        using System.Net.Security;
        using System.Security.Cryptography.X509Certificates;
        public class ServerCertificateValidationCallback
        {
            public static void Ignore()
            {
                if(ServicePointManager.ServerCertificateValidationCallback == null)
                {
                    ServicePointManager.ServerCertificateValidationCallback +=
                        delegate
                        (
                            Object obj,
                            X509Certificate certificate,
                            X509Chain chain,
                            SslPolicyErrors errors
                        )
                        {
                            return true;
                        };
                }
            }
        }
"@
        Add-Type $certCallback
    }
    [ServerCertificateValidationCallback]::Ignore()
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} 
catch {
    Throw "Unable to Allow Self Signed Certificates`n`n$($_.Exception.Message)"
}

} 

function Connect-HPERedfish
{
    [cmdletbinding(DefaultParameterSetName='unpw')]
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
        $Address,

        [System.String]
        [parameter(ParameterSetName="unpw", Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)]
        $Username,
        
        [System.String]
        [parameter(ParameterSetName="unpw", Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=2)]
        $Password,

        [alias('Cred')] 
        [PSCredential]
        [parameter(ParameterSetName="Cred", Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)]
        $Credential,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableExpect100Continue

    )
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $session = $null
        $wr = $null
        $httpWebRequest = $null


        if($null -ne $Credential)
        {
            $un = $Credential.UserName
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
            $pw = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        elseif($username -ne '' -and $password -ne '')
        {
            $un = $username
            $pw = $password
        }
        else
        {
            throw $(Get-Message('MSG_INVALID_CREDENTIALS'))
        }
    
        $unpw = @{'UserName'=$un; 'Password'=$pw}
        $jsonStringData = $unpw|ConvertTo-Json
        $session = $null

        [IPAddress]$ipAddress = $null
        if([IPAddress]::TryParse($Address, [ref]$ipAddress))
        {
            if(([IPAddress]$Address).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and $Address.IndexOf('[') -eq -1)
            {
                $Address = '['+$Address+']'
            }
        }

        $baseUri = "https://$Address"
        $odataid = "/redfish/v1/"
        $uri = (New-Object System.Uri -ArgumentList @([URI]$baseUri, $Odataid)).ToString()
        $method = "GET"
        $cmdletName = "Connect-HPERedfish"

        $parameters = @{}
        $parameters.Add("Uri", $uri)
        $parameters.Add("Method", $method)
        $parameters.Add("CmdletName", $cmdletName)

        if($PSBoundParameters.ContainsKey("DisableExpect100Continue"))
        { $parameters.Add("DisableExpect100Continue", $DisableExpect100Continue) }

        if($PSBoundParameters.ContainsKey("DisableCertificateAuthentication"))
        { $parameters.Add("DisableCertificateAuthentication", $DisableCertificateAuthentication) }

        $webResponse = Invoke-HttpWebRequest @parameters

        $rs = $webResponse.GetResponseStream();
        [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
        $results = ''
        [string]$results = $sr.ReadToEnd();
		$sr.Close()
        $rs.Close()
		$webResponse.Close()
        $rootData = Convert-JsonToPSObject $results
        
        if($rootData.SessionService.'@odata.id' -eq $null)
        {
            throw $(Get-Message('MSG_UNABLE_TO_CONNECT'))
        }

        $odataid = $rootData.Links.Sessions.'@odata.id'
        $uri = (New-Object System.Uri -ArgumentList @([URI]$baseUri, $Odataid)).ToString()
        $method = "POST"
        $payload = $jsonStringData
        $cmdletName = "Connect-HPERedfish"
    
        $parameters = @{}
        $parameters.Add("Uri", $uri)
        $parameters.Add("Method", $method)
        $parameters.Add("CmdletName", $cmdletName)
        $parameters.Add("Payload", $payload)

        if($PSBoundParameters.ContainsKey("DisableExpect100Continue"))
        { $parameters.Add("DisableExpect100Continue", $DisableExpect100Continue) }

        if($PSBoundParameters.ContainsKey("DisableCertificateAuthentication"))
        { $parameters.Add("DisableCertificateAuthentication", $DisableCertificateAuthentication) }

        $webResponse = Invoke-HttpWebRequest @parameters

        $rootUri = $webResponse.ResponseUri.ToString()
        $split = $rootUri.Split('/')
        $rootUri = ''
        for($i=0;$i -le 4; $i++ ) # till v1/ is 4
        {
            $rootUri = $rootUri + $split[$i] + '/'
        }
        $session = New-Object PSObject   
        $session|Add-Member -MemberType NoteProperty 'RootUri' $rootUri
        $session|Add-Member -MemberType NoteProperty 'X-Auth-Token' $webResponse.Headers['X-Auth-Token']
        $session|Add-Member -MemberType NoteProperty 'Location' $webResponse.Headers['Location']
        $session|Add-Member -MemberType NoteProperty 'RootData' $rootData
        $session|Add-Member -MemberType NoteProperty 'DisableExpect100Continue' $DisableExpect100Continue
    
        $webResponse.Close()

        return $Session
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Invoke-HttpWebRequest
{
    param
    (
        [System.String]
        $Uri,

        [System.String]
        $Method,

        [System.Object]
        $Payload,

        [System.String]
        $CmdletName,

        [Switch]
        $DisableExpect100Continue,

        [PSObject]
        $Session
    )

    Start-Sleep -Milliseconds 300
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    if($null -ne $wr)
    {
        $wr = $null
    }
    if($null -ne $httpWebRequest)
    {
        $httpWebRequest = $null
    }
    $wr = [System.Net.WebRequest]::Create($Uri)
    $httpWebRequest = [System.Net.HttpWebRequest]$wr
    $httpWebRequest.Method = $Method
    $httpWebRequest.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip
    $httpWebRequest.Headers.Add('Odata-version','4.0')

    if($CmdletName -ne 'Connect-HPERedfish')
    {
        $httpWebRequest.Headers.Add('X-Auth-Token',$Session.'X-Auth-Token')
        $httpWebRequest.ServicePoint.Expect100Continue = -not($Session.DisableExpect100Continue)
    }
    else # if cmdlet is Connect-HPE
    {
        $httpWebRequest.ServicePoint.Expect100Continue = -not($DisableExpect100Continue)
    }

    if($script:CertificateAuthenticationFlag -eq $false)
    {
        $httpWebRequest.ServerCertificateValidationCallback = {$true}
    }
    
    if($method -in @('PUT','POST','PATCH'))
    {
        if($null -eq $Payload -or $Payload -eq '')
        {
            $Payload = '{}'
        }
        $httpWebRequest.ContentType = 'application/json'
        $httpWebRequest.ContentLength = $Payload.length

        $reqWriter = New-Object System.IO.StreamWriter($httpWebRequest.GetRequestStream(), [System.Text.Encoding]::ASCII)
        $reqWriter.Write($Payload)
        $reqWriter.Close()
    }
        
    try
    {
        [System.Net.WebResponse] $resp = $httpWebRequest.GetResponse()
        return $resp
    }
    catch
    {
        if($CmdletName -in @("Disconnect-HPERedfish","Connect-HPERedfish"))
        {
            $webResponse = $_.Exception.InnerException.Response
            $msg = $_
            if($null -ne $webResponse)
            {
                $webStream = $webResponse.GetResponseStream();
                $respReader = New-Object System.IO.StreamReader($webStream)
                [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $webStream;
                $resultJSON = $sr.ReadToEnd();
                $result = $resultJSON|ConvertFrom-Json
                $webResponse.close()
                $webStream.close()
                $sr.Close()
                $msg = $_.Exception.Message
                if($result.Messages.Count -gt 0)
                {
                    foreach($msgID in $result.Messages)
                    {
                        $msg = $msg + "`n" + $msgID.messageID
                    }
                }
            }
            $Global:Error.RemoveAt(0)
            throw $msg
        }

        else
        {
            $webResponse = $_.Exception.InnerException.Response
            if($null -ne $webResponse)
            {
                if($webResponse.StatusCode.ToString() -eq '308')
                {
                    $uri = $webResponse.Headers['Location']
                    $wr = [System.Net.WebRequest]::Create($uri)
                    $httpWebRequest = [System.Net.HttpWebRequest]$wr
                    $httpWebRequest.Method = $Method
                    $httpWebRequest.ContentType = 'application/json'
                    $httpWebRequest.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip
                    $httpWebRequest.Headers.Add('X-Auth-Token',$Session.'X-Auth-Token')
                    $httpWebRequest.Headers.Add('Odata-version','4.0')
                    if($script:CertificateAuthenticationFlag -eq $false)
                    {
                        $httpWebRequest.ServerCertificateValidationCallback = {$true}
                    }
                    Write-Verbose "Redirecting to $uri"
                    [System.Net.WebResponse] $resp = $httpWebRequest.GetResponse()
                    $Global:Error.RemoveAt(0)
                    return $resp
                }
                else
                {   
                    $webResponse = $_.Exception.InnerException.Response
                    if($null -ne $webResponse -and $webResponse.StatusCode.value__ -ne "401")
                    {
                        $errorRecord = Get-ErrorRecord -WebResponse $webResponse -CmdletName $CmdletName                        
                        $Global:Error.RemoveAt(0)
                        throw $errorRecord
                    }
                    else
                    {
                        throw $_
                    }
                }
            }
            else
            {
                throw $_
            }
        }
    }
    finally
    {
        if ($null -ne $reqWriter -and $reqWriter -is [System.IDisposable]){$reqWriter.Dispose()}
    }
}

function Convert-JsonToPSObject
{
    param
    (
        [System.String]
        [parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $JsonString
    )

    try
    {
        $convertedPsobject = ConvertFrom-Json -InputObject $JsonString
    }
    catch [System.InvalidOperationException]
    {
        if($_.FullyQualifiedErrorId -eq "DuplicateKeysInJsonString,Microsoft.PowerShell.Commands.ConvertFromJsonCommand")
        {
            $spl = $_.Exception.Message.Split("'")
            $propToRemove = $spl[1]
            #$Error.RemoveAt(0)
            $jsonStringRemProp = Remove-PropertyDuplicate -InputJSONString $JsonString -Property $propToRemove
            $convertedPsobject = Convert-JsonToPSObject -JsonString $jsonStringRemProp
        }
        else
        {
            throw $_
        }
    }
    return $convertedPsobject
    
}

if (!($FileSaveLocation))
{
    $FileSaveLocation = "$env:USERPROFILE\Documents"
}
#endregion

$Credentials = Get-Credential -Message "Enter BMC Node Credentials"

Write-Verbose "Creating Data Table"
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("Host","string") | Out-Null
$DataTable.Columns.Add("MediaType","string") | Out-Null
$DataTable.Columns.Add("Model","string") | Out-Null
$DataTable.Columns.Add("SerialNumber","string") | Out-Null
$DataTable.Columns.Add("Health","string") | Out-Null
$DataTable.Columns.Add("State","string") | Out-Null
$DataTable.Columns.Add("Id","string") | Out-Null
$DataTable.Columns.Add("CapacityGB","string") | Out-Null
$DataTable.Columns.Add("InterfaceSpeedMbps","string") | Out-Null
$DataTable.Columns.Add("InterfaceType","string") | Out-Null

$URL = 'https://' + $FirstBMCNodeIP
$FirstOctets = ($FirstBMCNodeIP.Split('.') | Select-Object -First 3) -join '.'
[Int]$LastOctet = $FirstBMCNodeIP.Split('.') | Select-Object -Last 1
Write-Host "First BMC Node URL is $URL"

[Int]$Count = '0'

do 
{
    Enable-SelfSignedCerts
    $HostIP = $URL.Replace('https://','')
    Write-Host "Connecting to $($URL)"
    $Connection = Connect-HPERedfish $HostIP -Credential $Credentials
    Write-Host "Checking $URL for Array Controllers"
    $StorageURI = "$URL/redfish/v1/Systems/1/SmartStorage/ArrayControllers"

    $Header = @{
        'X-Auth-Token' = $($Connection.'X-Auth-Token') 
        'Location' = $($Connection.Location)
    }
    
    $StorageControllersInfo = Invoke-RestMethod -Uri $StorageURI -Method Get -UseBasicParsing -Headers $Header

    Write-host "Found $($StorageControllersInfo.Members.'@odata.id'.Count) Storage Controllers"

    foreach ($Member in $($StorageControllersInfo.Members.'@odata.id'))
    {
        Write-Host "Checking $($Member.Split('/') | Select-Object -Last 1) for physical drives"
        $URI = $URL + $Member
        $Results = Invoke-RestMethod -Uri $URI -Method Get -UseBasicParsing -Headers $Header
        $Uri = $URL + $Results.Links.PhysicalDrives.'@odata.id'
        $Results = Invoke-RestMethod -Uri $URI -Method Get -UseBasicParsing -Headers $Header
        $Results.Members.'@odata.id'
        if (!($Results.Members.'@odata.id'))
        {
            Write-Host "Controller $($Member.Split('/') | Select-Object -Last 1) has no physical drives" -ForegroundColor Yellow
            Continue
        }
        else
        {
            Write-Host "Controller $($Member.Split('/') | Select-Object -Last 1) has $($Results.Members.'@odata.id'.Count) physical drives" -ForegroundColor Green
            foreach ($Drive in $($Results.Members.'@odata.id'))
            {
                Write-Host "Getting information about physical drive $($Drive.Split('/') | Select-Object -Last 1)" -ForegroundColor Cyan
                $DiskURI = $URL + $Drive
                $DiskDetails = Invoke-RestMethod -Uri $DiskURI -Method Get -UseBasicParsing -Headers $Header
                    
                $NewRow = $DataTable.NewRow()
                $NewRow.Host = $($HostIP)
                $NewRow.MediaType = $($DiskDetails.MediaType)
                $NewRow.Model = $($DiskDetails.Model)
                $NewRow.SerialNumber = $($DiskDetails.SerialNumber)
                $NewRow.Health = $($DiskDetails.Status.Health)
                $NewRow.State = $($DiskDetails.Status.State)
                $NewRow.Id = $($DiskDetails.Id)
                $NewRow.CapacityGB = $($DiskDetails.CapacityGB)
                $NewRow.InterfaceSpeedMbps = $($DiskDetails.InterfaceSpeedMbps)
                $NewRow.InterfaceType = $($DiskDetails.InterfaceType)
                $DataTable.Rows.Add($NewRow)
            }
        }
    }

    $Count++
    $LastOctet++
    $URL = 'https://' + $FirstOctets + '.' + $LastOctet
}
while ($Count -le $numberOfNodes)

$CSVFileName = 'HPEASHDiskData-' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
Write-Host "CSV with Disk Data can be found here $FileSaveLocation\$CSVFileName"
