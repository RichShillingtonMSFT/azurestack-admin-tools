<#
    .SYNOPSIS
    Pulls Hard Drive information from the BMC of each Node in a given system and exports it to CSV

    .EXAMPLE
    Export-AzSHubDiskInfoToCSV.ps1 -NumberOfNodes '4' -FirstBMCNodeIP '10.0.1.2'

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

if (!($FileSaveLocation))
{
    $FileSaveLocation = "$env:USERPROFILE\Documents"
}

$credentials = Get-Credential -Message "Enter BMC Node Credentials"

Write-Verbose "Creating Data Table"
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("Host","string") | Out-Null
$DataTable.Columns.Add("Manufacturer","string") | Out-Null
$DataTable.Columns.Add("MediaType","string") | Out-Null
$DataTable.Columns.Add("Model","string") | Out-Null
$DataTable.Columns.Add("PartNumber","string") | Out-Null
$DataTable.Columns.Add("SerialNumber","string") | Out-Null
$DataTable.Columns.Add("Health","string") | Out-Null
$DataTable.Columns.Add("State","string") | Out-Null


$URL = 'https://' + $FirstBMCNodeIP
$FirstOctets = ($FirstBMCNodeIP.Split('.') | Select-Object -First 3) -join '.'
[Int]$LastOctet = $FirstBMCNodeIP.Split('.') | Select-Object -Last 1
Write-Host "First BMC Node URL is $URL"

[Int]$Count = '0'

do 
{
    Enable-SelfSignedCerts
    $HostIP = $URL.Replace('https://','')
    Write-Host "Checking $URL for Disks"
    $StorageURI = "$URL/redfish/v1/Systems/System.Embedded.1/Storage"

    $StorageInfo = Invoke-RestMethod -Uri $StorageURI -Credential $Credentials -Method Get -UseBasicParsing -Headers @{"Accept" = "application/json" }
    $StorageInfo.Members.'@odata.id'

    Write-host "Found $($StorageInfo.Members.'@odata.id'.Count) Storage Controllers"

    foreach ($Member in $($StorageInfo.Members.'@odata.id'))
    {
        Write-Host "Checking $($Member.Split('/') | Select-Object -Last 1) for physical drives"
        $URI = $URL + $Member
        $Results = Invoke-RestMethod -Uri $URI -Credential $Credentials -Method Get -UseBasicParsing -Headers @{"Accept" = "application/json" }
        if (!($Results.Drives))
        {
            Write-Host "$($Member.Split('/') | Select-Object -Last 1) has no physical drives" -ForegroundColor Yellow
            Continue
        }
        else
        {
            Write-Host "$($Member.Split('/') | Select-Object -Last 1) has $($Results.Drives.'@odata.id'.Count) physical drives" -ForegroundColor Green
            foreach ($Drive in $($Results.Drives.'@odata.id'))
            {
                Write-Host "Getting information about physical drives from $($Drive.Split('/') | Select-Object -Last 1)" -ForegroundColor Cyan
                $DiskURI = $URL + $Drive
                $DiskDetails = Invoke-RestMethod -Uri $DiskURI -Credential $Credentials -Method Get -UseBasicParsing -Headers @{"Accept" = "application/json" }
                    
                $NewRow = $DataTable.NewRow()

                $NewRow.Host = $($HostIP)
                $NewRow.Manufacturer = $($DiskDetails.Manufacturer)
                $NewRow.MediaType = $($DiskDetails.MediaType)
                $NewRow.Model = $($DiskDetails.Model)
                $NewRow.PartNumber = $($DiskDetails.PartNumber)
                $NewRow.SerialNumber = $($DiskDetails.SerialNumber)
                $NewRow.Health = $($DiskDetails.Status.Health)
                $NewRow.State = $($DiskDetails.Status.State)


                $DataTable.Rows.Add($NewRow)
            }
        }
    }

    $Count++
    $LastOctet++
    $URL = 'https://' + $FirstOctets + '.' + $LastOctet
}
while ($Count -le $numberOfNodes)

$CSVFileName = 'ASHDiskData-' + $(Get-Date -f yyyy-MM-dd) + '.csv'
$DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
Write-Host "CSV with Disk Data can be found here $FileSaveLocation\$CSVFileName"

