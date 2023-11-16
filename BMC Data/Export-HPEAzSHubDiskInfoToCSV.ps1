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

function Get-Message
{
    Param
    (
        [Parameter(Mandatory=$true)][String]$MsgID
    )
	$LocalizedStrings=@{
	'MSG_PROGRESS_ACTIVITY'='Receiving Results'
	'MSG_PROGRESS_STATUS'='Percent Complete'
	'MSG_SENDING_TO'='Sending to {0}'
	'MSG_FAIL_HOSTNAME'='DNS name translation not available for {0} - Host name left blank.'
	'MSG_FAIL_IPADDRESS'='Invalid Hostname: IP Address translation not available for hostname {0}.'
	'MSG_PARAMETER_INVALID_TYPE'="Error : `"{0}`" is not supported for parameter `"{1}`"."
	'MSG_INVALID_USE'='Error : Invalid use of cmdlet. Please check your input again'
	'MSG_INVALID_RANGE'='Error : The Range value is invalid'
	'MSG_INVALID_PARAMETER'="`"{0}`" is invalid, it will be ignored."
	'MSG_INVALID_TIMEOUT'='Error : The Timeout value is invalid'
	'MSG_FIND_LONGTIME'='It might take a while to search for all the HPE Redfish sources if the input is a very large range. Use Verbose for more information.'
	'MSG_USING_THREADS_FIND'='Using {0} threads for search.'
	'MSG_PING'='Pinging {0}'
	'MSG_PING_FAIL'='No system responds at {0}'
	'MSG_FIND_NO_SOURCE'='No HPE Redfish source at {0}'
	'MSG_INVALID_CREDENTIALS'='Invalid credentials'
    'MSG_SCHEMA_NOT_FOUND'='Schema not found for {0}'
	'MSG_INVALID_ODATA_ID'='The odata id is invalid'
	'MSG_FORMATDIR_LOCATION'='Location'
	'MSG_PARAMETER_MISSING'="Error : Invalid use of cmdlet. `"{0}`" parameter is missing"
    'MSG_NO_REDFISH_DATA'='{0} : HPE Redfish data not found'
    'MSG_UNABLE_TO_CONNECT'='Unable to create a connection to the target.'
    'MSG_REG_ODATAID_NOT_FOUND'='Registry OdataId not found for the message {0}'
	}

    $Message = ''
    try
    {
        $Message = $RM.GetString($MsgID)
        if($null -eq $Message)
        {
            $Message = $LocalizedStrings[$MsgID]
        }
    }
    catch
    {
        #throw $_
		$Message = $LocalizedStrings[$MsgID]
    }

    if($null -eq $Message)
    {
		#or unknown
        $Message = 'Fail to get the message'
    }
    return $Message
}

function Create-ThreadPool
{
    [Cmdletbinding()]
    Param
    (
        [Parameter(Position=0,Mandatory=$true)][int]$PoolSize,
        [Parameter(Position=1,Mandatory=$False)][Switch]$MTA
    )
    
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $PoolSize)	
    
    If(!$MTA) { $pool.ApartmentState = 'STA' }
    
    $pool.Open()
    
    return $pool
}

function Start-ThreadScriptBlock
{
    [Cmdletbinding()]
    Param
    (
        [Parameter(Position=0,Mandatory=$True)]$ThreadPool,
        [Parameter(Position=1,Mandatory=$True)][ScriptBlock]$ScriptBlock,
        [Parameter(Position=2,Mandatory=$False)][Object[]]$Parameters
    )
    
    $Pipeline = [System.Management.Automation.PowerShell]::Create() 

	$Pipeline.RunspacePool = $ThreadPool
	    
    $Pipeline.AddScript($ScriptBlock) | Out-Null
    
    Foreach($Arg in $Parameters)
    {
        $Pipeline.AddArgument($Arg) | Out-Null
    }
    
	$AsyncResult = $Pipeline.BeginInvoke() 
	
	$Output = New-Object AsyncPipeline 
	
	$Output.Pipeline = $Pipeline
	$Output.AsyncResult = $AsyncResult
	
	$Output
}

function Get-ThreadPipelines
{
    [Cmdletbinding()]
    Param
    (
        [Parameter(Position=0,Mandatory=$True)][AsyncPipeline[]]$Pipelines,
		[Parameter(Position=1,Mandatory=$false)][Switch]$ShowProgress
    )
	
	# incrementing for Write-Progress
    $i = 1 
	
    foreach($Pipeline in $Pipelines)
    {
		
		try
		{
        	$Pipeline.Pipeline.EndInvoke($Pipeline.AsyncResult)
			
			If($Pipeline.Pipeline.Streams.Error)
			{
				Throw $Pipeline.Pipeline.Streams.Error
			}
        } catch {
			$_
		}
        $Pipeline.Pipeline.Dispose()
		
		If($ShowProgress)
		{
            Write-Progress -Activity $(Get-Message('MSG_PROGRESS_ACTIVITY')) -PercentComplete $(($i/$Pipelines.Length) * 100) `
                -Status $(Get-Message('MSG_PROGRESS_STATUS'))
		}
		$i++
    }
}

function Get-IPArrayFromIPSection {
      param (
      [parameter(Mandatory=$true)][String] $stringIPSection,
      [parameter(Mandatory=$false)] [ValidateSet('IPv4','IPv6')] [String]$IPType = 'IPv4'
   )

    $returnarray=@()   
    try
    {
        $errMsg = "Failed to get $IPType array from IP section $stringIPSection"
        $by_commas = $stringIPSection.split(',')

        if($IPType -eq 'IPV4')
        {
        foreach($by_comma in $by_commas)
        {
            $by_comma_dashs = $by_comma.split('-')
            $by_comma_dash_ele=[int]($by_comma_dashs[0])
            $by_comma_dash_ele_end = [int]($by_comma_dashs[$by_comma_dashs.Length-1])
            if($by_comma_dash_ele -gt $by_comma_dash_ele_end)
            {
                $by_comma_dash_ele = $by_comma_dash_ele_end
                $by_comma_dash_ele_end = [int]($by_comma_dashs[0])                   
            }

            for(; $by_comma_dash_ele -le $by_comma_dash_ele_end;$by_comma_dash_ele++)
            {
                $returnarray+=[String]($by_comma_dash_ele)
                
            }
         }
        }

        if($IPType -eq 'IPv6')
        {
        foreach($by_comma in $by_commas)
        {
            $by_comma_dashs = $by_comma.split('-')
            $by_comma_dash_ele=[Convert]::ToInt32($by_comma_dashs[0], 16)
            $by_comma_dash_ele_end = ([Convert]::ToInt32($by_comma_dashs[$by_comma_dashs.Length-1], 16))
            if($by_comma_dash_ele -gt $by_comma_dash_ele_end)
            {
                $by_comma_dash_ele = $by_comma_dash_ele_end
                $by_comma_dash_ele_end = [Convert]::ToInt32($by_comma_dashs[0], 16)                   
            }

            for(; $by_comma_dash_ele -le $by_comma_dash_ele_end;$by_comma_dash_ele++)
            {
                $returnarray+=[Convert]::ToString($by_comma_dash_ele,16);
                
            }
         }
    }
   }
   catch
   {
         Write-Error "Error - $errmsg"
   }
   return ,$returnarray
   }

function Get-IPArrayFromString {
      param (
      [parameter(Mandatory=$true)][String] $stringIP,
      [parameter(Mandatory=$false)] [ValidateSet('IPv4','IPv6')] [String]$IPType = 'IPv4',
      [parameter(Mandatory=$false)] [String]$PreFix = '',
      [parameter(Mandatory=$false)] [String]$PostFix = ''
   )

    #$returnarray=@()
    try
    {
    $errMsg = "Invalid format of IP string $stringIP to get $IPType array"
    $IPSectionArray = New-Object System.Collections.ArrayList
    $returnarray = New-Object 'System.Collections.ObjectModel.Collection`1[System.String]'

    $IPdelimiter='.'
    if($IPType -eq 'IPv6')
    {
        $IPdelimiter=':'
    }
    
    $sections_bycolondot = $stringIP.Split($IPdelimiter)
    for($x=0; ($x -lt $sections_bycolondot.Length -and ($null -ne $sections_bycolondot[$x] -and $sections_bycolondot[$x] -ne '')) ; $x++)
    {
        $section=@()		
        $section= Get-IPArrayFromIPSection -stringIPSection $sections_bycolondot[$x] -IPType $IPType
        $x=$IPSectionArray.Add($section)        
    }
    
    if($IPSectionArray.Count -eq 1)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$PostFix)
        }
    }
    if($IPSectionArray.Count -eq 2)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$PostFix)
            }
        }
    }
    if($IPSectionArray.Count -eq 3)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$PostFix)
                }
            }
        }
    }
    if($IPSectionArray.Count -eq 4)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {  
                        $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$PostFix)
                    }
                }
            }
        }
    }

    if($IPSectionArray.Count -eq 5)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {
                        for($b=0; $b -lt $IPSectionArray[4].Count; $b++)
                        {
                            $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$IPdelimiter+$IPSectionArray[4][$b]+$PostFix)
                        }
                    }
                }
            }
        }
    }

    if($IPSectionArray.Count -eq 6)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {
                        for($b=0; $b -lt $IPSectionArray[4].Count; $b++)
                        {
                            for($c=0; $c -lt $IPSectionArray[5].Count; $c++)
                            {
                                $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$IPdelimiter+$IPSectionArray[4][$b]+$IPdelimiter+$IPSectionArray[5][$c]+$PostFix)
                            }
                        }
                    }
                }
            }
        }
    }
    if($IPSectionArray.Count -eq 7)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {
                        for($b=0; $b -lt $IPSectionArray[4].Count; $b++)
                        {
                            for($c=0; $c -lt $IPSectionArray[5].Count; $c++)
                            {
                                for($d=0; $d -lt $IPSectionArray[6].Count; $c++)
                                {
                                    $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$IPdelimiter+$IPSectionArray[4][$b]+$IPdelimiter+$IPSectionArray[5][$c]+$IPdelimiter+$IPSectionArray[6][$d]+$PostFix)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if($IPSectionArray.Count -eq 8)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {
                        for($b=0; $b -lt $IPSectionArray[4].Count; $b++)
                        {
                            for($c=0; $c -lt $IPSectionArray[5].Count; $c++)
                            {
                                for($d=0; $d -lt $IPSectionArray[6].Count; $d++)
                                {
                                    for($e=0; $e -lt $IPSectionArray[7].Count; $e++)
                                    {
                                        $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$IPdelimiter+$IPSectionArray[4][$b]+$IPdelimiter+$IPSectionArray[5][$c]+$IPdelimiter+$IPSectionArray[6][$d]+$IPdelimiter+$IPSectionArray[7][$e]+$PostFix)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if($IPSectionArray.Count -eq 9)
    {
        for($x=0; $x -lt $IPSectionArray[0].Count; $x++)
        {
            for($y=0; $y -lt $IPSectionArray[1].Count; $y++)
            {
                for($z=0; $z -lt $IPSectionArray[2].Count; $z++)
                {
                    for($a=0; $a -lt $IPSectionArray[3].Count; $a++)
                    {
                        for($b=0; $b -lt $IPSectionArray[4].Count; $b++)
                        {
                            for($c=0; $c -lt $IPSectionArray[5].Count; $c++)
                            {
                                for($d=0; $d -lt $IPSectionArray[6].Count; $c++)
                                {
                                    for($e=0; $e -lt $IPSectionArray[7].Count; $e++)
                                    {
                                        for($f=0; $f -lt $IPSectionArray[8].Count; $f++)
                                        {
                                            $returnarray.Add($PreFix+$IPSectionArray[0][$x]+$IPdelimiter+$IPSectionArray[1][$y]+$IPdelimiter+$IPSectionArray[2][$z]+$IPdelimiter+$IPSectionArray[3][$a]+$IPdelimiter+$IPSectionArray[4][$b]+$IPdelimiter+$IPSectionArray[5][$c]+$IPdelimiter+$IPSectionArray[6][$d]+$IPdelimiter+$IPSectionArray[7][$e]+$IPdelimiter+$IPSectionArray[8][$f]+$PostFix)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
    catch
    {
         Write-Error "Error - $errmsg"
    }

   return ,$returnarray
   }

function Get-IPv6FromString {
      param (
      [parameter(Mandatory=$true)][String] $stringIP,
	  [parameter(Mandatory=$false)] [switch] $AddSquare
	  
   )
            $percentpart=''
            $ipv4array=@()
            #$ipv6array=@()
            #$returnstring=@()
            $returnstring = New-Object 'System.Collections.ObjectModel.Collection`1[System.String]'
            $ipv6array = New-Object 'System.Collections.ObjectModel.Collection`1[System.String]'
			$preFix=''
			$postFix=''
			if($AddSquare)
			{
				$preFix='['
				$postFix=']'
			}
            try
            {
            $errMsg = "Invalid format of IP string $stringIP to get IPv6 address"
            #it could have ::, :,., % inside it, have % in it            
            if($stringIP.LastIndexOf('%') -ne -1)  
            {
                $sections = $stringIP.Split('%')
                $percentpart='%'+$sections[1]
                $stringIP=$sections[0]                
            }

            #it could have ::, :,.inside it, have ipv4 in it
            if($stringIP.IndexOf('.') -ne -1) 
            {
                [int]$nseperate = $stringIP.LastIndexOf(':')
				#to get the ipv4 part
                $mappedIpv4 = $stringIP.SubString($nseperate + 1) 
				$ipv4array=Get-IPArrayFromString -stringIP $mappedIpv4 -IPType 'IPV4' 

                #to get the first 6 sections, including :: or :
				$stringIP = $stringIP.Substring(0, $nseperate + 1) 
            }

				#it could have ::,: inside it             
                $stringIP = $stringIP -replace '::', '|' 
                $sectionsby_2colon=@()
				#suppose to get a 2 element array
                $sectionsby_2colon = $stringIP.Split('|') 
				#no :: in it
                if($sectionsby_2colon.Length -eq 1) 
                {
                    $ipv6array=Get-IPArrayFromString -stringIP $sectionsby_2colon[0] -IPType 'IPv6' 
                }
                elseif($sectionsby_2colon.Length -gt 1)
                {
					#starting with ::
                    if(($sectionsby_2colon[0] -eq '')) 
                    {
                        if(($sectionsby_2colon[1] -eq ''))
                        {
                            $ipv6array=@('::')
                        }
                        else
                        {
                            $ipv6array=Get-IPArrayFromString -stringIP $sectionsby_2colon[1] -IPType 'IPv6' -PreFix '::'
                        }
                    }
					#not starting with ::, may in the middle or in the ending
                    else 
                    {
                        if(($sectionsby_2colon[1] -eq ''))
                        {
                            $ipv6array=Get-IPArrayFromString -stringIP $sectionsby_2colon[0] -IPType 'IPv6' -PostFix '::'
                        }
                        else
                        {
                            $ipv6array1=Get-IPArrayFromString -stringIP $sectionsby_2colon[0] -IPType 'IPv6'  -PostFix '::'                            
                            $ipv6array2=Get-IPArrayFromString -stringIP $sectionsby_2colon[1] -IPType 'IPv6' 
                            foreach($x1 in $ipv6array1)
                            {
                                foreach($x2 in $ipv6array2)
                                {
                                    $ipv6array.Add($x1 + $x2)
                                }
                            }
                        }                        
                    }
                }        

        foreach($ip1 in $ipv6array)
        {
            if($ipv4array.Count -ge 1)
            {
                foreach($ip2 in $ipv4array)
                {
                    if($ip1.SubString($ip1.Length-1) -eq ':')
                    {
                        $returnstring.Add($preFix+$ip1+$ip2+$percentpart+$postFix)
                    }
                    else
                    {
                        $returnstring.Add($preFix+$ip1+':'+$ip2+$percentpart+$postFix)
                    }
                }
            }
            else
            {
                $returnstring.Add($preFix+$ip1+$percentpart+$postFix)
            }            
        }
        }
        catch
        {
            Write-Error "Error - $errmsg"
        }
    return $returnstring    
}

function Complete-IPv4{
    param (
        [parameter(Mandatory=$true)] [String] $strIP
        #[parameter(Mandatory=$true)] [ref] $arrayforip
    )
    $arrayfor = @()
    $arrayfor += '0-255'
    $arrayfor += '0-255'
    $arrayfor += '0-255'
    $arrayfor += '0-255'

             #with the new format, 1..., or .1, at most 5 items in $sections, but might have empty values  
             $sections = $strIP.Split('.')
			 
			 #no "." in it
             if($sections.length -eq 1)
             {              
                $arrayfor[0]=$sections[0]					
			 }
			#might have empty item when input is "x." or ".x"
			elseif($sections.length -eq 2)
			{
                if($sections[0] -ne '')
                {
                    $arrayfor[0]=$sections[0]
                    if($sections[1] -ne '')
                    {
                        $arrayfor[1]=$sections[1]   
                    }
                }
                else
                {
                    if($sections[1] -ne '')
                    {
                        $arrayfor[3]=$sections[1]
                    }
                }				
			}
            elseif($sections.length -eq 3) 
			{
				#"1..", "1.1.","1.1.1" "1..1"
                if($sections[0] -ne '')
                {
                    $arrayfor[0]=$sections[0]
                    if($sections[1] -ne '')
                    {
                        $arrayfor[1]=$sections[1]
                        if($sections[2] -ne '')
                        {
                            $arrayfor[2]=$sections[2]
                        }
                    }
                    else
                    {
                        if($sections[2] -ne '')
                        {
                            $arrayfor[3]=$sections[2]
                        }
                    }

                }                                
                else
                { 
					#.1.1
                    if($sections[2] -ne '') 
                    {
                        $arrayfor[3]=$sections[2]
                        if($sections[1] -ne '')
                        {
                            $arrayfor[2]=$sections[1]
                        }                                      
                    }
                    else
                    {
						#the 1 and 3 items are empty ".1."
                        if($sections[1] -ne '')
                        {
                            $arrayfor[1]=$sections[1]
                        }
                    }
                }							
			}
			#1.1.1., 1..., ...1, 1...1, .x.x.x, x..x.x, x.x..x,..x. 
            elseif($sections.length -eq 4)
			{
				#1st is not empty
                if($sections[0] -ne '')
                {
                    $arrayfor[0]=$sections[0]
					#2nd is not empty
                    if($sections[1] -ne '')
                    {
                        $arrayfor[1]=$sections[1]
						#3rd is not empty
                        if($sections[2] -ne '')
                        {
                            $arrayfor[2]=$sections[2]
							#4th is not empty
                            if($sections[3] -ne '')
                            {
                                $arrayfor[3]=$sections[3]
                            }
                        }
						#3rd is empty 1.1..1
                        else 
                        {
							#4th is not empty
                            if($sections[3] -ne '')
                            {
                                $arrayfor[3]=$sections[3]
                            }                            
                        }

                    }
					#2nd is empty, 1..1., 1...
                    else 
                    {
						#4th is not empty
                        if($sections[3] -ne '')
                        {
                            $arrayfor[3]=$sections[3]
							#3rd is not empty
                            if($sections[2] -ne '')
                            {
                                $arrayfor[2]=$sections[2]
                            }  
                        }  
						#4th is empty
                        else 
                        {
							#3rd is not empty
                            if($sections[2] -ne '')
                            {
                                $arrayfor[2]=$sections[2]
                            } 
                        }                        
                    }
                }
				#1st is empty
                else 
                {
					#4th is not empty
                    if($sections[3] -ne '')
                    {
                        $arrayfor[3]=$sections[3]
						#3rd is not empty
                        if($sections[2] -ne '')
                        {
                            $arrayfor[2]=$sections[2]
							#2rd is not empty
                            if($sections[1] -ne '')
                            {
                                $arrayfor[1]=$sections[1]
                            }                            
                        }
                        else
                        {
							#2rd is not empty
                            if($sections[1] -ne '')
                            {
                                $arrayfor[1]=$sections[1]
                            }  
                        }
                    }
					#4th is empty .1.1., ..1., .1..
                    else 
                    {
						#3rd is not empty
                        if($sections[2] -ne '')
                        {
                            $arrayfor[2]=$sections[2]                                                      
                        }
						
						#2nd is not empty
                        if($sections[1] -ne '')
                        {
                            $arrayfor[1]=$sections[1]                                                      
                        }
                    }                    
                }			
			}
			#x.x.x.., ..x.x.x, x.x.x.x
            elseif($sections.length -eq 5) 
			{
				#1st is not empty
				if($sections[0] -ne '')
                {
                    $arrayfor[0]=$sections[0]
                    if($sections[1] -ne '') 
                    {
                        $arrayfor[1]=$sections[1]
                    }
                    if($sections[2] -ne '') 
                    {
                        $arrayfor[2]=$sections[2]
                    }
                    if($sections[3] -ne '') 
                    {
                        $arrayfor[3]=$sections[3]
                    }
                                                    
                }
				#1st is empty
                else 
                {                    
                    if($sections[4] -ne '')
                    {
                        $arrayfor[3]=$sections[4]
                    }
                    if($sections[3] -ne '') 
                    {
                        $arrayfor[2]=$sections[3]
                    }
                    if($sections[2] -ne'')
                    {
                        $arrayfor[1]=$sections[2]
                    }
                    if($sections[1] -ne '') 
                    {
                        $arrayfor[0]=$sections[1]
                    }
                }		
			}

            #$arrayforip.Value = $arrayfor;
            return $arrayfor[0]+'.'+$arrayfor[1]+'.'+$arrayfor[2]+'.'+$arrayfor[3]
}

function Get-IPv4-Dot-Num{
    param (
        [parameter(Mandatory=$true)] [String] $strIP
    )
    [int]$dotnum = 0
    for($i=0;$i -lt $strIP.Length; $i++)
    {
        if($strIP[$i] -eq '.')
        {
            $dotnum++
        }
    }
    
    return $dotnum
}

function Complete-IPv6{
    param (
        [parameter(Mandatory=$true)] [String] $strIP,
        #[parameter(Mandatory=$true)] [ref] $arrayforip,
        [parameter(Mandatory=$false)] [Int] $MaxSecNum=8
    )
            $arrayfor = @()
            $arrayfor+=@('0-FFFF')
            $arrayfor+=@('0-FFFF')
            $arrayfor+=@('0-FFFF')
            $arrayfor+=@('0-FFFF')
            $arrayfor+=@('0-FFFF')
            $arrayfor+=@('0-FFFF')
			
			#used for ipv4-mapped,also used for ipv6 if not in ipv4 mapped format
            $arrayfor+=@('0-FFFF') 
			
			#used for ipv4-mapped,also used for ipv6 if not in ipv4 mapped format
            $arrayfor+=@('0-FFFF') 
			
			#used for ipv4-mapped
            $arrayfor+=@('') 
			
			#used for ipv4-mapped
            $arrayfor+=@('')  
			
			#used for %
            $arrayfor+=@('') 
			
            #$strIP = $strIP -replace "::", "|" 
            $returnstring=''
			
			#have % in it 
            if($strIP.LastIndexOf('%') -ne -1)  
            {
                $sections = $strIP.Split('%')
                $arrayfor[10]='%'+$sections[1]
                $strIP=$sections[0]                
            }
            #it could have ::, :, %, . inside it, have ipv4 in it
            if($strIP.IndexOf('.') -ne -1) 
            {
            
                [int]$nseperate = $strIP.LastIndexOf(':')	
				#to get the ipv4 part				
                $mappedIpv4 = $strIP.SubString($nseperate + 1) 
				$ipv4part = Complete-IPv4 -strIP $mappedIpv4                				
				
				#to get the first 6 sections
                $strIP = $strIP.Substring(0, $nseperate + 1)  
                $ipv6part = Complete-IPv6 -strIP $strIP -MaxSecNum 6 
                $returnstring += $ipv6part+':'+$ipv4part
            }
			#no ipv4 part in it, to get the 8 sections
            else 
            {
                $strIP = $strIP -replace '::', '|' 
                $parsedipv6sections=@()
				#suppose to get a 2 element array
                $bigsections = $strIP.Split('|') 
				#no :: in it
                if($bigsections.Length -eq 1) 
                {
                    $parsedipv6sections = $bigsections[0].Split(':')
                    for($x=0; ($x -lt $parsedipv6sections.Length) -and ($x -lt $MaxSecNum); $x++)
                    {
                        $arrayfor[$x] = $parsedipv6sections[$x]
                    }
                }
                elseif($bigsections.Length -gt 1)
                {
					#starting with ::
                    if(($bigsections[0] -eq '')) 
                    {
                        $parsedipv6sections = $bigsections[1].Split(':')
                        $Y=$MaxSecNum-1
                        for($x=$parsedipv6sections.Length; ($parsedipv6sections[$x-1] -ne '') -and ($x -gt 0) -and ($y -gt -1); $x--, $y--)
                        {
                            $arrayfor[$y] = $parsedipv6sections[$x-1]
                        }
                        for(; $y -gt -1; $y--)
                        {
                            $arrayfor[$y]='0'
                        }
                        
                    }
					#not starting with ::, may in the middle or in the ending
                    else 
                    {
                        $parsedipv6sections = $bigsections[0].Split(':')
                        $x=0
                        for(; ($x -lt $parsedipv6sections.Length) -and ($x -lt $MaxSecNum); $x++)
                        {
                            $arrayfor[$x] = $parsedipv6sections[$x]
                        }
                        
                        $y=$MaxSecNum-1
                        if($bigsections[1] -ne '')
                        {
                            $parsedipv6sections2 = $bigsections[1].Split(':')                            
                            for($z=$parsedipv6sections2.Length;  ($parsedipv6sections2[$z-1] -ne '')-and ($z -gt 0) -and ($y -gt ($x-1)); $y--,$z--)
                            {
                                $arrayfor[$y] = $parsedipv6sections2[$z-1]
                            }
                        }
                        for(;$x -lt ($y+1); $x++)
                        {
                              $arrayfor[$x]='0' 
                        }
                    }
                }
            if($MaxSecNum -eq 6)
            {
                $returnstring = $returnstring = $arrayfor[0]+':'+$arrayfor[1]+':'+$arrayfor[2]+':'+$arrayfor[3]+':'+$arrayfor[4]+':'+$arrayfor[5]
            }
            if($MaxSecNum -eq 8)
            {
                $appendingstring=''
                if($arrayfor[8] -ne '')
                {
                    $appendingstring=':'+$arrayfor[8]
                }
                if($arrayfor[9] -ne '')
                {
                    if($appendingstring -ne '')
                    {
                        $appendingstring = $appendingstring + ':'+$arrayfor[9]
                    }
                    else
                    {
                        $appendingstring=':'+$arrayfor[9]
                    }
                }
                if($arrayfor[10] -ne '')
                {
                    if($appendingstring -ne '')
                    {
                        $appendingstring = $appendingstring + $arrayfor[10]
                    }
                    else
                    {
                        $appendingstring=$arrayfor[10]
                    }
                }
                
                $returnstring = $arrayfor[0]+':'+$arrayfor[1]+':'+$arrayfor[2]+':'+$arrayfor[3]+':'+$arrayfor[4]+':'+$arrayfor[5]+':'+$arrayfor[6]+':'+$arrayfor[7]+$appendingstring
            }
            }
    #$arrayforip.Value= $arrayfor
    return $returnstring
}

function Get-HPERedfishDataPropRecurse
{
    param
    (
        [PSObject]
        $Data,

        [PSObject]
        $Schema,

        [PSObject]
        $Session,

        [String]
        $DataType,

        [String]
        $Language = 'en',

        [System.Collections.Hashtable]
        $DictionaryOfSchemas
    )
    $DataProperties = New-Object PSObject

    $PROP = 'Value'
    $PROP1 = 'Schema_Description'
    $SCHEMAPROP1 = 'Description'  #'description' prop name in schema
    $PROP2 = 'Schema_AllowedValue'
    #$SCHEMAPROP2 = 'enum'         #'enum' prop name in schema
    $PROP3 = 'Schema_Type'
    $SCHEMAPROP3 = 'type'         #'type' prop name in schema
    $PROP4 = 'Schema_ReadOnly'
    $SCHEMAPROP4 = 'readonly'     #'readonly' prop name in schema
    $dataInSchema = $false

    if($Data.'@odata.type' -ne '' -and $null -ne $Data.'@odata.type')
    {
        $DataType = $Data.'@odata.type'
    }

    foreach($dataProp in $data.PSObject.Properties)
    {
        foreach($schProp in $Schema.Properties.PSObject.Properties)
        {
            if($schProp.Name -eq $dataProp.Name)
            {
                $dataInSchema = $true
                if($dataProp.TypeNameOfValue -eq 'System.String' -or $dataProp.TypeNameOfValue -eq 'System.Int32')
                {
                    
                    $outputObj = New-Object PSObject
                    $schToUse = $null
                    if($schProp.value.PSObject.properties.Name.Contains("`$ref"))
                    {
                        $subpath = ''
                        if($schProp.value.'$ref'.contains('.json#/'))
                        {
                            $startInd = $schProp.value.'$ref'.IndexOf('.json#/')
                            $subpath = $schProp.value.'$ref'.Substring(0,$startInd+6)
                            $subpath = $subpath.replace('#','')
                        }
                        else
                        {
                            $subpath = $schProp.value.'$ref'.replace('#','')
                        }
                        
                        $schemaJSONLink = Get-HPERedfishSchemaExtref -odatatype $subpath.replace('.json','') -Session $Session -Language $Language
                        #$index = $schemaJSONLink.LastIndexOf('/')
                        #$prefix = $schemaJSONLink.SubString(0,$index+1)
                        
                        $split = $schemaJSONLink.Split('/')
                        $prefix = ''
                        for($i=0;$i -lt $split.length-2; $i++ )
                        {
                            $prefix = $prefix + $split[$i] + '/'
                        }
                        $newLink = $prefix + $subpath

                        $schToUse = Get-HPERedfishDataRaw -odataid $newLink -Session $session
                    }
                    else
                    {
                        $schToUse = $schProp.Value
                    }

                    if(-not($schToUse.$SCHEMAPROP1 -eq '' -or $null -eq $schToUse.$SCHEMAPROP1))
                    {
                        $outputObj | Add-Member NoteProperty $PROP1 $schToUse.$SCHEMAPROP1
                    }
                    if($schToUse.PSObject.Properties.Name.Contains('enum') -eq $true)
                    {
                        $outputObj | Add-Member NoteProperty $PROP2 $schToUse.enum
                    }
                    if($schToUse.PSObject.Properties.Name.Contains('enumDescriptions') -eq $true)
                    {    
                        $outputObj | Add-Member NoteProperty 'schema_enumDescriptions' $schToUse.enumDescriptions
                    }
                    <#if($schToUse.PSObject.Properties.Name.Contains('enum') -eq $true)
                    {
                        $outputObj | Add-Member NoteProperty 'schema_valueType' $schToUse.type
                    }#>
                    if(-not($schToUse.$SCHEMAPROP3 -eq '' -or $null -eq $schToUse.$SCHEMAPROP3))
                    {
                        $outputObj | Add-Member NoteProperty $PROP3 $schToUse.$SCHEMAPROP3
                    }
                    if($schToUse.$SCHEMAPROP4 -eq $true -or $schToUse.$SCHEMAPROP4 -eq $false) # readonly is true or false 
                    {
                        $outputObj | Add-Member NoteProperty $PROP4 $schToUse.$SCHEMAPROP4
                    }
                    if(-not ($DictionaryOfSchemas.ContainsKey($dataProp.Name)))
                    {
                        $DictionaryOfSchemas.Add($dataProp.Name, $outputObj)
                    }
                    $DataProperties | Add-Member NoteProperty $dataProp.Name $dataProp.value
                }
                elseif($dataProp.TypeNameOfValue -eq 'System.Object[]')
                {
                    $dataList = @()
                    for($i=0;$i-lt$dataProp.value.Length;$i++)
                    {
                        $dataPropElement = ($dataProp.Value)[$i]
                        if($dataPropElement.GetType().ToString() -eq 'System.String' -or $dataPropElement.GetType().ToString() -eq 'System.Int32')
                        {
                            $dataList += $dataPropElement
                            if(-not ($DictionaryOfSchemas.ContainsKey($dataProp.Name)))
                            {

                                if($schprop.value.items.PSObject.Properties.name.Contains('anyOf'))
                                {
                                    $x = $schProp.Value.items.anyOf
                                }
                                else
                                {
                                    $x = $schProp.Value.items
                                }
                                $outputObj = New-Object PSObject
                                if(-not($schema.Properties.($schprop.Name).$SCHEMAPROP1 -eq '' -or $null -eq $schema.Properties.($schprop.Name).$SCHEMAPROP1))
                                {
                                    $outputObj | Add-Member NoteProperty $PROP1 $schema.Properties.($schprop.Name).$SCHEMAPROP1
                                }
                                if($x.PSObject.Properties.Name.Contains('enum') -eq $true)
                                {
                                    $outputObj | Add-Member NoteProperty $PROP2 $x.enum
                                }
                                if($x.PSObject.Properties.Name.Contains('enumDescriptions') -eq $true)
                                {    
                                    $outputObj | Add-Member NoteProperty 'schema_enumDescriptions' $x.enumDescriptions
                                }
                                <#if($schToUse.PSObject.Properties.Name.Contains('enum') -eq $true)
                                {
                                    $outputObj | Add-Member NoteProperty 'schema_valueType' $schToUse.type
                                }#>
                                if(-not($x.$SCHEMAPROP3 -eq '' -or $null -eq $x.$SCHEMAPROP3))
                                {
                                    $outputObj | Add-Member NoteProperty $PROP3 $x.$SCHEMAPROP3
                                }
                                if($x.$SCHEMAPROP4 -eq $true -or $x.$SCHEMAPROP4 -eq $false) # readonly is true or false 
                                {
                                    $outputObj | Add-Member NoteProperty $PROP4 $x.$SCHEMAPROP4
                                }                            
                                $DictionaryOfSchemas.Add($dataProp.Name, $outputObj)
                            }
                        }
                        elseif($dataPropElement.GetType().ToString() -eq 'System.Management.Automation.PSCustomObject')
                        {
                            $psObj = New-Object PSObject
                            if($schprop.Value.PSObject.Properties.name.Contains('items'))
                            {
                                if($schprop.value.items.PSObject.Properties.name.Contains('anyOf'))
                                {
                                    $x = $schProp.Value.items.anyOf
                                }
                                else
                                {
                                    $x = $schProp.Value.items
                                }
                            }
                            else
                            {
                                $x = $schProp.value
                            }
                            if($x.PSObject.properties.Name.Contains("`$ref"))
                            {
                                $subpath = ''
                                if($x.'$ref'.contains('.json#/'))
                                {
                                    $startInd = $x.'$ref'.IndexOf('.json#/')
                                    $subpath = $x.'$ref'.Substring(0,$startInd+6)
                                    $subpath = $subpath.replace('#','')
                                    $schemaJSONLink = Get-HPERedfishSchemaExtref -odatatype $subpath.replace('.json','') -Session $Session -Language $Language
                                    $index = $schemaJSONLink.LastIndexOf('/')
                                    $prefix = $schemaJSONLink.SubString(0,$index+1)
                                    $newLink = $prefix + $subpath

                                    $sch = Get-HPERedfishDataRaw -odataid $newLink -Session $session
                                }
                                elseif($x.'$ref'.Contains('#'))
                                {
                                    if($x.'$ref'.IndexOf('#') -eq 0)
                                    {
                                        $laterPath = $x.'$ref'.Substring(2)
                                        $sch = Get-HPERedfishSchema -odatatype $DataType -Session $Session -Language $Language
                                    }
                                    else
                                    {
                                        $subpath = $x.'$ref'.replace('#','')
                                        $schemaJSONLink = Get-HPERedfishSchemaExtref -odatatype $subpath.replace('.json','') -Session $Session -Language $language
                                        $split = $schemaJSONLink.Split('/')
                                        $prefix = ''
                                        for($i=0;$i -lt $split.length-2; $i++ )
                                        {
                                            $prefix = $prefix + $split[$i] + '/'
                                        }
                                        $newLink = $prefix + $subpath

                                        $sch = Get-HPERedfishDataRaw -odataid $newLink -Session $session
                                    }
                                }

                                $schToUse = $sch
                                if($laterPath -ne '')
                                {
                                    $tmp = $laterPath.Replace('/','.')
                                    $schToUse = $sch
                                    foreach($x in $tmp.split('.'))
                                    {
                                        $schToUse = $sch.$x
                                    }
                                }
                            }
                            else
                            {
                                $schToUse = $x
                            }
                            $opObj, $DictionaryOfSchemas = Get-HPERedfishDataPropRecurse -Data $dataPropElement -Schema $schToUse -Session $Session -DictionaryOfSchemas $DictionaryOfSchemas -DataType $DataType
                            $dataList += $opObj
                        }
                    }
                    $DataProperties | Add-Member NoteProperty $dataProp.Name $dataList #$outputObj
                }
                elseif($dataProp.TypeNameOfValue -eq 'System.Management.Automation.PSCustomObject')
                {
                    $psObj = New-Object PSObject
                    if($schProp.value.PSObject.properties.Name.Contains("`$ref"))
                    {
                        
                        $laterPath = ''
                        $subpath = ''
                        if($schProp.value.'$ref'.contains('.json#/'))
                        {
                            $startInd = $schProp.value.'$ref'.IndexOf('.json#/')
                            $laterPath = $schProp.value.'$ref'.Substring($startInd+7)
                            $subpath = $schProp.value.'$ref'.Substring(0,$startInd+6)
                            $subpath = $subpath.replace('#','')
                            $schemaJSONLink = Get-HPERedfishSchemaExtref -odatatype $subpath.replace('.json','') -Session $Session -Language $language
                            $split = $schemaJSONLink.Split('/')
                            $prefix = ''
                            for($i=0;$i -lt $split.length-2; $i++ )
                            {
                                $prefix = $prefix + $split[$i] + '/'
                            }
                            $newLink = $prefix + $subpath
                            $refSchema = Get-HPERedfishDataRaw -odataid $newLink -Session $session
                        }
                        elseif($schProp.value.'$ref'.Contains('#'))
                        {
                            if($schProp.Value.'$ref'.IndexOf('#') -eq 0)
                            {
                                $laterPath = $schProp.value.'$ref'.Substring(2)
                                $refSchema = Get-HPERedfishSchema -odatatype $DataType -Session $session -Language $Language
                            }
                            else
                            {
                                $subpath = $schProp.value.'$ref'.replace('#','')
                                $schemaJSONLink = Get-HPERedfishSchemaExtref -odatatype $subpath.replace('.json','') -Session $Session -Language $language
                                $split = $schemaJSONLink.Split('/')
                                $prefix = ''
                                for($i=0;$i -lt $split.length-2; $i++ )
                                {
                                    $prefix = $prefix + $split[$i] + '/'
                                }
                                $newLink = $prefix + $subpath
                                $refSchema = Get-HPERedfishDataRaw -odataid $newLink -Session $session
                            }
                        }
                        

                        if($laterPath -eq '')
                        {
                            $sch = $refSchema
                        }
                        else
                        {
                            $tmp = $laterPath.Replace('/','.')
                            $sch = $refSchema
                            foreach($x in $tmp.split('.'))
                            {
                                $sch = $sch.$x
                            }
                        }
                        $opObj, $DictionaryOfSchemas = Get-HPERedfishDataPropRecurse -Data $dataProp.Value -Schema $sch -Session $Session -DictionaryOfSchemas $DictionaryOfSchemas -schemaLink $newLink -DataType $DataType
                        $DataProperties | Add-Member NoteProperty $dataProp.Name $opObj
                        
                    }
                    else
                    {
                        $opObj, $DictionaryOfSchemas  = Get-HPERedfishDataPropRecurse -Data $dataProp.Value -Schema $schProp.Value -Session $Session -DictionaryOfSchemas $DictionaryOfSchemas -DataType $DataType
                        $DataProperties | Add-Member NoteProperty $dataProp.Name $opObj #$psObj
                    }
                }
                break;
            }
        }
        
        if($dataInSchema -eq $false)
        {
            $DataProperties | Add-Member NoteProperty $dataProp.Name $dataProp.Value
        }
    }
    #Write-Host $DataProperties
    return $DataProperties, $DictionaryOfSchemas
}

function Get-HPERedfishTypePrefix
{
    param
    (
        [System.String]
        $odatatype
    )

    $gen10Regex = "^[a-zA-Z0-9]+\.v\d+_\d+_\d+\.[a-zA-Z0-9]+$"
    $gen89Regex = "^[a-zA-Z0-9]+\.\d+\.\d+\.\d+\.[a-zA-Z0-9]+$"
    $noVerRegex = "^[a-zA-Z0-9]+\.[a-zA-Z0-9]+$"
                        
    $g10Matches = [Regex]::Matches($odatatype,$gen10Regex)
    $g89Matches = [Regex]::Matches($odatatype,$gen89Regex)
    $noVerMatches = [Regex]::Matches($odatatype,$noVerRegex)


    if($g10Matches.Count -gt 0 -or $g89Matches.count -gt 0 -or $noVerMatches.Count -gt 0)
    {
        $dotIndex = $odatatype.IndexOf('.')
        return $odatatype.Substring(0, $dotIndex)
    }

    if($odatatype.Split('.').Count -eq 2)
    {
        return $odatatype.Split('.')[0]
    }

    return $odatatype

}

function Set-Message
{
    param
    (
        [System.String]
        $Message,
	
        [System.Object]
        $MessageArg
    )

    $m = $Message
    for($i = 0; $i -lt $MessageArg.count; $i++)
    {
        $placeHolder = '%'+($i+1)
        $value = $MessageArg[$i]
        $m =  $m -replace $placeHolder, $value
    }
    return $m
}

function Get-ErrorRecord
{
    param
    (
        [System.Net.HttpWebResponse]
        $WebResponse,
	
        [System.String]
        $CmdletName
    )

    $webStream = $webResponse.GetResponseStream()
    $respReader = New-Object System.IO.StreamReader($webStream)
    $respJSON = $respReader.ReadToEnd()
    $webResponse.close()
    $webStream.close()
    $respReader.Close()
    $resp = $respJSON|ConvertFrom-Json
    $webResponse.Close()
            
    $noValidSession = $false
    $msg = ''
    foreach($i in $resp.error.'@Message.ExtendedInfo')
    {
        if($i.MessageId -match 'NoValidSession')
        {
            $noValidSession = $true
            $msg = $msg + $i.messageID + "`n"
        }
    }
    if($noValidSession -eq $false)
    {
        foreach($extInfo in $resp.error.'@Message.ExtendedInfo')
        {
            $msg = $msg + "`n" + $extInfo.messageID + "`n"
            if($extInfo.PSObject.Properties.Name.Count -gt 2)
            {
                $status = $extInfo
            }
            else
            {
                try
                {
                    $status = Get-HPERedfishMessage -MessageID $extInfo.MessageID -MessageArg $extInfo.MessageArgs -Session $session
                }
                catch
                {
                    Write-Verbose $_.Message
                    $status = $extInfo
                }
            }
            foreach($mem in $status.PSObject.Properties)
            {
                $msg = $msg + $mem.Name + ': ' + $mem.value + "`n"
            }
            $msg = $msg + "-`n"
        }
    }

    $message = $msg + ($_| Format-Table | Out-String)
    $targetObject = $CmdletName
    try{
        $exception = New-Object $_.Exception $message
        $errorID = $_.FullyQualifiedErrorId
        $errorCategory = $_.CategoryInfo.Category
    }
    catch
    {
        $exception = New-Object System.InvalidOperationException $message
        $errorID = 'InvocationException'
        $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidOperation
    }
        

    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorID, $errorCategory, $targetObject
    return $errorRecord
}

function Get-BlockIndex
{
    param
    (
        [System.String]$InputJSONString,
        [System.Int32]$PropertyIndex
    )
    
    $bracketCounter = 0
    $blockStartIndex = 0
    $blockEndIndex = $InputJSONString.Length-1
    for($i=$PropertyIndex; $i-gt0; $i--)
    {
        if($InputJSONString[$i] -eq "}") { $bracketCounter = $bracketCounter + 1 }
        elseif($InputJSONString[$i] -eq "{")
        {
            if($bracketCounter -eq 0)
            {
                $blockStartIndex = $i
                break
            }
            else { $bracketCounter = $bracketCounter - 1 }
        }
    }
    for($i=$PropertyIndex; $i-lt$InputJSONString.Length; $i++)
    {
        if($InputJSONString[$i] -eq "{") { $bracketCounter = $bracketCounter + 1 }
        elseif($InputJSONString[$i] -eq "}")
        {
            if($bracketCounter -eq 0)
            {
                $blockEndIndex = $i+1
                break
            }
            else { $bracketCounter = $bracketCounter - 1 }
        }
    }
    return $blockStartIndex,$blockEndIndex
}

function Get-BlockEnd
{
    param
    (
        [System.String]$InputJSONString,
        [System.Int32]$PropertyIndex,
        [System.String]$BracketType = '{'
    )
    
    $bracketCounter = 0
    $blockStartIndex = 0
    $blockEndIndex = $InputJSONString.Length-1

    if($InputJSONString[$PropertyIndex] -eq '{' -or $InputJSONString[$PropertyIndex] -eq '[')
    {
        $PropertyIndex = $PropertyIndex+1
    }
    else
    {
        for($i=$PropertyIndex;$i-lt$InputJSONString.Length; $i++)
        {
            if($InputJSONString[$i] -eq ',' -or $InputJSONString[$i] -eq '}' -or $InputJSONString[$i] -eq ']')
            {
                return $i;
            }
        }
    }

    $startBracket = '{'
    $endBracket = '}'

    if($BracketType -eq '[')
    {
        $startBracket = '['
        $endBracket = ']'
    }

    for($i=$PropertyIndex; $i-lt$InputJSONString.Length; $i++)
    {
        if($InputJSONString[$i] -eq $startBracket) { $bracketCounter = $bracketCounter + 1 }
        elseif($InputJSONString[$i] -eq $endBracket)
        {
            if($bracketCounter -eq 0)
            {
                $blockEndIndex = $i
                break
            }
            else { $bracketCounter = $bracketCounter - 1 }
        }
    }

    $i = $blockEndIndex + 1
    while($InputJSONString[$i] -notin @(',','}',']'))
    {
        $i++
    }
    return $i
}

function Remove-PropertyDuplicate
{
    param
    (
        [System.String]
        $InputJSONString,

        [System.String]
        $Property
    )

    $block = ""
    $blockStart = 0
    $blockEnd = $InputJSONString.Length
    
    $block = $InputJSONString.Substring($blockStart,$blockEnd-$blockStart)

    $matchedObjects = $InputJSONString| Select-String -Pattern "`"$property`": " -AllMatches
    if($matchedObjects.Matches.Count -eq 0)
    {
        $matchedObjects = $InputJSONString| Select-String -Pattern "`"$property`":" -AllMatches
    }

    for($i=0; $i-lt$matchedObjects.Matches.Count; $i++)
    {
        $start,$end = Get-BlockIndex $InputJSONString $matchedObjects.Matches[$i].Index
        $matchedObjects.Matches[$i]|Add-Member blockstart $start
        $matchedObjects.Matches[$i]|Add-Member blockend $end
    }

    $propList = @{}
    for($i=0; $i-lt$matchedObjects.Matches.Count; $i++)
    {
        try
        {
            $prop = $matchedObjects.Matches[$i]
            $propList.Add($prop.blockstart,$prop)#$prop.Value.Substring(1,$prop.val))
        }
        catch
        {
            if($_.Exception.Message -match "Item has already been added.")
            {
                $prop1 = $propList[$matchedObjects.Matches[$i].blockstart]
                $prop2 = $matchedObjects.Matches[$i]
            
                $startChar = '{'
                $jsonStart = 0
                $jsonEnd = 0
                $startIndex = $prop1.Index+$prop1.Value.Length
                if($InputJSONString.Substring($startIndex,1) -eq '[')
                {
                    $startChar = '['
                }
                $endIndex = Get-BlockEnd -InputJSONString $InputJSONString -PropertyIndex $startIndex -BracketType $startChar
                $prop1ValueJson = $InputJSONString.Substring($startIndex, $endIndex-$startIndex)
                $prop1ValueObj = $prop1ValueJson | ConvertFrom-Json
                if($prop1ValueObj.PSObject.Properties.Name -match 'Deprecated')
                {
                    $InputJSONString = $InputJSONString.Remove($prop1.Index, $endIndex-$prop1.Index+1)
                }
                else
                {
                    $startChar = '{'
                    $jsonStart = 0
                    $jsonEnd = 0
                    $startIndex = $prop2.Index+$prop2.Value.Length
                    if($InputJSONString.Substring($startIndex,1) -eq '[')
                    {
                        $startChar = '['
                    }
                    $endIndex = Get-BlockEnd -InputJSONString $InputJSONString -PropertyIndex $startIndex -BracketType $startChar
                    if($InputJSONString[$prop2.Index + $endIndex-$prop2.Index] -eq '}' -or $InputJSONString[$prop2.Index + $endIndex-$prop2.Index] -eq ']')
                    {                    
                        $st = $prop2.Index
                        $backPtr = $st
                        while($backPtr -gt 0 )
                        {
                            if($InputJSONString[$backPtr] -eq '[' -or $InputJSONString[$backPtr] -eq '{')
                            {
                                break;
                            }
                            elseif($InputJSONString[$backPtr] -eq ',')
                            {
                                $st = $backPtr
                                break;
                            }
                            $backPtr--
                        }
                        $InputJSONString = $InputJSONString.Remove($st, $endIndex-$st)
                    }
                    else
                    {
                        $InputJSONString = $InputJSONString.Remove($prop2.Index, $endIndex-$prop2.Index+1)
                    }
                }

                for($j=$i+1; $j-lt$matchedObjects.Matches.Count; $j++)
                {
                    $matchedObjects.Matches[$j].blockstart = $matchedObjects.Matches[$j].blockstart - ($endIndex-$startIndex)
                    $matchedObjects.Matches[$j].blockend = $matchedObjects.Matches[$j].blockend - ($endIndex-$startIndex)
                    $matchedObjects.Matches[$j].Index = $matchedObjects.Matches[$j].Index - ($endIndex-$startIndex)
                }
            }
        }
    }
    return $InputJSONString
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

function Get-OdataIdForOdataType([System.String]$OdataType, [System.Collections.Generic.HashSet[string]]$OdataIdSet)
{
    $OdataType = $OdataType.ToLower()
    $odataTypeSplit = $OdataType.Split('.')

    $regexString = "^[vV]\d+_\d+_\d+$"
    $set1 = @{}
    $set2a = @{}
    $set2b = @{}
    $set3 = @{}
    $set4 = @{}
    $set5 = @{}

    foreach($s in $OdataIdSet)
    {
        $tempOdataId = $s
        if($tempOdataId[$tempOdataId.length-1] -ne '/')
        { 
            $tempOdataId = $tempOdataId + '/'
        }
        $split1 = $tempOdataId.Split('/')
        $typeFromOdataId = $split1[$split1.length-2] -replace "%23",""
        $split2 = $typeFromOdataId.Split('.')

        if($split2.Length -eq 5) { $set5.Add($typeFromOdataId.ToLower(), $s) }
        elseif($split2.Length -eq 4) { $set4.Add($typeFromOdataId.ToLower(), $s) }
        elseif($split2.Length -eq 3) { $set3.Add($typeFromOdataId.ToLower(), $s) }
        elseif($split2.Length -eq 2) 
        {
            if($split2[1] -match $regexString) { $set2a.Add($typeFromOdataId.ToLower(), $s) }
            else { $set2b.Add($typeFromOdataId.ToLower(), $s) }
        }
        else { $set1.Add($typeFromOdataId.ToLower(), $s) }
    }


    if($odataTypeSplit.Length -eq 5)
    {
        $odataType5 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[2]+'.'+$odataTypeSplit[3]+'.'+$odataTypeSplit[4]
        $odataType4 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[2]+'.'+$odataTypeSplit[3]
        $odataType1 = $odataTypeSplit[0]
        if($set5.Count -gt 0 -and $set5.Keys.Contains($OdataType5)) { return $set5[$OdataType5] }
        if($set4.Count -gt 0 -and $set4.Keys.Contains($OdataType4)) { return $set4[$OdataType4] }
        if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
    }
    elseif($odataTypeSplit.Length -eq 4)
    {
        $odataType5 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[2]+'.'+$odataTypeSplit[3]+'.'+$odataTypeSplit[0]
        $odataType4 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[2]+'.'+$odataTypeSplit[3]
        $odataType1 = $odataTypeSplit[0]
        if($set4.Count -gt 0 -and $set4.Keys.Contains($OdataType4)) { return $set4[$OdataType4] }
        if($set5.Count -gt 0 -and $set5.Keys.Contains($OdataType5)) { return $set5[$OdataType5] }
        if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
    }
    elseif($odataTypeSplit.Length -eq 3)
    {
        $odataType3 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[2]
        $odataType2a = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]
        $odataType2b = $odataTypeSplit[0]+'.'+$odataTypeSplit[0]
        $odataType1 = $odataTypeSplit[0]
        if($set3.Count -gt 0 -and $set3.Keys.Contains($OdataType3)) { return $set3[$OdataType3] }
        if($set2a.Count -gt 0 -and $set2a.Keys.Contains($OdataType2a)) { return $set2a[$OdataType2a] }
        if($set2b.Count -gt 0 -and $set2b.Keys.Contains($OdataType2b)) { return $set2a[$OdataType2b] }
        if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
    }
    elseif($odataTypeSplit.Length -eq 2)
    {
        if($odataTypeSplit[1] -match $regexString)
        {
            $odataType3 = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]+'.'+$odataTypeSplit[0]
            $odataType2a = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]
            $odataType2b = $odataTypeSplit[0]+'.'+$odataTypeSplit[0]
            $odataType1 = $odataTypeSplit[0]
            if($set2a.Count -gt 0 -and $set2a.Keys.Contains($OdataType2a)) { return $set2a[$OdataType2a] }
            if($set2b.Count -gt 0 -and $set2b.Keys.Contains($OdataType2b)) { return $set2a[$OdataType2b] }
            if($set3.Count -gt 0 -and $set3.Keys.Contains($OdataType3)) { return $set3[$OdataType3] }
            if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
        }
        else
        {
            $odataType2a = $odataTypeSplit[0]+'.'+$odataTypeSplit[1]
            $odataType2b = $odataTypeSplit[0]+'.'+$odataTypeSplit[0]
            $odataType1 = $odataTypeSplit[0]
            if($set2a.Count -gt 0 -and $set2a.Keys.Contains($OdataType2a)) { return $set2b[$OdataType2a] }
            if($set2b.Count -gt 0 -and $set2b.Keys.Contains($OdataType2b)) { return $set2b[$OdataType2b] }
            if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
        }
    }
    else
    {
        $odataType1 = $odataTypeSplit[0]
        if($set1.Count -gt 0 -and $set1.Keys.Contains($OdataType1)) { return $set1[$OdataType1] }
    }
}

function Connect-HPERedfish
{
<#
.SYNOPSIS
Creates a session between PowerShell client and the Redfish data source.

.DESCRIPTION
Creates a session between the PowerShell client and the Redfish data source using HTTP POST method and returns a session object. The session object has the following members:
1. 'X-Auth-Token' to identify the session
2. 'RootURI' of the Redfish data source
3. 'Location' which is used for logging out of the session.
4. 'RootData' includes data from '/redfish/v1/'. It includes the refish data and the odata id of components like systems, chassis, etc.

.PARAMETER Address
IP address or Hostname of the target HPE Redfish data source.

.PARAMETER Username
Username of iLO account to access the HPE Redfish data source.

.PARAMETER Password
Password of iLO account to access the iLO.

.PARAMETER Cred
PowerShell PSCredential object having username and passwword of iLO account to access the iLO.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.INPUTS
System.String
You can pipe the Address i.e. the hostname or IP address to Connect-HPERedfish.

.OUTPUTS
System.Management.Automation.PSCustomObject
Connect-HPERedfish returns a PSObject that has session details - X-Auth-Token, RootURI, Location and RootData.

.EXAMPLE
PS C:\> $s = Connect-HPERedfish -Address 192.184.217.212 -Username admin -Password admin123


PS C:\> $s|fl


RootUri      : https://192.184.217.212/redfish/v1/
X-Auth-Token : e02ce457b3fa4ad10f9ebc64d33c1445
Location     : https://192.184.217.212/redfish/v1/Sessions/admin556733a2020c49bb/
RootData     : @{@odata.context=/redfish/v1/$metadata#ServiceRoot/; @odata.id=/redfish/v1/; @odata.type=#ServiceRoot.1.0.0.ServiceRoot; AccountService=; Chassis=; EventService=; Id=v1; JsonSchemas=; Links=; Managers=; Name=HP RESTful Root Service; Oem=; RedfishVersion=1.0.0; Registries=; SessionService=; Systems=; UUID=8dea7372-23f9-565f-9396-2cd07febbe29}

.EXAMPLE
PS C:\> $cred = Get-Credential
PS C:\> $s = Connect-HPERedfish -Address 192.184.217.212 -Cred $cred
PS C:\> $s|fl


RootUri      : https://192.184.217.212/redfish/v1/
X-Auth-Token : a5657bdsgfsdg3650f9ebc64d33c3262
Location     : https://192.184.217.212/redfish/v1/Sessions/admin75675856ad6g25fg6/
RootData     : @{@odata.context=/redfish/v1/$metadata#ServiceRoot/; @odata.id=/redfish/v1/; @odata.type=#ServiceRoot.1.0.0.ServiceRoot; AccountService=; Chassis=; EventService=; Id=v1; JsonSchemas=; Links=; Managers=; Name=HP RESTful Root Service; Oem=; RedfishVersion=1.0.0; Registries=; SessionService=; Systems=; UUID=8dea7372-23f9-565f-9396-2cd07febbe29}

.LINK
http://www.hpe.com/servers/powershell

#>
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

        #$webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -Payload $payload -CmdletName $cmdletName -DisableExpect100Continue $DisableCertificateAuthentication

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

function Disable-HPERedfishCertificateAuthentication
{
<#
.SYNOPSIS
Disables SSL certificate authentication in the current PowerShell session.

.DESCRIPTION
The Disable-HPERedfishCertificateAuthentication cmdlet disables checking of SSL certificate when using HPERedfishCmdlets. The certificate checking is disabled for all requests until Enable-HPERedfishCertificateAuthentication cmdlet is executed or the session is closed. 

.NOTES
Disabling the certificate check should be used until a valid certificate has been installed on the device being connected to. Installing valid certificates that can be verified gives and extra level of network security.

.EXAMPLE
PS C:\> Disable-HPERedfishCertificateAuthentication


This command disables the server certificate authentication, and sets the session level flag to FALSE. The scope of the session level flag is limited to this session of PowerShell.

.LINK
http://www.hpe.com/servers/powershell

#>
	[CmdletBinding(PositionalBinding=$false)]
    param() # no parameters		
    $script:CertificateAuthenticationFlag = $false
}

function Disconnect-HPERedfish
{
<#
.SYNOPSIS
Disconnects specified session between PowerShell client and Redfish data source.

.DESCRIPTION
Disconnects the session between the PowerShell client and Redfish data source by deleting the session information from location pointed to by Location field in Session object passed as parameter. This cmdlets uses HTTP DELETE method for removing session information from location.

.PARAMETER Session
Session object that has Location information obtained by executing Connect-HPERedfish cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
The variable storing the session object will not become null/blank but cmdlets cannot not be executed using the session object.

.INPUTS
System.String
You can pipe the session object to Disconnect-HPERedfish. The session object is obtained from executing Connect-HPERedfish.

.OUTPUTS
This cmdlet does not generate any output.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> Disconnect-HPERedfish -Session $s
PS C:\> 

This will disconnect the session given in the variable $s

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        if($null -eq $session -or $session -eq '')
        {
            throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
        }
        
        $tempuri = $Session.Location
        [System.Uri]$uri = $null
        if([Uri]::TryCreate($tempuri, [UriKind]::Absolute, [ref]$uri) -eq $false)
        {
            $initUri = New-Object System.Uri -ArgumentList @([URI]$Session.RootUri)
            $baseUri = $initUri.Scheme + '://' + $initUri.Authority  # 'Authority' has the port number if provided by the user (along with the IP or hostname)

            $uri = (New-Object System.Uri -ArgumentList @([URI]$baseUri, $tempuri)).ToString()
        }
                       
        $method = "DELETE"
        $cmdletName = "Disconnect-HPERedfish"
    
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -CmdletName $cmdletName -Session $Session
        $webResponse.Close()
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Edit-HPERedfishData
{
<#
.SYNOPSIS
Executes HTTP PUT method on the destination server.

.DESCRIPTION
Executes HTTP PUT method on the desitination server with the data from Setting parameter.

.PARAMETER Odataid
Odataid where the setting is to be sent using HTTP PUT method.

.PARAMETER Setting
Data is the payload body for the HTTP PUT request in name-value pair format. The parameter can be a hashtable with multiple name-value pairs or a JSON string.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
- Edit-HPERedfishData is for HTTP PUT method.
- Invoke-HPERedfishAction is for HTTP POST method.
- Remove-HPERedfishData is for HTTP DELETE method.
- Set-HPERedfishData is for HTTP PATCH method.

See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.


.INPUTS
System.String
You can pipe the Odataid to Edit-HPERedfishData. Odataid points to the location where the PUT method is to be executed.

.OUTPUTS
System.Management.Automation.PSCustomObject
Edit-HPERedfishData returns a PSObject that has message from the HTTP response. The response may be informational or may have a message requiring an action like server reset.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [System.Object]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Setting,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
  
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    if(($null -ne $setting) -and $Setting.GetType().ToString() -notin @('System.Collections.Hashtable', 'System.String'))
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Setting.GetType().ToString() ,'Setting'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
    
        $jsonStringData = ''

        if($null -eq $Setting)
        {
            $jsonStringData = '{}'
        }
        else
        {
            if($Setting.GetType().ToString() -eq 'System.Collections.Hashtable')
            {
                $jsonStringData = $setting | ConvertTo-Json -Depth 10
            }
            else
            {
                $jsonStringData = $Setting
            }
        }


        $uri = Get-HPERedfishUriFromOdataId -Odataid $odataid -Session $Session
        $method = "PUT"
        $payload = $jsonStringData
        $cmdletName = "Edit-HPERedfishData"
    
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -Payload $payload -CmdletName $cmdletName -Session $Session
        
        try
        {
            $webStream = $webResponse.GetResponseStream()
            $respReader = New-Object System.IO.StreamReader($webStream)
            $resp = $respReader.ReadToEnd()

            $webResponse.Close()
            $webStream.Close()
            $respReader.Close()

            return $resp|ConvertFrom-Json
        }
        finally
        {
            if ($null -ne $webResponse -and $webResponse -is [System.IDisposable]){$webResponse.Dispose()}
            if ($null -ne $webStream -and $webStream -is [System.IDisposable]){$webStream.Dispose()}
            if ($null -ne $respReader -and $respReader -is [System.IDisposable]){$respReader.Dispose()}
        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Enable-HPERedfishCertificateAuthentication
{
<#
.SYNOPSIS
Enables SSL certificate authentication in the current PowerShell session.

.DESCRIPTION
The Enable-HPERedfishCertificateAuthentication cmdlet enables checking of SSL certificate when using HPERedfishCmdlets. In a new PowerShell session, the SSL certificate checking is enabled by default. When communicating using HTTPS protocol, the target device is checked for a valid certificate. If the certificate is not present, then the connection is not made and the client does not send the HTTPS request to the target. This certificate check can be disabled using Disable-HPERedfishCertificateAuthentication and can be enabled using Enable-HPERedfishCertificateAuthentication.

.NOTES
Disabling the certificate check should be used until a valid certificate has been installed on the device being connected to. Installing valid certificates that can be verified gives and extra level of network security.

.EXAMPLE
PS C:\> Enable-HPERedfishCertificateAuthentication


This command enables the server certificate authentication, and sets the session level flag to TRUE. The scope of the session level flag is limited to this session of PowerShell. Default value of session level is flag TRUE.


.LINK
http://www.hpe.com/servers/powershell

#>

	[CmdletBinding(PositionalBinding=$false)]
	param() # no parameters	
    $script:CertificateAuthenticationFlag = $true
}

function Find-HPERedfish 
{
<#
.SYNOPSIS
Find list of HPE Redfish data sources in a specified subnet.

.DESCRIPTION
Lists HPE Redfish sources in the subnet provided. You must provide the subnet in which the Redfish data sources have to be searched.

.PARAMETER Range
Specifies the lower parts of the IP addresses which is the subnet in which the Redfish data sources are being searched. For IP address format 'a.b.c.d', where a, b, c, d represent an integer from 0 to 255, the Range parameter can have values such  as: 
a - eg: 10 - for all IP addresses in 10.0.0.0 to 10.255.255.255
a.b - eg: 10.44 - for all IP addresses in 10.44.0.0 to 10.44.255.255
a.b.c - eg: 10.44.111 - for all IP addresses in 10.44.111.0 to 10.44.111.255
a.b.c.d - eg: 10.44.111.222 - for IP address 10.44.111.222
Each division of the IP address, can specify a range using a hyphen. eg: 
"10.44.111.10-12" returns IP addresses 10.44.111.10, 10.44.111.11, 10.44.111.12
Each division of the IP address, can specify a set using a comma. eg: 
"10.44.111.10,12" returns IP addresses 10.44.111.10, 10.44.111.12

.PARAMETER Timeout
Timeout period for ping request. Timeout period can be specified by the user where there can be a possible lag due to geographical distance between client and server. Default value is 300 which is 300 milliseconds. If the default timeout is not long enough, no Redfish data sources will be found and no errors 
will be displayed.

.INPUTS
String or a list of String specifying the lower parts of the IP addresses which is the subnet in which the Redfish data sources are being searched. For IP address format 'a.b.c.d', where a, b, c, d represent an integer from 0 to 255, the Range parameter can have values such as: 
    a - eg: 10 - for all IP addresses in 10.0.0.0 to 10.255.255.255
    a.b - eg: 10.44 - for all IP addresses in 10.44.0.0 to 10.44.255.255
    a.b.c - eg: 10.44.111 - for all IP addresses in 10.44.111.0 to 10.44.111.255
    a.b.c.d - eg: 10.44.111.222 - for IP address 10.44.111.222
Each division of the IP address, can specify a range using a hyphen. eg: "10.44.111.10-12" returns IP addresses 10.44.111.10, 10.44.111.11, 10.44.111.12.
Each division of the IP address, can specify a set using a comma. eg: "10.44.111.10,12" returns IP addresses 10.44.111.10, 10.44.111.12
Note: Both IPv4 and IPv6 ranges are supported.
Note: Port number is optional. With port number 8888 the input are 10:8888, 10.44:8888, 10.44.111:8888, 10.44.111.222:8888; Without port number, default port in iLO is used.

.OUTPUTS
System.Management.Automation.PSObject[]
List of service Name, Oem details, Service Version, Links, IP, and hostname for valid Redfish data sources in the subnet.
Use Get-Member to get details of fields in returned objects.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> Find-HPERedfish -Range 192.184.217.210-215
WARNING: It might take a while to search for all the HPE Redfish data sources if the input is
 a very large range. Use Verbose for more information.


@odata.context : /redfish/v1/$metadata#ServiceRoot
@odata.id      : /redfish/v1/
@odata.type    : #ServiceRoot.1.0.0.ServiceRoot
AccountService : @{@odata.id=/redfish/v1/AccountService/}
Chassis        : @{@odata.id=/redfish/v1/Chassis/}
EventService   : @{@odata.id=/redfish/v1/EventService/}
Id             : v1
JsonSchemas    : @{@odata.id=/redfish/v1/Schemas/}
Managers       : @{@odata.id=/redfish/v1/Managers/}
Name           : HP RESTful Root Service
Oem            : @{Hp=}
RedfishVersion : 1.0.0
Registries     : @{@odata.id=/redfish/v1/Registries/}
ServiceVersion : 1.0.0
SessionService : @{@odata.id=/redfish/v1/SessionService/}
Systems        : @{@odata.id=/redfish/v1/Systems/}
Time           : 2016-02-09T23:10:06Z
Type           : ServiceRoot.1.0.0
UUID           : 8dea7372-23f9-565f-9396-2cd07febbe29
links          : @{AccountService=; Chassis=; EventService=; Managers=; Registries=; Schemas=; 
                 SessionService=; Sessions=; Systems=; self=}
IP             : 192.184.217.212
HOSTNAME       : ilogen9.americas.net

@odata.context : /redfish/v1/$metadata#ServiceRoot
@odata.id      : /redfish/v1/
@odata.type    : #ServiceRoot.1.0.0.ServiceRoot
AccountService : @{@odata.id=/redfish/v1/AccountService/}
Chassis        : @{@odata.id=/redfish/v1/Chassis/}
EventService   : @{@odata.id=/redfish/v1/EventService/}
Id             : v1
JsonSchemas    : @{@odata.id=/redfish/v1/Schemas/}
Managers       : @{@odata.id=/redfish/v1/Managers/}
Name           : HP RESTful Root Service
Oem            : @{Hp=}
RedfishVersion : 1.0.0
Registries     : @{@odata.id=/redfish/v1/Registries/}
ServiceVersion : 1.0.0
SessionService : @{@odata.id=/redfish/v1/SessionService/}
Systems        : @{@odata.id=/redfish/v1/Systems/}
Time           : 2016-02-08T12:07:09Z
Type           : ServiceRoot.1.0.0
UUID           : 9c4df8e9-9f57-5fd2-ae1f-7b2a12916251
links          : @{AccountService=; Chassis=; EventService=; Managers=; Registries=; Schemas=; 
                 SessionService=; Sessions=; Systems=; self=}
IP             : 192.184.217.215
HOSTNAME       : ilom4.americas.net

.LINK
http://www.hpe.com/servers/powershell

#>
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)] [alias('IP')] $Range,
        [parameter(Mandatory=$false)] $Timeout = 300
    )
    Add-Type -AssemblyName System.Core

    $ping    = New-Object System.Net.NetworkInformation.Ping
    $options = New-Object System.Net.NetworkInformation.PingOptions(20, $false)
    $bytes   =  0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb
    $iptoping = New-Object System.Collections.Generic.HashSet[String]
    $validformat = $false

    #put all the input range in to array (one for IPv4, the other for IPv6)
    $InputIPv4Array = @()
    $InputIPv6Array = @() 

    # size of $IPv4Array will be the same as size of $InputIPv4Array, the same case to IPv6
    $IPv4Array = @()
    $IPv6Array = @()
	
    $ipv6_one_section='[0-9A-Fa-f]{1,4}'
    $ipv6_one_section_phen="$ipv6_one_section(-$ipv6_one_section)?"
	$ipv6_one_section_phen_comma="$ipv6_one_section_phen(,$ipv6_one_section_phen)*"

    $ipv4_one_section='(2[0-4]\d|25[0-5]|[01]?\d\d?)'
	$ipv4_one_section_phen="$ipv4_one_section(-$ipv4_one_section)?"
	$ipv4_one_section_phen_comma="$ipv4_one_section_phen(,$ipv4_one_section_phen)*"

    $ipv4_regex_inipv6="${ipv4_one_section_phen_comma}(\.${ipv4_one_section_phen_comma}){3}"  
    $ipv4_one_section_phen_comma_dot_findhpilo="(\.\.|\.|${ipv4_one_section_phen_comma}|\.${ipv4_one_section_phen_comma}|${ipv4_one_section_phen_comma}\.)"

    $port_regex = ':([1-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])'
	$ipv6_regex_findhpilo="^\s*(${ipv4_regex_inipv6}|${ipv6_one_section_phen_comma}|((${ipv6_one_section_phen_comma}:){1,7}(${ipv6_one_section_phen_comma}|:))|((${ipv6_one_section_phen_comma}:){1,6}(:${ipv6_one_section_phen_comma}|${ipv4_regex_inipv6}|:))|((${ipv6_one_section_phen_comma}:){1,5}(((:${ipv6_one_section_phen_comma}){1,2})|:${ipv4_regex_inipv6}|:))|((${ipv6_one_section_phen_comma}:){1,4}(((:${ipv6_one_section_phen_comma}){1,3})|((:${ipv6_one_section_phen_comma})?:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1,3}(((:${ipv6_one_section_phen_comma}){1,4})|((:${ipv6_one_section_phen_comma}){0,2}:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1,2}(((:${ipv6_one_section_phen_comma}){1,5})|((:${ipv6_one_section_phen_comma}){0,3}:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1}(((:${ipv6_one_section_phen_comma}){1,6})|((:${ipv6_one_section_phen_comma}){0,4}:${ipv4_regex_inipv6})|:))|(:(((:${ipv6_one_section_phen_comma}){1,7})|((:${ipv6_one_section_phen_comma}){0,5}:${ipv4_regex_inipv6})|:)))(%.+)?\s*$" 
	$ipv6_regex_findhpilo_with_bra ="^\s*\[(${ipv4_regex_inipv6}|${ipv6_one_section_phen_comma}|((${ipv6_one_section_phen_comma}:){1,7}(${ipv6_one_section_phen_comma}|:))|((${ipv6_one_section_phen_comma}:){1,6}(:${ipv6_one_section_phen_comma}|${ipv4_regex_inipv6}|:))|((${ipv6_one_section_phen_comma}:){1,5}(((:${ipv6_one_section_phen_comma}){1,2})|:${ipv4_regex_inipv6}|:))|((${ipv6_one_section_phen_comma}:){1,4}(((:${ipv6_one_section_phen_comma}){1,3})|((:${ipv6_one_section_phen_comma})?:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1,3}(((:${ipv6_one_section_phen_comma}){1,4})|((:${ipv6_one_section_phen_comma}){0,2}:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1,2}(((:${ipv6_one_section_phen_comma}){1,5})|((:${ipv6_one_section_phen_comma}){0,3}:${ipv4_regex_inipv6})|:))|((${ipv6_one_section_phen_comma}:){1}(((:${ipv6_one_section_phen_comma}){1,6})|((:${ipv6_one_section_phen_comma}){0,4}:${ipv4_regex_inipv6})|:))|(:(((:${ipv6_one_section_phen_comma}){1,7})|((:${ipv6_one_section_phen_comma}){0,5}:${ipv4_regex_inipv6})|:)))(%.+)?\]($port_regex)?\s*$" 	
    $ipv4_regex_findhpilo="^\s*${ipv4_one_section_phen_comma_dot_findhpilo}(\.${ipv4_one_section_phen_comma_dot_findhpilo}){0,3}($port_regex)?\s*$"
  		
    if ($Range.GetType().Name -eq 'String')
    {
        if(($range -match $ipv4_regex_findhpilo) -and (4 -ge (Get-IPv4-Dot-Num -strIP  $range)))
        {
            $InputIPv4Array += $Range            
            $validformat = $true
        }
        elseif($range -match $ipv6_regex_findhpilo -or $range -match $ipv6_regex_findhpilo_with_bra)
        {
            if($range.contains(']') -and $range.Split(']')[0].Replace('[','').Trim() -match $ipv4_regex_findhpilo)  #exclude [ipv4] and [ipv4]:port
            {
			   $validformat = $false
               throw $(Get-Message('MSG_INVALID_RANGE'))
            }
            else
            {
               $InputIPv6Array += $Range            
               $validformat = $true
            }
        }
        else
        {
			#Write-Error $(Get-Message('MSG_INVALID_RANGE'))
            $validformat = $false
            throw $(Get-Message('MSG_INVALID_RANGE'))
        }	
        
    }
	elseif($Range.GetType().Name -eq 'Object[]')
    {
        $hasvalidinput=$false
        foreach($r in $Range)
        {            
            if(($r -match $ipv4_regex_findhpilo)  -and (4 -ge (Get-IPv4-Dot-Num -strIP  $r)) )
            {
                $InputIPv4Array += $r                
                $hasvalidinput=$true
            }
            elseif($r -match $ipv6_regex_findhpilo -or $r -match $ipv6_regex_findhpilo_with_bra)
            {
                if($r.contains(']') -and $r.Split(']')[0].Replace('[','').Trim() -match $ipv4_regex_findhpilo) #exclude [ipv4] and [ipv4]:port
                {
                   Write-Warning $([string]::Format($(Get-Message('MSG_INVALID_PARAMETER')) ,$r))           
                }
                else
                {
                   $InputIPv6Array += $r
                   $hasvalidinput=$true
                }
            }
            else
            {
                Write-Warning $([string]::Format($(Get-Message('MSG_INVALID_PARAMETER')) ,$r))           
            }                    
        }
        $validformat = $hasvalidinput        
    }
    else
    {
           $validformat = $false
           throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Range.GetType().Name, 'Range'))
    }
    
    if($null -ne $Timeout){
        if(($Timeout -match "^\s*[1-9][0-9]*\s*$") -ne $true){ 		
            $validformat = $false
            throw $(Get-Message('MSG_INVALID_TIMEOUT'))
        }
    }
	
    if($InputIPv4Array.Length -gt 0)
    {
        #$IPv4Array = New-Object 'object[,]' $InputIPv4Array.Length,4
        $IPv4Array = New-Object System.Collections.ArrayList              
        foreach($inputIP in $InputIPv4Array)
        {
           if($inputIP.contains(':'))
           {
              $returnip = Complete-IPv4 -strIP $inputIP.Split(':')[0].Trim()
              $returnip = $returnip + ':' + $inputIP.Split(':')[1].Trim()      
           }
           else
           {
              $returnip = Complete-IPv4 -strIP $inputIP
           }
           $x = $IPv4Array.Add($returnip)
        }
    }

    if($InputIPv6Array.Length -gt 0)
    {
        #$IPv6Array = New-Object'object[,]' $InputIPv6Array.Length,11
        $IPv6Array = New-Object System.Collections.ArrayList        
        foreach($inputIP in $InputIPv6Array)
        { 
            if($inputIP.contains(']')) #[ipv6] and [ipv6]:port
            {
               $returnip = Complete-IPv6 -strIP $inputIP.Split(']')[0].Replace('[','').Trim()
               $returnip = '[' + $returnip + ']' + $inputIP.Split(']')[1].Trim()
            }
            else #ipv6 without [] nor port
            {
               $returnip = Complete-IPv6 -strIP $inputIP 
               $returnip = '[' + $returnip + ']'
            }
            $x = $IPv6Array.Add($returnip)
        }
    }   

	
	if($validformat)
	{	
		Write-Warning $(Get-Message('MSG_FIND_LONGTIME'))
        foreach($ipv4 in $IPv4Array)
        { 
            if($ipv4.contains(':')) #contains port
            {
               $retarray = Get-IPArrayFromString -stringIP $ipv4.Split(':')[0].Trim() -IPType 'IPv4'
               foreach($oneip in $retarray)
               {
                  $x = $ipToPing.Add($oneip + ':' + $ipv4.Split(':')[1].Trim())
               }                 
            }
            else
            {
               $retarray = Get-IPArrayFromString -stringIP $ipv4 -IPType 'IPv4'
               foreach($oneip in $retarray)
               {
                  $x = $ipToPing.Add($oneip)
               }  
            }                  
        }
				
        foreach($ipv6 in $IPv6Array) #all ipv6 has been changed to [ipv6] or [ipv6]:port
        { 
           $retarray = Get-IPv6FromString -stringIP $ipv6.Split(']')[0].Replace('[','').Trim() 
           foreach($oneip in $retarray)
           {
              $x = $ipToPing.Add('[' + $oneip + ']' + $ipv6.Split(']')[1].Trim())
           }                           
        }		
		  
        $rstList = @()
		$ThreadPipes = @()
		$poolsize = (@($ipToPing.Count, 256) | Measure-Object -Minimum).Minimum
		if($poolsize -eq 0)
		{
			$poolsize = 1
		}
		Write-Verbose -Message $([string]::Format($(Get-Message('MSG_USING_THREADS_FIND')) ,$poolsize))
		$thispool = Create-ThreadPool $poolsize
		$t = {
			    Param($aComp, $aComp2, $timeout,$RM)

                Function Get-Message
                {
                    Param
                    (
                        [Parameter(Mandatory=$true)][String]$MsgID
                    )
                     #only these strings are used in the two script blocks
                    $LocalizedStrings=@{
	                    'MSG_SENDING_TO'='Sending to {0}'
	                    'MSG_FAIL_HOSTNAME'='DNS name translation not available for {0} - Host name left blank.'
	                    'MSG_FAIL_IPADDRESS'='Invalid Hostname: IP Address translation not available for hostname {0}.'
	                    'MSG_PING'='Pinging {0}'
	                    'MSG_PING_FAIL'='No system responds at {0}'
	                    'MSG_FIND_NO_SOURCE'='No HPE Redfish source at {0}'
	                    }
                    $Message = ''
                    try
                    {
                        $Message = $RM.GetString($MsgID)
                        if($null -eq $Message)
                        {
                            $Message = $LocalizedStrings[$MsgID]
                        }
                    }
                    catch
                    {
                        #throw $_
		                $Message = $LocalizedStrings[$MsgID]
                    }

                    if($null -eq $Message)
                    {
		                #or unknown
                        $Message = 'Fail to get the message'
                    }
                    return $Message
                }

                function Invoke-FindHpeRedfishHttpWebRequest
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
                        $CmdletName
                    )
                    [System.Net.ServicePointManager]::SecurityProtocol = @([System.Net.SecurityProtocolType]::Ssl3,[System.Net.SecurityProtocolType]::Tls,[System.Net.SecurityProtocolType]::Tls12)
    
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
                    $httpWebRequest.Headers.Add('X-Auth-Token',$Session.'X-Auth-Token')
                    $httpWebRequest.Headers.Add('Odata-version','4.0')
                    $httpWebRequest.ServerCertificateValidationCallback = {$true}
       
                    try
                    {
                        [System.Net.WebResponse] $resp = $httpWebRequest.GetResponse()
                        #return $resp
                        $rs = $resp.GetResponseStream();
                        [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
                        $results = ''
                        [string]$results = $sr.ReadToEnd();
                        $resp.Close()
                        $rs.Close()
                        $sr.Close()
                        $finalResult = ConvertFrom-Json $results
                        return $finalResult
                    }
                    catch
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
                                if($null -ne $webResponse)
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

			    $ping    = New-Object -TypeName System.Net.NetworkInformation.Ping
			    $options = New-Object -TypeName System.Net.NetworkInformation.PingOptions -ArgumentList (20, $false)
			    $bytes   =  0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb, 0xdb
			    $retobj = New-Object -TypeName PSObject   
			    try
			    {			
				    $pingres = $ping.Send($aComp2, $timeout, [Byte[]]$bytes, $options )
				    if ($pingres.Status -eq 'Success') 
                    {
					    $rstAddr = $pingres.Address.IPAddressToString
                        $inUri = "https://$aComp/redfish/v1/"
                        $inMethod = "GET"
                        $inCmdletName = "Find-HPERedfish"

                        $rstobj = Invoke-FindHpeRedfishHttpWebRequest -Uri $inUri -Method $inMethod -CmdletName $inCmdletName
								  
					    try 
					    {   
                            $rstobj |   Add-Member NoteProperty IP  $rstAddr 
						    $rstobj |   Add-Member NoteProperty HOSTNAME $null
						    try
						    {
							    $dns = [System.Net.Dns]::GetHostEntry($rstAddr)
							    $rstobj.Hostname = $dns.Hostname
						    }
						    catch
						    {
							    $retobj | Add-Member NoteProperty errormsg $([string]::Format($(Get-Message('MSG_FAIL_HOSTNAME')), $rstAddr))
						    }
						    if(($rstobj.'@odata.type').indexOf('ServiceRoot.') -ne -1) 
                            {
							    $retobj | Add-Member NoteProperty data $rstobj
						    }
					    }
					    catch 
					    {
						    $retobj | Add-Member NoteProperty errormsg $([string]::Format($(Get-Message('MSG_FIND_NO_SOURCE')), $rstAddr))
					    }
				    }
				    else
				    {
					    $retobj | Add-Member NoteProperty errormsg  $([string]::Format($(Get-Message('MSG_PING_FAIL')), $aComp2))
				    }
			    }
			    catch
			    {
				    $retobj | Add-Member NoteProperty errormsg  $([string]::Format($(Get-Message('MSG_PING_FAIL')), $aComp2))
			    }
			    return $retobj
        } 
		#end of $t scriptblock
            
		foreach ($comp in $ipToPing) {
			Write-Verbose -Message $([string]::Format($(Get-Message('MSG_PING')) ,$comp))
            $comp2=$comp
            if($comp -match $ipv4_regex_findhpilo -and $comp.contains(':')) #ipv4:port
            {
               $comp2 = $comp.Split(':')[0].Trim()
            }
            elseif($comp -match $ipv6_regex_findhpilo_with_bra) #all ipv6 have been added [] after completing address
            {
               if($comp.contains(']:')) #[ipv6]:port
               {
                 $comp2 = $comp.Split(']')[0].Replace('[','').Trim()
               }
               else #[ipv6]
               {
                 $comp2 = $comp.Replace('[','').Replace(']','').Trim()
               }
            }
            
			$ThreadPipes += Start-ThreadScriptBlock -ThreadPool $thispool -ScriptBlock $t -Parameters $comp,$comp2, $Timeout, $RM
		}

		#this waits for and collects the output of all of the scriptblock pipelines - using showprogress for verbose
		if ($VerbosePreference -eq 'Continue') {
			$rstList = Get-ThreadPipelines -Pipelines $ThreadPipes -ShowProgress
		}
		else {
			$rstList = Get-ThreadPipelines -Pipelines $ThreadPipes
		}
		$thispool.Close()
		$thispool.Dispose()
        foreach($ilo in $rstList)
        {
			if($null -ne $ilo.errormsg)
            {
                Write-Verbose $ilo.errormsg
            }
            
            if($null -ne $ilo.data)
            {
                $ilo.data
            }
        }  
        
    }    
    else{
        #Write-Error $(Get-Message('MSG_INVALID_USE'))
        throw $(Get-Message('MSG_INVALID_USE'))
    }
}

function Format-HPERedfishDir
{
<#
.SYNOPSIS
Displays HPE Redfish data in directory format.

.DESCRIPTION
Takes the node array returned by Get-HPERedfishDir and displays each node as a directory.

.PARAMETER NodeArray
The array created by Get-HPERedfishDir, containing a collection of Redfish API nodes in an array.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER AutoSize
Switch parameter that turns the autosize feature on when true.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.INPUTS
System.String
You can pipe the NodeArray obtained from Get-HPERedfishDir to Format-HPERedfishDir.

.OUTPUTS
System.Management.Automation.PSCustomObject or System.Object[]
Format-HPERedfishDir returns a PSCustomObject or an array of PSCustomObject if Recurse parameter is set to true.

.EXAMPLE
PS C:\> $odataid = '/redfish/v1/sessions/'

PS C:\> $nodeArray = Get-HPERedfishDir -Session $s -Odataid $odataid -Recurse

PS C:\> Format-HPERedfishDir -NodeArray $NodeArray

Location: https://192.184.217.212/redfish/v1/
Link: /redfish/v1/Sessions/

Type           Name                Value                                                            
----           ----                -----                                                            
String         @odata.context      /redfish/v1/$metadata#Sessions                                   
String         @odata.id           /redfish/v1/Sessions/                                            
String         @odata.type         #SessionCollection.SessionCollection                             
String         Description         Manager User Sessions                                            
Object[]       Items               {@{@odata.context=/redfish/v1/$metadata#SessionService/Session...
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
PSCustomObject links               @{Member=System.Object[]; self=}                                 
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
               @odata.id           /redfish/v1/Sessions/
Object[]       Members             {@{@odata.id=/redfish/v1/SessionService/Sessions/admin55dd017b...
Int32          Members@odata.count 1                                                                
String         MemberType          Session.1                                                        
String         Name                Sessions                                                         
PSCustomObject Oem                 @{Hp=}                                                           
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
Int32          Total               1                                                                
String         Type                Collection.1.0.0                                                 


Link: /redfish/v1/SessionService/Sessions/admin55dd017b39999998/

Type           Name           Value                                                        
----           ----           -----                                                        
String         @odata.context /redfish/v1/$metadata#SessionService/Sessions/Members/$entity
String         @odata.id      /redfish/v1/SessionService/Sessions/admin55dd017b39999998/   
String         @odata.type    #Session.1.0.0.Session                                       
String         Description    Manager User Session                                         
String         Id             admin55dd017b39999998                                        
PSCustomObject links          @{self=}                                                     
               @odata.id      /redfish/v1/SessionService/Sessions/admin55dd017b39999998/       
String         Name           User Session                                                 
PSCustomObject Oem            @{Hp=}                                                       
String         Type           Session.1.0.0                                                
String         UserName       admin                                                        


Link: /redfish/v1/Sessions/

Type           Name                Value                                                            
----           ----                -----                                                            
String         @odata.context      /redfish/v1/$metadata#Sessions                                   
String         @odata.id           /redfish/v1/Sessions/                                            
String         @odata.type         #SessionCollection.SessionCollection                             
String         Description         Manager User Sessions                                            
Object[]       Items               {@{@odata.context=/redfish/v1/$metadata#SessionService/Session...
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
PSCustomObject links               @{Member=System.Object[]; self=}                                 
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
               @odata.id           /redfish/v1/Sessions/                                                
Object[]       Members             {@{@odata.id=/redfish/v1/SessionService/Sessions/admin55dd017b...
Int32          Members@odata.count 1                                                                
String         MemberType          Session.1                                                        
String         Name                Sessions                                                         
PSCustomObject Oem                 @{Hp=}                                                           
               @odata.id           /redfish/v1/SessionService/Sessions/admin55dd017b39999998/           
Int32          Total               1                                                                
String         Type                Collection.1.0.0                                                 



This example shows the formatted node array obtained from odataid for sessions.The list of Odataid links in a property are listed below the property name and value

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        #($NodeArray, $Session, $AutoSize)
        [System.Object[]]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $NodeArray,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $AutoSize
    )
    BEGIN 
    {
        function Find-ODataId($nodeForFindOdataid)
        {
            if($nodeForFindOdataid.GetType().ToString() -eq 'System.Object[]')
            {
                foreach($obj in $nodeForFindOdataid)
                {
                    $obj | Get-Member -type NoteProperty | ForEach-Object {
                        $name = $_.Name ;
                        $value = $obj."$($_.Name)"
                        if($name -eq '@odata.id')
                        {
                            foreach($v in $value)
                            { 
                                $NodeProperties = New-Object System.Object
                                $NodeProperties | Add-Member -type NoteProperty -name Type -value $null
                                $NodeProperties | Add-Member -type NoteProperty -name Name -value $name
                                $NodeProperties | Add-Member -type NoteProperty -name Value -value $v
                                $Global:DirValues += $NodeProperties
                            }
                        }

                        else
                        {
                            if($null -ne $value -and $value.GetType().ToString() -eq 'System.Object[]')
                            {
                                $arrHasNonNullElements = $false
                                foreach($i in $value)
                                {
                                    if($null -ne $i)
                                    {
                                        $arrHasNonNullElements = $true
                                        break
                                    }
                                }
                                if($arrHasNonNullElements -eq $false)
                                {
                                    continue
                                }
                            }
                    
                            if($null -ne $value -and ($value |Get-Member).MemberType -contains 'NoteProperty')
                            {
                                Find-ODataId -nodeForFindOdataid $value
                            }
                        }
                    }
                }
            }
            else
            {
                $nodeForFindOdataid | Get-Member -type NoteProperty | ForEach-Object {
                    $name = $_.Name ;
                    $value = $nodeForFindOdataid."$($_.Name)"
                    if($name -eq '@odata.id')
                    {
                        foreach($v in $value)
                        { 
                            $NodeProperties = New-Object System.Object
                            $NodeProperties | Add-Member -type NoteProperty -name Type -value $null
                            $NodeProperties | Add-Member -type NoteProperty -name Name -value $name
                            $NodeProperties | Add-Member -type NoteProperty -name Value -value $v
                            $Global:DirValues += $NodeProperties
                        }
                    }

                    else
                    {
                        if($null -ne $value -and $value.GetType().ToString() -eq 'System.Object[]')
                        {
                            $arrHasNonNullElements = $false
                            foreach($i in $value)
                            {
                                if($null -ne $i)
                                {
                                    $arrHasNonNullElements = $true
                                    break
                                }
                            }
                            if($arrHasNonNullElements -eq $false)
                            {
                                continue
                            }
                        }
                    
                        if($null -ne $value -and ($value |Get-Member).MemberType -contains 'NoteProperty')
                        {
                            Find-ODataId -nodeForFindOdataid $value
                        }
                    }
                }
            }
        }

        Function Format-Node($nodeForFormat, $odataid)
        {
            "Link: $odataid"
            $Global:DirValues = @()
            $nodeForFormat | get-member -type NoteProperty | foreach-object {
                $name = $_.Name ; 
                $value = $nodeForFormat."$($_.Name)"
                
                if($null -ne $value)
                {
                    $NodeProperties = New-Object System.Object
                    $NodeProperties | Add-Member -type NoteProperty -name Type -value $value.GetType().name
                    $NodeProperties | Add-Member -type NoteProperty -name Name -value $name
                    $NodeProperties | Add-Member -type NoteProperty -name Value -value $value
                    $Global:DirValues += $NodeProperties
                }
                else
                {
                    $NodeProperties = New-Object System.Object
                    $NodeProperties | Add-Member -type NoteProperty -name Type -value 'Null'
                    $NodeProperties | Add-Member -type NoteProperty -name Name -value $name
                    $NodeProperties | Add-Member -type NoteProperty -name Value -value $value
                    $Global:DirValues += $NodeProperties
                }

                if($null -ne $value -and $value.GetType().ToString() -eq 'System.Object[]')
                {
                    $arrHasNonNullElements = $false
                    foreach($i in $value)
                    {
                        if($null -ne $i)
                        {
                            $arrHasNonNullElements = $true
                            break
                        }
                    }
                    if($arrHasNonNullElements -eq $false)
                    {
                        continue
                    }
                }
                if($null -ne $value -and ($value |Get-Member).MemberType -contains 'NoteProperty')
                {
                    Find-ODataId -nodeForFindODataId $value
                }
            }
            if($AutoSize -eq $true)
            {
                $Global:DirValues | Format-Table -AutoSize
            }
            else
            {
                $Global:DirValues | Format-Table
            }
        }
        if(!($null -eq $session.Location -or $session.Location -eq ''))
        {
            "$(Get-Message('MSG_FORMATDIR_LOCATION')): $($Session.RootUri)"
        }
    }
    PROCESS
    {
        if($NodeArray.GetType().ToString() -match 'PScustomobject')
        {
            $odataid1 = $NodeArray.'@odata.id'
            Format-Node -nodeForFormat $NodeArray -Odataid $odataid1
        }
        elseif($NodeArray.GetType().ToString() -eq 'System.Object[]')
        {
            foreach($node1 in $NodeArray)
            {
                if($node1.GetType().ToString() -match 'PSCustomObject')
                {
                    $odataid1 = $node1.'@odata.id'
                    if(-not ($odataid1 -ne "" -and $null -ne $odataid1))
                    {
                        $odataid1 = $node1.links.self.href
                        $odataid1 = $odataid1 -replace '/rest/v1','/redfish/v1'
                    }
                    Format-Node -nodeForFormat $node1 -Odataid $odataid1
                }
                else
                {
                    throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $node1.GetType().Name, 'NodeArray'))
                }
            }
        }
    }
    END
    {

    }
}

function Get-HPERedfishData
{
<#
.SYNOPSIS
Retrieves the data and the schema of the data properties for specified odataid.

.DESCRIPTION
Retrieves the data and the schema of the data properties for data specified by given odataid. This cmdlet returns two sets of values - data and schema details. The schema details include information like if the data item is readonly, possible values in enum, enum values' descriptions and datatypes of allowed value.

.PARAMETER Odataid
Odataid of the data for which data and properties are to be retrieved.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the Odataid to Get-HPERedfishData.

.OUTPUTS
Two objects of type System.Management.Automation.PSCustomObject or one object of System.Object[]
Get-HPERedfishData returns two object of type PSObject. First object has the retrieved data and the second has schema properties in the form of System.Collections.Hashtable. If you use one variable for returned object, then the variable will be an array with first term as the data PSObject and second element as the property list in System.Collections.Hashtable

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.


.EXAMPLE
PS C:\> $data,$prop = Get-HPERedfishData -Odataid /redfish/v1/systems/1/ -Session $s

PS C:\> $data


@odata.context   : /redfish/v1/$metadata#Systems/Members/$entity
@odata.id        : /redfish/v1/Systems/1/
@odata.type      : #ComputerSystem.1.1.0.ComputerSystem
Actions          : @{#ComputerSystem.Reset=}
AssetTag         : Test111
BiosVersion      : P89 v2.00 (06/07/2015)
Boot             : @{BootSourceOverrideEnabled=Disabled; BootSourceOverrideTarget=None; 
                   UefiTargetBootSourceOverride=None}
Description      : Computer System View
HostName         : TestServerName
Id               : 1
IndicatorLED     : Off
Links            : @{Chassis=System.Object[]; ManagedBy=System.Object[]}
LogServices      : @{@odata.id=/redfish/v1/Systems/1/LogServices/}
Manufacturer     : HPE
MemorySummary    : @{Status=; TotalSystemMemoryGiB=8}
Model            : ProLiant DL380 Gen9
Name             : Computer System
Oem              : @{Hp=}
PowerState       : On
ProcessorSummary : @{Count=2; Model=Intel(R) Xeon(R) CPU E5-2683 v3 @ 2.00GHz; Status=}
Processors       : @{@odata.id=/redfish/v1/Systems/1/Processors/}
SKU              : 501101-001
SerialNumber     : LCHAS01RJ5Y00Z
Status           : @{Health=Warning; State=Enabled}
SystemType       : Physical
UUID             : 31313035-3130-434C-4841-533031524A35




PS C:\Poseidon_SVN\New_Strategy\HPERedfish\trunk\HPERedfishCmdlets> $prop

Name                           Value                                                                            
----                           -----                                                                            
Count                          @{Schema_Description=The number of processors in the system.; Schema_Type=Syst...
UUID                           @{Schema_Description=The universal unique identifier for this system.; Schema_...
ResetType@Redfish.Allowable... @{Schema_Description=The supported values for the ResetType parameter.; Schema...
Description                    @{Schema_Type=object}                                                            
TotalSystemMemoryGiB           @{Schema_Description=This is the total amount of memory in the system measured...
IndicatorLED                   @{Schema_Description=The state of the indicator LED.; Schema_AllowedValue=Syst...
    .
    .
    .
Manufacturer                   @{Schema_Description=The manufacturer or OEM of this system.; Schema_Type=Syst...
IntelligentProvisioningLoca... @{Schema_Description= Location string of Intelligent Provisioning in Firmware ...
Name                           @{Schema_Type=object}                                                            
PushType@Redfish.AllowableV... @{Schema_Description=The supported values for the PushType parameter.; Schema_...
VersionString                  @{Schema_Description=The version string of the firmware. This value might be n...
BiosVersion                    @{Schema_Description=The version of the system BIOS or primary system firmware...




PS C:\> $prop.IndicatorLED


Schema_Description      : The state of the indicator LED.
Schema_AllowedValue     : {Unknown, Lit, Blinking, Off}
schema_enumDescriptions : @{Unknown=The state of the Indicator LED cannot be determined.; Lit=The Indicator LED is 
                          lit.; Blinking=The Indicator LED is blinking.; Off=The Indicator LED is off.}
Schema_Type             : {string, null}
Schema_ReadOnly         : False

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }

    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
    
        $data = Get-HPERedfishDataRaw -Odataid $odataid -Session $Session
        $schema = Get-HPERedfishSchema -odatatype $data.'@odata.type' -Session $Session
        $DictionaryOfSchemas = [System.Collections.Hashtable]@{}

        $data, $props = Get-HPERedfishDataPropRecurse -Data $data -Schema $schema -Session $Session -DictionaryOfSchemas $DictionaryOfSchemas
        return $data, $props
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishDataRaw
{
<#
.SYNOPSIS
Retrieves data for provided Odataid.

.DESCRIPTION
Retrieves the HPE Redfish data returned from the source pointed to by the Odataid in PSObject format.
This cmdlet uses the session information to connect to the Redfish data source and retrieves the data to the user in PSObject format. Session object with ‘RootUri’, ‘X-Auth-Token’ and ‘Location’ information of the session must be provided for using sessions to retrieve data.

.PARAMETER Odataid
Specifies the value of Odataid of Redfish data source to be retrieved. This is concatenated with the root URI (obtained from session parameter) to get the URI to where the WebRequest has to be sent.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.PARAMETER OutputType
Specifies the format of required output. Possible values are PSObject, String and ByteArray. Default value is PSObject. If you need to download a binary file from the interface, then use 'ByteArray' as OutputType. The returned value can be stored into a file when the Path parameter is used.

.PARAMETER Path
Specifies the location of the file where the output of Get-HPERedfishDataRaw has to be saved.

.PARAMETER Force
Forces this cmdlet to create an item that writes over an existing read-only item. This parameter will create the file even if the directories in the mentioned Path do not exist. The directories will be created by PowerShell when the Force parameter is used.

.INPUTS
System.String
You can pipe the Odataid parameter to Get-HPERedfishDataRaw.

.OUTPUTS
System.Management.Automation.PSCustomObject
Get-HPERedfishDataRaw returns a PSCustomObject that has the retrieved data.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $sys = Get-HPERedfishDataRaw -Odataid /redfish/v1/systems/1/ -Session $s

PS C:\> $sys


@odata.context   : /redfish/v1/$metadata#Systems/Members/$entity
@odata.id        : /redfish/v1/Systems/1/
@odata.type      : #ComputerSystem.1.1.0.ComputerSystem
Actions          : @{#ComputerSystem.Reset=}
AssetTag         : Test111
BiosVersion      : P89 v2.00 (06/07/2015)
Boot             : @{BootSourceOverrideEnabled=Disabled; BootSourceOverrideTarget=None; 
                   UefiTargetBootSourceOverride=None}
Description      : Computer System View
HostName         : 
Id               : 1
IndicatorLED     : Off
Links            : @{Chassis=System.Object[]; ManagedBy=System.Object[]}
LogServices      : @{@odata.id=/redfish/v1/Systems/1/LogServices/}
Manufacturer     : HPE
MemorySummary    : @{Status=; TotalSystemMemoryGiB=8}
Model            : ProLiant DL380 Gen9
Name             : Computer System
Oem              : @{Hp=}
PowerState       : On
ProcessorSummary : @{Count=2; Model=Intel(R) Xeon(R) CPU E5-2683 v3 @ 2.00GHz; Status=}
Processors       : @{@odata.id=/redfish/v1/Systems/1/Processors/}
SKU              : 501101-001
SerialNumber     : LASDFGHRJ5Y00Z
Status           : @{Health=Warning; State=Enabled}
SystemType       : Physical
UUID             : 31313035-3130-434C-4841-533031524A35

This example retrieves system data.

.EXAMPLE

PS C:\> $sessions = Get-HPERedfishDataRaw -Odataid '/redfish/v1/sessionservice/Sessions/' -Session $session
$mysession = Get-HPERedfishDataRaw -Odataid $sessions.Oem.Hp.Links.MySession.'@odata.id' -Session $session
if($mysession.Oem.Hp.MySession -eq $true)
{
    $mysession
    $mysession.oem.hp
}


@odata.context : /redfish/v1/$metadata#SessionService/Sessions/Members/$entity
@odata.id      : /redfish/v1/SessionService/Sessions/admin56ba7c4648f5c28f/
@odata.type    : #Session.1.0.0.Session
Description    : Manager User Session
Id             : admin56ba7c4648f5c28f
Name           : User Session
Oem            : @{Hp=}
UserName       : admin

@odata.type           : #HpiLOSession.1.0.0.HpiLOSession
AccessTime            : 2016-02-10T00:07:16Z
LoginTime             : 2016-02-09T23:54:46Z
MySession             : True
Privileges            : @{LoginPriv=True; RemoteConsolePriv=True; UserConfigPriv=True; VirtualMediaPriv=True; 
                        VirtualPowerAndResetPriv=True; iLOConfigPriv=True}
UserAccount           : admin
UserDistinguishedName : 
UserExpires           : 2016-02-10T00:12:16Z
UserIP                : 16.100.237.28
UserTag               : Web UI
UserType              : Local

This example shows the process to retrieve current user session.


.EXAMPLE
PS C:\> $biosData = Get-HPERedfishDataRaw -Odataid '/redfish/v1/registries/' -Session $session
        foreach($reg in $registries.items)
        {
            if($reg.Schema -eq $biosAttReg)
            {
                $attRegLoc = $reg.Location|Where-Object{$_.Language -eq 'en'}|%{$_.uri.extref}
                break
            }
        }
        $attReg = Get-HPERedfishDataRaw -Odataid $attRegLoc -Session $session
        $attReg.RegistryEntries.Dependencies


The example shows retrieval of Dependencies of BIOS settings. The BIOS attribute registry value is present in $biosAttReg. The English version of the registry is retrieved.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, Position=1)]
        $Session,
        
        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication,

        [System.String]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, Position=2)]
        [ValidateSet("PSObject","String","ByteArray")]
        $OutputType = "PSObject",
        
        [System.String]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, Position=3)]
        $Path,
        
        [switch]
        [parameter(Mandatory=$false)]
        $Force
    )
    # $resp is http web response object with headers
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        try
        {
            $rootURI = $Session.RootUri
            if($null -eq $rootURI)
            {
                 throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Session.GetType().Name, 'Session'))
            }

            $initUri = New-Object System.Uri -ArgumentList @([URI]$Session.RootUri)
            $baseUri = $initUri.Scheme + '://' + $initUri.Authority  # 'Authority' has the port number if provided by the user (along with the IP or hostname)

            $uri = (New-Object System.Uri -ArgumentList @([URI]$baseUri, $Odataid)).ToString()
            
            $Method = 'GET'
            $cmdletName = 'Get-HPRESTDataRaw'

            $parameters = @{}
            $parameters.Add("Uri", $uri)
            $parameters.Add("Method", $Method)
            $parameters.Add("CmdletName", $CmdletName)
            $parameters.Add("Session", $Session)
            
            if($PSBoundParameters.ContainsKey("DisableCertificateAuthentication"))
            { $parameters.Add("DisableCertificateAuthentication", $DisableCertificateAuthentication) }

			$resp = Invoke-HttpWebRequest @parameters
			
            $rs = $resp.GetResponseStream();
            
            if($OutputType -eq "PSObject")
            {
                [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
                $results = ''
                [string]$results = $sr.ReadToEnd();
				$sr.Close()
                $rs.Close()
				$resp.Close()        

                $finalResult = Convert-JsonToPSObject $results
            }
            elseif($OutputType -eq "String")
            {
                [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
                $results = ''
                [string]$results = $sr.ReadToEnd();
				$sr.Close()
                $rs.Close()
				$resp.Close()

                $finalResult = $results
            }
            elseif($OutputType -eq "ByteArray")
            {

                [System.IO.BinaryReader] $br = New-Object System.IO.BinaryReader -argumentList $rs #@($rs, [System.Text.Encoding]::UTF8)
                $Buffer = New-Object Byte[] 10240

                if($PSBoundParameters.ContainsKey('Path') -eq $false)
                {
                    try
                    {
                        $memStream = New-Object System.IO.MemoryStream
                        Do {
                            $BytesRead = $br.Read($Buffer, 0, $Buffer.Length)
                            $memStream.Write($Buffer,0,$BytesRead)    
                        } While ($BytesRead -gt 0)

                        $finalResult = $memStream.ToArray()
                    }
                    finally
                    {
                        $br.Close()
                        $rs.Close()
				        $resp.Close()
                        $memStream.Close()
                        $memStream.Dispose()
                    }

                    return $finalResult
                }
                else
                {
                    if(!(Test-Path $Path))
                    {
                        if($Force.IsPresent){ New-Item -Path $Path -ItemType File -Force }
                        else { New-Item -Path $Path -ItemType File}
                    }

                    try
                    {
                        $outfile = [System.IO.FileStream]::New($path, [System.IO.FileMode]::OpenOrCreate)
                        do
                        {
                            $BytesRead = $br.Read($Buffer, 0, $buffer.Length)
                            $outfile.Write($Buffer, 0, $BytesRead)
                        }while($BytesRead -ne 0);

                    }
                    finally
                    {
                        $outfile.close()
                    }
			        
                    return;
                }
            }
        }
        finally
        {
            if ($null -ne $resp -and $resp -is [System.IDisposable]){$resp.Dispose()}
            if ($null -ne $rs -and $rs -is [System.IDisposable]){$rs.Dispose()}
            if ($null -ne $sr -and $sr -is [System.IDisposable]){$sr.Dispose()}
            if ($null -ne $memStream -and $memStream -is [System.IDisposable]) {$memStream.Dispose()}
        }

        if($PSBoundParameters.ContainsKey('Path') -eq $false)
        {
           return $finalResult
        }
        else
        {
            if(!(Test-Path $Path))
            {
                if($Force.IsPresent){ New-Item -Path $Path -ItemType File -Force }
                else { New-Item -Path $Path -ItemType File}
            }
            if($Force.IsPresent){ Set-Content -Path $Path -Value $finalResult -Force }
            else { Set-Content -Path $Path -Value $finalResult}
        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishDir
{
<#
.SYNOPSIS
Gets HPE Redfish data and stores into a node array.

.DESCRIPTION
Get-HPERedfishDir cmdlet gets the data at location specified by the 'Odataid' parameter and stores it in a node array. If Recurse parameter is set, the cmdlet will iterate to every odata id stored within the first node and every node thereafter storing each node into a node array.

.PARAMETER Odataid
Specifies the value of Odataid of Redfish data source to be retrieved. This is concatenated with the root URI (obtained from session parameter) to get the URI to retrieve the Redfish data.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER Recurse
Switch parameter that turns recursion on if true.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the Odataid to Get-HPERedfishDir.

.OUTPUTS
System.Object[]
Get-HPERedfishDir returns an array of PSObject objects that contains the data at the location specified by the Odataid parameter and by odataids in that data if Recurse parameter is set to true.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.Example
PS C:\> $NodeArray = Get-HPERedfishDir -Session $s -Odataid $odataid 

PS C:\> $NodeArray 


Description : Manager User Sessions
Items       : {@{Description=Manager User Session; Name=User Session; Oem=; Type=Session.0.9.5; UserName=admin; links=}, @{Description=Manager User Session; Name=User Session; Oem=; 
              Type=Session.0.9.5; UserName=admin; links=}}
MemberType  : Session.0
Name        : Sessions
Oem         : @{Hp=}
Total       : 2
Type        : Collection.0.9.5
links       : @{Member=System.Object[]; self=}

This example shows the basic execution where there is no recursion. Only the data at the specified Odataid is returned.

.Example
PS C:\> $NodeArray = Get-HPERedfishDir -Session $s -Odataid /redfish/v1/sessionservice/sessions/ -Recurse

PS C:\> $NodeArray


@odata.context      : /redfish/v1/$metadata#Sessions
@odata.id           : /redfish/v1/SessionService/Sessions/
@odata.type         : #SessionCollection.SessionCollection
Description         : Manager User Sessions
Members             : {@{@odata.id=/redfish/v1/SessionService/Sessions/admin56baa83eb16872af/}, 
                      @{@odata.id=/redfish/v1/SessionService/Sessions/admin56baa870dfbe76c8/}}
Members@odata.count : 2
Name                : Sessions
Oem                 : @{Hp=}

@odata.context : /redfish/v1/$metadata#SessionService/Sessions/Members/$entity
@odata.id      : /redfish/v1/SessionService/Sessions/admin56baa83eb16872af/
@odata.type    : #Session.1.0.0.Session
Description    : Manager User Session
Id             : admin56baa83eb16872af
Name           : User Session
Oem            : @{Hp=}
UserName       : admin

@odata.context : /redfish/v1/$metadata#SessionService/Sessions/Members/$entity
@odata.id      : /redfish/v1/SessionService/Sessions/admin56baa870dfbe76c8/
@odata.type    : #Session.1.0.0.Session
Description    : Manager User Session
Id             : admin56baa870dfbe76c8
Name           : User Session
Oem            : @{Hp=}
UserName       : admin


This example shows a recursive execution of the cmdlet with the specified Recurse parameter. The second and the third PSObjects shown above are retrieved recursively using the odataid from the 'Members' property in the first object.


.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [Switch]
        [parameter(Mandatory=$false)]
        $Recurse,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
    
        $global:SeenOdataIds = [System.Collections.ArrayList]@() #The OdataIds of the already visited nodes.
        $global:NodeArr = @() #The Array of nodes to be returned.
                
        $fromInnerObject = 0
        $currOdataId = $Odataid
        function Find-OdataIds($node, $currodataid) #This function finds all the OdataIds in a node recursively and adds them to the $SeenOdataIds cmdlet, 
        {                          #adds the new node to the node array, and uses the new node to call the function again.
    
            if($null -eq $node -or ((($node | Get-Member).MemberType -contains 'NoteProperty') -eq $false))
            {
                return
            }

            #$node | Get-Member -type NoteProperty | foreach {
            $props = $node | Get-Member -MemberType NoteProperty
            if($fromInnerObject -eq 0)
            {
                $currOdataId = $node."@odata.id"
            }
            foreach($prop in $props)
            {
                $name = $prop.Name ;
                $value = $node."$($prop.Name)"
                if($null -eq $value)
                {
                    continue
                }

                if($value.GetType().ToString() -eq 'System.Object[]')
                {
                    $arrHasNonNullElements = $false
                    foreach($i in $value)
                    {
                        if($null -ne $i)
                        {
                            $arrHasNonNullElements = $true
                            break
                        }
                    }
                    if($arrHasNonNullElements -eq $false)
                    {
                        continue
                    }
                }

                if($name -eq '@odata.id')
                {
                    foreach($v in $value)
                    {
                        $ind = $v.IndexOf('#')
                        if($ind -ne -1 )
                        {
                            $v = $v.substring(0,$ind)
                        }
                        if($null -ne $v -and $Global:SeenOdataIds -notcontains $v.ToLower())
                        {
                            $currOdidSplit = $currOdataId -split '/'
                            $vSplit = $v -split '/'
                            $diffTreeFlag = $false
                            for($i=$currOdidSplit.length-2; $i-ge0; $i--)
                            {
                                if($vSplit[$i] -ne $currOdidSplit[$i])
                                {
                                    $diffTreeFlag = $true
                                    break
                                }
                            }
                            if($diffTreeFlag -eq $false)
                            {
                                try
                                {   
                                    if($v.StartsWith('/') -eq $false)
                                    {
                                        $v = '/'+$v
                                    }
                                    if($v.EndsWith('/') -eq $false)
                                    {
                                        $v = $v+'/'
                                    }
                                    if($null -ne $v -and $Global:SeenOdataIds -notcontains $v.ToLower())
                                    {
                                        Write-Verbose $v
                                        $newnode = Get-HPERedfishDataRaw -Odataid $v -Session $Session
                                        $global:SeenOdataIds += $v.ToLower()
                                        $global:NodeArr += $newnode

                                        if($recurse -eq $true)
                                        {
                                            Find-OdataIds $newnode -currodataid $v
                                        }
                                    }
                                }
                                catch
                                {
                                    Write-Error "$v`n$_"
                                }
                            }
                        }
                    }
                }
                elseif($null -ne $value -and $value.GetType().ToString() -eq 'System.Object[]')
                {
                    foreach($v in $value)
                    {
                        Find-OdataIds -node $v $currOdataId
                    }
                }
                elseif($null -ne $value -and ($value |Get-Member).MemberType -contains 'NoteProperty')
                {
                    $fromInnerObject = $fromInnerObject +1
                    Find-OdataIds -node $value -currodataid $currOdataId
                    $fromInnerObject = $fromInnerObject -1
                }
            }
        }


        if($recurse -ne $true)
        {
            try
            {
                $newnode = Get-HPERedfishDataRaw -Odataid $odataid -Session $Session
            }
            catch
            {
                Write-Error "$odataid`n$_"
            }
            $global:NodeArr+=$newnode
        }
        else
        {

            try
            {
                $newnode = Get-HPERedfishDataRaw -Odataid $odataid -Session $Session
            }
            catch
            {
                Write-Error "$odataid`n$_"
            }
            if($odataid.StartsWith('/') -eq $false)
            {
                $odataid = '/'+$odataid
            }
            if($odataid.EndsWith('/') -eq $false)
            {
                $odataid = $odataid+'/'
            }
            $global:SeenOdataIds += $Odataid.ToLower() 
            $global:NodeArr += $newnode
            Find-OdataIds $newnode -currodataid $Odataid
        }
        $ret = $global:NodeArr
        return $ret
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishMessage
{
<#
.SYNOPSIS
Retrieves message details from the MessageId returned from the API.

.DESCRIPTION
This cmdlet retrieves details of the API response messages specified by the MessageID parameter. This error message may be informational or warning message and not necessarily an error. The possible messages are specified in the Data Model Reference document. The MessageIds and required arguments are obtained in the returned objects by executing cmdlets like Set-HPERedfishData, Edit-HPERedfishData etc.

.PARAMETER MessageID
API response message object returned by executing cmdlets like Set-HPERedfishData and Edit-HPERedfishData.

.PARAMETER MessageArg
API response message arguments returned in the message from cmdlets like Set-HPERedfishData, Edit-HPERedfishData, etc. The MessageArg parameter has an array of arguments that provides parameter names and/or values relevant to the error/messages returned from cmdlet execution.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the MessageID parameter to Get-HPERedfishMessage.

.OUTPUTS
System.Management.Automation.PSCustomObject
Get-HPERedfishMessage returns a PSCustomObject that has the error details with Description, Mesage, Severity, Number of arguments to the message, parameter types and the resolution.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $LoginNameToModify = 'TimHorton'
PS C:\> $accounts = Get-HPERedfishDataRaw -Odataid '/redfish/v1/AccountService/Accounts/' -Session $s
PS C:\> $reqAccount = $null
        foreach($acc in $accounts.Members.'@odata.id')
        {
            $accountInfo = Get-HPERedfishDataRaw -Odataid $acc -Session $s
            if($accountInfo.UserName -eq $LoginNameToModify)
            {
                $reqAccount = $accountInfo
                break;
            }
        }
PS C:\> $priv = @{}
        $priv.Add('VirtualMediaPriv',$false)
        $priv.Add('UserConfigPriv',$false)
            
        $hp = @{}
        $hp.Add('Privileges',$priv)
    
        $oem = @{}
        $oem.Add('Hp',$hp)

        $user = @{}
        $user.Add('Oem',$oem)

PS C:\> $ret = Set-HPERedfishData -Odataid $reqAccount.'@odata.id' -Setting $user -Session $s
PS C:\> $ret

Messages                                  Name                        Type                       
--------                                  ----                        ----                       
{@{MessageID=Base.0.10.AccountModified}}  Extended Error Information  ExtendedError.0.9.6


PS C:\> $errDetails = Get-HPERedfishMessage -MessageID $ret.error.'@Message.ExtendedInfo'[0].MessageId -Session $s

PS C:\> $errorDetails


Description  : The account was modified successfully.
Message      : The account was modified successfully.
Severity     : OK
NumberOfArgs : 0
Resolution   : None.

This example shows modification of user privilege for a user and the retrieved message details. First the Odataid of the user 'TimHorton' is seacrched from Accounts odataid. Then user object is created with the required privilege change. This object is then used as the setting parameter value for Set-HPERedfishData cmdlet. When the user details are modified, the details of the returned object are retrieved using 'Get-HPERedfishMessage' cmdlet.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $MessageID,

        [System.Object]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $MessageArg,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )

    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
        
        $regs = Get-HPERedfishDataRaw -Odataid $session.RootData.Registries.'@odata.id' -Session $session
        $location = $null
        $errorname = ''
        foreach($item in $regs.Members.'@odata.id')
        {
            $spl = $item -split '/'
            if(($MessageID.Split('.'))[0] -eq $spl[$spl.count-2] )
            {
                $location = $item
                $split = $MessageID.Split('.')
                $errorname = $split[$split.Length-1]
                break
            }
        }

        if($null -eq $location -or $location -eq [string]::Empty)
        {
            throw $([string]::Format($(Get-Message('MSG_REG_ODATAID_NOT_FOUND')) ,$MessageID))
        }

        $registryMeta = Get-HPERedfishDataRaw -Odataid $location -Session $session
        
        $regOdataId = $(($registryMeta.location |Where-Object{$_.language -eq 'en'}).URI)
        if($regOdataId -is [PSObject] -and $regOdataId.PSObject.Properties.Name.Contains('extref'))
        {
            $regOdataId = $regOdataId.extref
        }

        $registry = Get-HPERedfishDataRaw -Odataid $regOdataId -Session $Session
        
        if(-not($registry.Messages.$errorname -eq '' -or $null -eq $registry.Messages.$errorname))
        {
            $errDetail = $registry.Messages.$errorname
            $msg = $errDetail.Message
            $newMsg = Set-Message -Message $msg -MessageArg $MessageArg
            $errDetail.Message = $newMsg
            return $errDetail
        }
        return $null
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishHttpData
{
<#
.SYNOPSIS
Retrieves HTTP data for provided Odataid.

.DESCRIPTION
Retrieves the HTTP web response with the redfish data returned from the source pointed to by the Odataid in PSObject format.
This cmdlet uses the session information to connect to the Redfish data source and retrieves the webresponse which has the headers from which 'Allow' methods can be found. These can be GET, POST, PATCH, PUT, DELETE. Session object with ‘RootUri’, ‘X-Auth-Token’ and ‘Location’ information of the session must be provided for using sessions to retrieve data.


.PARAMETER Odataid
Specifies the value of Odataid of Redfish data source to be retrieved. This is concatenated with the root URI (obtained from session parameter) to get the URI to send the WebRequest to.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the Odataid parameter to Get-HPERedfishHttpData.

.OUTPUTS
System.Management.Automation.PSCustomObject
Get-HPERedfishHttpData returns a PSCustomObject that has the retrieved HTTP data.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $httpSys = Get-HPERedfishHttpData -Odataid /redfish/v1/systems/1/ -Session $s

PS C:\> $httpSys


IsMutuallyAuthenticated : False
Cookies                 : {}
Headers                 : {Allow, Link, OData-Version, X-Frame-Options...}
SupportsHeaders         : True
ContentLength           : 2970
ContentEncoding         : 
ContentType             : application/json; charset=utf-8
CharacterSet            : utf-8
Server                  : HPE-iLO-Server/1.30
LastModified            : 2/9/2016 12:02:06 PM
StatusCode              : OK
StatusDescription       : OK
ProtocolVersion         : 1.1
ResponseUri             : https://192.184.217.212/redfish/v1/systems/1/
Method                  : GET
IsFromCache             : False



PS C:\> $httpSys.Headers['Allow']
GET, HEAD, POST, PATCH

PS C:\> $httpSys.Headers['Connection']
keep-alive

The example shows HTTP details returned and the 'Allow' and 'Connection' header values

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )

    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($null -eq $session -or $session -eq '')
        {
            throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
        }

        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $uri = Get-HPERedfishUriFromOdataId -Session $Session -Odataid $Odataid
        $method = "GET"
        $cmdletName = "Get-HPERedfishHttpData"
    
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -CmdletName $cmdletName -Session $Session
        return $webResponse    
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishIndex
{ 
<#
.SYNOPSIS
Gets an index structure of the HPE Redfish API data.

.DESCRIPTION
Using a passed in Redfish API session, the cmdlet recursively traverses the Redfish API tree and indexes everything that is found. Using the switch parameters, the user can customize what gets indexed. The returned index is a set of key-value pairs where the keys are the terms in the HPE Redfish data source and the values are list of occurances of the term and details of the term like Property name or value where the term is found, the odataids to access the data item and its schema, etc.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DateAndTime
Switch value that causes the iLO Data and Time node to be indexed when true.

.PARAMETER ExtRef
Switch value that causes external refrences to be indexed when true.

.PARAMETER Schema
Switch value that causes Schemas to be in indexed when true.

.PARAMETER Log
Switch value that causes IML and IEL logs to be indexed when true.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.Management.Automation.PSCustomObject
You can pipe Session object obtained by executing Connect-HPERedfish cmdlet to Get-HPERedfishIndex

.OUTPUTS
System.Collections.SortedList
Get-HPERedfishIndex returns a sorted list of key-value pairs which is the index. The keys are terms in the HPE Redfish data source and values are details of keys like Porperty name and value where the key is found, odataid to access the key and the schema odataid for the property.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $index = Get-HPERedfishIndex -Session $s

PS C:\> $index.Keys -match "power"
AllocatedPowerWatts
AutoPowerOn
AveragePowerOutputWatts
BalancedPowerPerf
CollabPowerControl
DynamicPowerResponse
DynamicPowerSavings
FastPowerMeter
HpPowerMeter
HpPowerMetricsExt
HpServerPowerSupply
LastPowerOutputWatts
MaxPowerOutputWatts
MinProcIdlePower
MixedPowerSupplyReporting
OldPowerOnPassword
Power
PowerAllocationLimit
PowerandResetPriv
PowerAutoOn
PowerButton
PowerCapacityWatts
PowerConsumedWatts
PowerMeter
PowerMetrics
PowerOnDelay
PowerOnLogo
PowerOnPassword
PowerProfile
PowerRegulator
PowerRegulatorMode
PowerRegulatorModesSupported
PowerSupplies
PowerSupplyStatus
PowerSupplyType
PushPowerButton
VirtualPowerAndResetPriv

PS C:\> $index.PowerMeter


PropertyName  : PowerMeter
Value         : @{@odata.id=/redfish/v1/Chassis/1/Power/PowerMeter/}
DataOdataId   : /redfish/v1/Chassis/1/Power/
SchemaOdataId : /redfish/v1/SchemaStore/en/HpPowerMetricsExt.json/
Tag           : PropertyName

PropertyName  : @odata.id
Value         : /redfish/v1/Chassis/1/Power/PowerMeter/
DataOdataId   : /redfish/v1/Chassis/1/Power/
SchemaOdataId : /redfish/v1/SchemaStore/en/HpPowerMetricsExt.json/
Tag           : Value

PropertyName  : PowerMeter
Value         : @{@odata.id=/redfish/v1/Chassis/1/Power/PowerMeter/}
DataOdataId   : /redfish/v1/Chassis/1/Power#/PowerSupplies/0/
SchemaOdataId : /redfish/v1/SchemaStore/en/Power.json/
Tag           : PropertyName

PropertyName  : @odata.id
Value         : /redfish/v1/Chassis/1/Power/PowerMeter/
DataOdataId   : /redfish/v1/Chassis/1/Power#/PowerSupplies/0/
SchemaOdataId : /redfish/v1/SchemaStore/en/Power.json/
Tag           : Value

PropertyName  : @odata.id
Value         : /redfish/v1/Chassis/1/Power/PowerMeter/
DataOdataId   : /redfish/v1/ResourceDirectory/
SchemaOdataId : /redfish/v1/SchemaStore/en/ComputerSystemCollection.json/
Tag           : Value

This example shows how to create and use the index on an HPE Redfish data source. First, the index is created using Get-HPERedfishIndex cmdlets and store the created index. The index stores key-value pairs for the entire data source. The term "power" is searched in the keys of the index and it returns all the keys which has "power" as substring. When a specific key "PowerMeter" is seleted, the list of values is displayed where PowerMeter was encountered in the HPE redfish data.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [Switch]
        [parameter(Mandatory=$false)]
        $DateAndTime,

        [Switch]
        [parameter(Mandatory=$false)]
        $ExtRef,

        [Switch]
        [parameter(Mandatory=$false)]
        $Schema,

        [Switch]
        [parameter(Mandatory=$false)]
        $Log,

        [Switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $Global:SeenOdataIds = [System.Collections.ArrayList]@() #The odata ids of the already visited nodes.

        $Global:SeenSchemaTypes = [System.Collections.ArrayList]@() #The odata id of the already visited nodes.

        $KeyValueIndex= New-Object System.Collections.SortedList
    
        $SchemaIgnoreList = @('object', 'string', 'BaseNetworkAdapter.0.9.5', 'Type.json#', 'array', 'integer', 'null', 'number', 'boolean', 'map')

        #$Seperator = @(' ', '!', "`"", '#', "$", '%', '&', "``", '(', ')', '*', "'",'+', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^', '_', '~', '{', '|', '}')

        $IgnoreList = @('a', 'A', 'and', 'any', 'are', 'as', 'at', 'be', 'been', 'for', 'from', 'has', 'have', 'if', 'in', 'is', 'or', 'the', 'The', 'this', 'This', 'to', 'was', 'when', 'which', 'will')

        $PropertyNameIgnoreList = @('Created', 'Type', 'action', 'UUID', 'Updated', 'updated')

        $odataIdIgnoreList = @()

        $TraverseRefs = @('@odata.id')

        if($DateAndTime -ne $true)
        {
            $odataIdIgnoreList += '/redfish/v1/Managers/1/DateTime/'
        }

        if($ExtRef -eq $true)
        {
            $TraverseRefs += 'extref'
        }

        if($Log -ne $true)
        {
            $odataIdIgnoreList += '/redfish/v1/Managers/1/LogServices/IEL/Entries/'
            $odataIdIgnoreList += '/redfish/v1/Systems/1/LogServices/IML/Entries/'
        }

    

    

        function Step-ThroughNoteProperties($node, $DOdataId, $SchemaOdataId, $s, $SchemaNode)
        {
            if($null -ne $node.'@odata.type')
            {
                $NodeType = $node.'@odata.type'
                foreach($SchemaType in $NodeType)
                {
                    if($null -ne $SchemaType.'$ref')
                    {
                        $SchemaType = $SchemaType.'$ref'
                    } 
                    if($null -ne $SchemaType -and $SchemaIgnoreList -notcontains $SchemaType -and $Global:SeenSchemaTypes -notcontains $SchemaType)
                    {
                        $Global:SeenSchemaTypes += $SchemaType
                        try
                        {
                            if($SchemaType -isnot [string])
                            {
                                break
                            }
                            $SchemaOdataId = Get-HPERedfishSchemaExtref -odatatype $SchemaType -Session $s
                        }
                        catch
                        {
                            if($_.Exception.InnerException -match "The underlying connection was closed: Could not establish trust relationship for the SSL/TLS secure channel.")
                            {
                                Write-Error $_
                            }
                            else
                            {
                                write-error $([string]::Format($(Get-Message('MSG_SCHEMA_NOT_FOUND')), $SchemaType))
                            }
                            continue
                        }
                    
                        if($Schema -and $Global:SeenOdataIds -notcontains $SchemaOdataId)
                        {
                            $Global:SeenOdataIds+= $SchemaOdataId
                            if($null -ne $schemaodataId -and $schemaodataId.GetType() -notmatch 'string' -and $null -ne $SchemaOdataId.'$ref')
                            {
                                $SchemaOdataId = $SchemaOdataId.'$ref'
                            }
                            try
                            {
                                $SchemaNode = Get-HPERedfishDataRaw -Odataid $SchemaOdataId -Session $s
                            }
                            catch
                            {
                                Write-Error $([string]::Format($(Get-Message('MSG_NO_REDFISH_DATA')) ,$SchemaOdataId))
                            }
                            Step-ThroughNoteProperties -node $SchemaNode -DOdataId $SchemaOdataId -s $s
                        }
                    }
                }
            }
            $node | get-member -type NoteProperty | foreach-object { #Displays all the note properties within the node.
                if($true)#$PropertyNameIgnoreList -notcontains $_.Name)
                {
                    $name=$_.Name ;
                    $temp = $node.$name
            
                    $Information = New-Object PSObject
                        $Information | Add-Member -type NoteProperty -Name PropertyName -Value $name
                        $Information | Add-Member -type NoteProperty -Name Value -Value $temp
                        $Information | Add-Member -type NoteProperty -Name DataOdataId -Value $DOdataId
                        $Information | Add-Member -type NoteProperty -Name SchemaOdataId -Value $SchemaOdataId
                        $Information | Add-Member -type NoteProperty -Name Tag -Value 'PropertyName'
                        Limit-Entries -Name $name -Information $information
            
                    if($null -ne $temp -and $temp -ne '' -and $PropertyNameIgnoreList -notcontains $name )
                    {
                        $parsedProp = $false
                        $arrHasNonNullElements = $false
                        if($temp.GetType().ToString() -eq 'System.Object[]')
                        {
                            foreach($i in $temp)
                            {
                                if($null -ne $i)
                                {
                                    $arrHasNonNullElements = $true
                                    break
                                }
                            }
                            if($arrHasNonNullElements -eq $false)
                            {
                                Split-Value -DOdataId $DOdataId -SchemaOdataId $SchemaOdataId -node $node -Value $temp -name $name
                                $parsedProp = $true
                            }
                        }

                        if($parsedProp -eq $false)
                        {
                            if(($temp | Get-Member).MemberType -contains 'NoteProperty') 
                            {
                                Step-ThroughNoteProperties -node $temp -DOdataId $DOdataId -SchemaOdataId $SchemaOdataId -s $s -SchemaNode $SchemaNode
                            }
                            elseif(($temp.Count) -gt 1)
                            {
                                foreach($t in $temp)
                                {
                                    if($null -ne $t -and ($t | Get-Member).MemberType -contains 'NoteProperty') 
                                    {
                                        Step-ThroughNoteProperties -node $t -DOdataId $DOdataId -SchemaOdataId $SchemaOdataId -s $s -SchemaNode $SchemaNode
            
                                    }
                                    else
                                    {
                                        Split-Value -DOdataId $DOdataId -SchemaOdataId $SchemaOdataId -node $node -Value $t -name $name
                                    }
                            }
                            }
                            else
                            {
                                Split-Value -DOdataId $DOdataId -SchemaOdataId $SchemaOdataId -node $node -Value $temp -name $name
                            }
                        }

                        if($TraverseRefs -contains $name)
                        {
                        
                
                            foreach($t in $temp)
                            {
                                if($Global:SeenOdataIds -notcontains $t -and $OdataIdIgnoreList -notcontains $t -and (Confirm-OdataId $t))
                                {
                                    $Global:SeenOdataIds += $t
                                    try
                                    {
                                        if($t.GetType() -notmatch 'string' -and $null -ne $t.'$ref')
                                        {
                                            $t = $t.'$ref'
                                        }

                                        $NewNode = Get-HPERedfishDataRaw -Odataid $t -Session $s
                                        if($null -ne $NewNode)
                                        {
                                            Step-ThroughNoteProperties -node $NewNode -DOdataId $t -SchemaOdataId $SchemaOdataId -s $s -SchemaNode $SchemaNode
                                        }
                                    }
                                    catch
                                    {
                                        Write-Error $_
                                    }
                                }        
                            }
                       

                    
                        }
                    }
                }
            }
        }

        function Confirm-OdataId($value)
        {
            if($value -match '/redfish/v1/')
            {
                return $true
            }
            else
            {
                return $false
            }
        }

        function Confirm-isNumeric ($value) 
        {
            $x = 0
            $isNum = [System.Int32]::TryParse($value, [ref]$x)
            return $isNum
        }

        function Limit-Entries($Name, $Information)
        {
            $PassedRules = $true

            if(Confirm-isNumeric $name)
            {
                $PassedRules = $false
            }
            elseif($name -eq '' -or $null -eq $Information)
            {
                $PassedRules = $false
            }
            elseif($IgnoreList -ccontains $name)
            {
                $PassedRules = $false
            }
            if($PassedRules)
            {
                Add-KeyValueIndex $Name $Information
            }
        }

        function Add-KeyValueIndex($Name, $Information)
        {
            if($KeyValueIndex.Contains($Name))
            {
                $KeyValueIndex.$Name += $Information
            }
            else
            {
                $ray = @()
                $KeyValueIndex.Add($Name, $ray)
                $KeyValueIndex.$Name += $Information
            }
        }

        function Split-Value($DOdataId, $SchemaOdataId, $node, $Value, $name)
        {
            $Information = New-Object PSObject
            $Information | Add-Member -type NoteProperty -Name PropertyName -Value $name
            $Information | Add-Member -type NoteProperty -Name Value -Value $value
            $Information | Add-Member -type NoteProperty -Name DataOdataId -Value $DOdataId
            $Information | Add-Member -type NoteProperty -Name SchemaOdataId -Value $SchemaOdataId
            $Information | Add-Member -type NoteProperty -Name Tag -Value 'Value'

            $value = $value -replace '[ -/]+', ' '
            $value = $value -replace '[:-@]+', ' '
            $value = $value -replace '[[-``]+', ' '
            $value = $value -replace '[{-~]+', ' '

            if($null -ne $value -and $value -ne '')
            {
                $SplitValue = $Value.Split(' ')
                foreach($word in $SplitValue)
                {
                    if($IgnoreList -notcontains $word)
                    {
                    
                        Limit-Entries -Name $word -Information $information
                    }
                }
            }
        }

        Step-ThroughNoteProperties -node $Session.RootData -DOdataId $odataid -s $Session
        return $KeyValueIndex
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishModuleVersion
{
<#
.SYNOPSIS
Gets the module details for the HPERedfishCmdlets module.

.DESCRIPTION
The Get-HPERedfishModuleVersion cmdlet gets the module details for the HPERedfishCmdlets module. The details include name of file, path, description, GUID, version, and supported UICultures with respective version.
    
.INPUTS

.OUTPUTS
System.Management.Automation.PSCustomObject
    
    Get-HPERedfishmoduleVersion retuns a System.Management.Automation.PSCustomObject object.

.EXAMPLE
Get-HPERedfishModuleVersion 

Name                    : HPERedfishCmdlets
Path                    : C:\Program Files\Hewlett-Packard\PowerShell\Modules\HPERedfishCmdlets\HPERedfishCmdlets.psm1
Description             : HPE Redfish PowerShell cmdlets create an interface to HPE Redfish devices such as iLO. 
                          These cmdlets can be used to get and set HPE Redfish data and to invoke actions on these devices and 
                          the systems they manage.
                          There are also advanced functions that can create an index or directory of HPE Redfish data sources. 
                          A file with examples called HPERedfishExamples.ps1 is included in this release.
GUID                    : aadc4b97-c04c-44c6-8d69-1ebc5b5ffcc8
Version                 : 1.0.0.0
CurrentUICultureName    : en-US
CurrentUICultureVersion : 1.0.0.0
AvailableUICulture      : @{UICultureName=en-US; UICultureVersion=1.0.0.0}


This example shows the cmdlets module details.

.LINK
http://www.hpe.com/servers/powershell

#>
    [CmdletBinding(PositionalBinding=$false)]
    param() # no parameters
    $mod = Get-Module | Where-Object {$_.Name -eq 'HPERedfishCmdlets'}
    $cul = Get-UICulture
    $versionObject = New-Object PSObject
    $versionObject | Add-member 'Name' $mod.Name
    $versionObject | Add-member 'Path' $mod.Path
    $versionObject | Add-member 'Description' $mod.Description
    $versionObject | Add-member 'GUID' $mod.GUID
    $versionObject | Add-member 'Version' $mod.Version
    $versionObject | Add-member 'CurrentUICultureName' $cul.Name
    $versionObject | Add-member 'CurrentUICultureVersion' $mod.Version
    
    $UICulture = New-Object PSObject
    $UICulture | Add-Member 'UICultureName' 'en-US'
    $UICulture | Add-Member 'UICultureVersion' $mod.Version
    $AvailableUICulture += $UICulture
          
    $versionObject | Add-Member 'AvailableUICulture' $AvailableUICulture

    return $versionObject
}

function Get-HPERedfishSchema
{
<#
.SYNOPSIS
Retrieve schema for the specified Type.

.DESCRIPTION
Retrieves the schema for the specified Type of Redfish data. The cmdlet first gets the JSON link of the schema and then gets the data from the schema store that has the schema.

.PARAMETER Type
Value of the Type field obtained from the data for which schema is to be found.

.PARAMETER Language
The language code of the schema to be retrieved. The default value is 'en'. The allowed values depend on the languages available on the system.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the Type parameter to Get-HPERedfishSchema.

.OUTPUTS
System.Management.Automation.PSCustomObject
Get-HPERedfishSchema returns a PSCustomObject that has the retrieved schema of the specified type.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $sch = Get-HPERedfishSchema -odataType '#ComputerSystem.1.1.0.ComputerSystem' -Session $s

PS C:\> $sch


$schema              : http://json-schema.org/draft-04/schema#
title                : ComputerSystem.1.1.0
type                 : object
readonly             : False
additionalProperties : False
description          : The schema definition of a computer system and its properties. A computer system represents a physical or virtual machine and the local resources, such as memory, CPU, and other devices that can be accessed from that machine.
properties           : @{Oem=; Name=; Modified=; Type=; SystemType=; AssetTag=; Manufacturer=; Model=; SKU=; SerialNumber=; Version=; PartNumber=; Description=; VirtualSerialNumber=; UUID=; HostCorrelation=; HostName=; Status=; BIOSPOSTCode=; IndicatorLED=; Power=; PowerState=; Boot=; Bios=; BiosVersion=; Processors=; ProcessorSummary=; Memory=; MemorySummary=; AvailableActions=; @odata.id=; @odata.context=; @odata.type=; Id=; Actions=; LogServices=; Links=}
actions              : @{description=The POST custom actions defined for this type (the implemented actions might be a subset of these).; actions=}
copyright            : Copyright 2014,2015 ABC Company Development, LP.  Portions Copyright 2014-2015 Distributed Management Task Force. All rights reserved.


PS C:\> $sch.properties


Oem                 : @{type=object; readonly=False; additionalProperties=True; properties=}
Name                : @{$ref=Resource.json#/definitions/Name}
Modified            : @{$ref=Resource.json#/definitions/Modified}
Status              : @{$ref=Resource.json#/definitions/Status}
BIOSPOSTCode        : @{type=System.Object[]; description=The BIOS Power on Self Test code from the last system boot.; readonly=True; etag=True; redfish=False; deprecated=This property has been deprecated.; replacedBy=}
IndicatorLED        : @{type=System.Object[]; description=The state of the indicator LED.; enum=System.Object[]; enumDescriptions=; readonly=False; etag=True}
    .
    .
    .
Power               : @{type=System.Object[]; description=The current power state of the system.; enum=System.Object[]; readonly=True; etag=True; redfish=False; deprecated=This property has been deprecated.; replacedBy=PowerState}
ProcessorSummary    : @{type=object; additionalProperties=False; properties=; description=This object describes the central processors of the system in general detail.}
AvailableActions    : @{type=array; readonly=True; additionalItems=False; uniqueItems=True; items=; redfish=False; deprecated=The AvailableActions object has been deprecated and replaced by the Redfish compatible Actions object.; replacedBy=Actions}
@odata.id           : @{$ref=Resource.json#/definitions/odataid}
@odata.context      : @{$ref=Resource.json#/definitions/odatacontext}
@odata.type         : @{$ref=Resource.json#/definitions/odatatype}
Id                  : @{$ref=Resource.json#/definitions/Id}
Actions             : @{additionalProperties=False; type=object; properties=}
LogServices         : @{description=The LogService collection URI for this resource.; readonly=True; etag=False; type=object; properties=}
Links               : @{additionalProperties=True; readonly=True; type=object; properties=; description=The links array contains the related resource URIs.}


PS C:\> $sch.properties.IndicatorLED


type             : {string, null}
description      : The state of the indicator LED.
enum             : {$null, Unknown, Lit, Blinking...}
enumDescriptions : @{Unknown=The state of the Indicator LED cannot be determined.; Lit=The 
                   Indicator LED is lit.; Blinking=The Indicator LED is blinking.; Off=The 
                   Indicator LED is off.}
readonly         : False
etag             : True

This example shows schema for @odata.type value '#ComputerSystem.1.1.0.ComputerSystem'.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $odatatype,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [System.String]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Language = 'en',

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication

    )
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
    
        $schemaJSONOdataId = Get-HPERedfishSchemaExtref -odatatype $odatatype -Session $Session -Language $Language
        if($null -ne $schemaJSONOdataId)
        {
            $schema = Get-HPERedfishDataRaw -Odataid $schemaJSONOdataId -Session $Session
        }
    
        return $schema
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishSchemaExtref
{
<#
.SYNOPSIS
Retrieves the uri of the JSON file that contains the schema for the specified odata type.

.DESCRIPTION
Schema JSON file is pointed to by a uri. This link is retrieved from the external reference (extref) in Location field of the @odata.type in /redfish/v1/schemas/. This is uri of the JSON file that contains the schema for the specified type. This cmdlet retrieves this URI that points to the JSON schema file.

.PARAMETER odatatype
Odata type value of the data for which schema JSON file link has to be retrieved. The odata type value is present in the Redfish data as the value for the property '@odata.type'.

.PARAMETER Language
The language code of the schema for which the JSON URI is to be retrieved. The default value is 'en'. The allowed values depend on the languages available on the system.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI and X-Auth-Token for executing this cmdlet.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.INPUTS
System.String
You can pipe the Type parameter to Get-HPERedfishSchemaExtref.

.OUTPUTS
System.String
Get-HPERedfishSchemaExtref returns a String that has the Extref of the schema specified by the Type parameter.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> $schemaJSONodataid = Get-HPERedfishSchemaExtref -odatatype '#ComputerSystem.1.1.0.ComputerSystem' -Session $s
    
PS C:\> $schemaJSONodataid
/redfish/v1/SchemaStore/en/ComputerSystem.json/

This example shows that the schema for '#ComputerSystem.1.1.0.ComputerSystem' is stored at the external reference /redfish/v1/SchemaStore/en/ComputerSystem.json/. The schema is retrieved using this as the value for 'Odataid' parameter for Get-HPERedfishData or Get-HPERedfishDataRaw and navigate to the 'Properties' field.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $odatatype,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [System.String]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Language = 'en',

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )

    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }

    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }
    
        if(-not($null -eq $odatatype -or $odatatype -eq ''))
        {
            $noHash = $odatatype.Replace('#','')
            $odataTypeSplit = $noHash.Split('.')

            $schemaURIList = $Session.RootData.JsonSchemas.'@odata.id'
            $data = $null
            $data = Get-HPERedfishDataRaw -Session $Session -Odataid $schemaURIList
            $odataIdList = $data.members

            $odataIdSet = New-Object System.Collections.Generic.HashSet[string]

            foreach($odataId in $odataIdList)
            {
                $tempOdataId = $odataId.'@odata.id'
                if($tempOdataId[$tempOdataId.length-1] -ne '/')
                { 
                    $tempOdataId = $tempOdataId + '/' 
                }
                $split = $tempOdataId.Split('/')
                $typeFromOdataId = $split[$split.length-2] -replace "%23",""
                $splitTypeFromOdataId = $typeFromOdataId.Split('.')
                if($odataTypeSplit[0] -eq $splitTypeFromOdataId[0])
                {
                    $odataIdSet.Add($odataId.'@odata.id') | Out-Null
                }
            }
            
            $schemaOdataId = Get-OdataIdForOdataType -OdataType $noHash -OdataIdSet $odataIdSet

            if([string]::IsNullOrEmpty($schemaOdataId) -eq $false)
            {
                $schemaLinkObj = $null
                $schemaLinkObj = Get-HPERedfishDataRaw -Odataid $schemaOdataId -Session $session
                $schemaJSONRef = ($schemaLinkObj.Location|Where-Object {$_.language -eq $Language} | ForEach-Object {$_.Uri})
                if($schemaJSONRef -is [PSObject] -and $schemaJSONRef.PSObject.Properties.Name.Contains('extref'))
                {
                    $schemaJSONRef = $schemaJSONRef.extref
                }
                return $schemaJSONRef
            }
            else
            {
                #Write-Error "Schema not found for $type"
                throw $([string]::Format($(Get-Message('MSG_SCHEMA_NOT_FOUND')), $odatatype))
            }
        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Get-HPERedfishUriFromOdataId
{
<#
.SYNOPSIS
Gets entire URI path from provided Odataid and root URI in Session variable.

.DESCRIPTION
Gets entire URI path from provided Odataid and root URI in Session variable.

.PARAMETER Odataid
Odataid of data of which completer URI is to be obtained.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI to create the complete URI along with the Odataid parameter.

.INPUTS
System.String
You can pipe the Odataid parameter to Get-HPERedfishUriFromOdataid.

.OUTPUTS
System.String
Get-HPERedfishUriFromOdataid returns a string that has the complete URI derived from the Odataid and the RootUri from the session object.

.NOTES
See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.EXAMPLE
PS C:\> Get-HPERedfishUriFromOdataid -Odataid /redfish/v1/systems/1/ -Session $s
https://192.184.217.212/redfish/v1/systems/1

This example shows the resultant URI obtained from the Odataid provided and the RootURI from the session object.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session
    )

    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $rootURI = $Session.RootUri
    if($null -eq $rootURI)
    {
         throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Session.GetType().Name, 'Session'))
    }
    if($rootURI[$rootURI.length-1] -eq '/'){$rootURI = $rootURI.Substring(0,$rootURI.Length-1)}

    $matchLen = 0
    try
    {
        do {
            $matchLen++
            $a = $rootURI.Substring(($rootURI.Length - $matchLen), $matchLen)
            $b = $Odataid.Substring(0,$matchLen)
        } while ($a -ne $b)
        $c = $Odataid.Substring($matchLen)
        #if($c[0] -eq '/' -and $c.Length -gt 1){$c = $c.Substring(1)}
        return $rootURI + $c
    }
    catch
    {
        throw $(Get-Message('MSG_INVALID_ODATA_ID'))
    }
}

function Invoke-HPERedfishAction
{
<#
.SYNOPSIS
Executes HTTP POST method on the destination server.

.DESCRIPTION
Executes HTTP POST method on the desitination server with the data from Data parameter. Used for invoking an action like resetting the server.

.PARAMETER Odataid
Odataid where you have to POST the data.

.PARAMETER Data
Data is the payload body for the HTTP POST request passed in the form of a JSON string or name-value hashtable format.

.Parameter Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI to create the complete URI along with the Odataid parameter.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
- Edit-HPERedfishData is for HTTP PUT method
- Invoke-HPERedfishAction is for HTTP POST method
- Remove-HPERedfishData is for HTTP DELETE method
- Set-HPERedfishData is for HTTP PATCH method

See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.INPUTS
System.String
You can pipe the Odataid to Invoke-HPERedfishAction. Odataid points to the location where the POST method is to be executed.

.OUTPUTS
System.Management.Automation.PSCustomObject
Invoke-HPERedfishAction returns a PSObject that has message from the HTTP response. The response may be informational or may have a message requiring an action like server reset.

.EXAMPLE
PS C:\> $ret = Invoke-HPERedfishAction -Odataid $mgr..'@odata.id' -Data $null -Session $s
PS C:\> $ret.error

@Message.ExtendedInfo            code                  message                                        
---------------------            ----                  -------                                        
{@{MessageId=Base.0.10.Success}} iLO.0.10.ExtendedInfo See @Message.ExtendedInfo for more information.


This example shows Invoke-HPERedfishData used to invoke a reset on the server. The 'ResetType' property is set to 'ForcedReset' and the output shows that reset was invoked successfully. The details of actions that can be performed at a particular odataid are mentioned in the value for 'Actions' field.

.EXAMPLE
$PS C:\> $accData = Get-HPERedfishDataRaw -Odataid '/redfish/v1/AccountService/' -Session $session
    $accountodataid = $accData.Accounts.'@odata.id'
    
$PS C:\> $priv = @{}
    $priv.Add('RemoteConsolePriv',$true)
    $priv.Add('iLOConfigPriv',$true)
    $priv.Add('VirtualMediaPriv',$false)
    $priv.Add('UserConfigPriv',$false)
    $priv.Add('VirtualPowerAndResetPriv',$true)

$PS C:\> $hp = @{}
    $hp.Add('LoginName',$newiLOLoginName)
    $hp.Add('Privileges',$priv)
    
$PS C:\> $oem = @{}
    $oem.Add('Hp',$hp)

$PS C:\> $user = @{}
    $user.Add('UserName',$newiLOUserName)
    $user.Add('Password',$newiLOPassword)
    $user.Add('Oem',$oem)

$PS C:\> $ret = Invoke-HPERedfishAction -Odataid $accountodataid -Data $user -Session $session

This example creates a user object and adds it to the Account odataid in AccountService.

.EXAMPLE
PS C:\> $sys = Get-HPERedfishDataRaw -Odataid /redfish/v1/systems/1/ -Session $s
PS C:\> $settingToPost = @{}
PS C:\> $settingToPost.Add('ResetType','ForceRestart')
PS C:\> $ret = Invoke-HPERedfishAction -Odataid $sys.Actions.'#ComputerSystem.Reset'.target -Data $settingToPost -Session $s
PS C:\> $ret.error

Messages                                  Name                          Type
--------                                  ----                          ----
{@{MessageID=iLO.0.10.ResetInProgress}}   Extended Error Information    ExtendedError.0.9.6

This example invokes a reset on the iLO for the server.

.EXAMPLE
PS C:\> $sys = Get-HPERedfishDataRaw -Odataid /redfish/v1/systems/1/ -Session $s
PS C:\> $sys.LogServices

@odata.id                         
---------                         
/redfish/v1/Systems/1/LogServices/

PS C:\> $logSerObj = Get-HPERedfishDataRaw $sys.LogServices.'@odata.id' -Session $s

PS C:\> $logSerObj.Members

@odata.id                             
---------                             
/redfish/v1/Systems/1/LogServices/IML/
 
PS C:\> $iml = Get-HPERedfishDataRaw $logSerObj.Members.'@odata.id' -Session $s

PS C:\> $iml


@odata.context  : /redfish/v1/$metadata#Systems/Members/1/LogServices/Members/$entity
@odata.id       : /redfish/v1/Systems/1/LogServices/IML/
@odata.type     : #LogService.1.0.0.LogService
Actions         : @{#LogService.ClearLog=}
Entries         : @{@odata.id=/redfish/v1/Systems/1/LogServices/IML/Entries/}
Id              : IML
Name            : Integrated Management Log
OverWritePolicy : WrapsWhenFull


PS C:\> $iml.Actions

#LogService.ClearLog                                                        
--------------------                                                        
@{target=/redfish/v1/Systems/1/LogServices/IML/Actions/LogService.ClearLog/}

PS C:\> Invoke-HPERedfishAction -Odataid $iml.Actions.'#LogService.ClearLog'.target -Data $action -Session $session

{"Messages":[{"MessageID":"iLO.0.10.EventLogCleared"}],"Name":"Extended Error Information","Type":"ExtendedError.0.9.6"}


This example clears the IML logs by creating a JSON object with action to clear the Integraged Management Logs.

.EXAMPLE
PS C:\> $mgr = Get-HPERedfishDataRaw -Odataid /redfish/v1/managers/1/ -Session $s
PS C:\> $mgr.LogServices

@odata.id                         
---------                         
/redfish/v1/Managers/1/LogServices/

PS C:\> $logSerObj = Get-HPERedfishDataRaw $mgr.LogServices.'@odata.id' -Session $s

PS C:\> $logSerObj.Members

@odata.id                             
---------                             
/redfish/v1/Managers/1/LogServices/IEL/
 
PS C:\> $iml = Get-HPERedfishDataRaw $logSerObj.Members.'@odata.id' -Session $s

PS C:\> $iml


@odata.context  : /redfish/v1/$metadata#Managers/Members/1/LogServices/Members/$entity
@odata.id       : /redfish/v1/Managers/1/LogServices/IEL/
@odata.type     : #LogService.1.0.0.LogService
Actions         : @{#LogService.ClearLog=}
Entries         : @{@odata.id=/redfish/v1/Managers/1/LogServices/IEL/Entries/}
Id              : IEL
Name            : iLO Event Log
OverWritePolicy : WrapsWhenFull


PS C:\> $iml.Actions

#LogService.ClearLog                                                        
--------------------                                                        
@{target=/redfish/v1/Systems/1/LogServices/IML/Actions/LogService.ClearLog/}

PS C:\> $ret = Invoke-HPERedfishAction -Odataid $iml.Actions.'#LogService.ClearLog'.target -Data $action -Session $s

PS C:\> $ret.error

{"Messages":[{"MessageID":"iLO.0.10.EventLogCleared"}],"Name":"Extended Error Information","Type":"ExtendedError.0.9.6"}


This example clears the IML logs by creating a JSON object with action to clear the IML.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [System.Object]
        [parameter(Mandatory=$false)]
        $Data, #one of the AllowedValue in capabilities

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
<#
    Edit-HPERedfishData is for HTTP PUT method
    Invoke-HPERedfishAction is for HTTP POST method
    Remove-HPERedfishData is for HTTP DELETE method
    Set-HPERedfishData is for HTTP PATCH method
#>
  
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    if(($null -ne $Data) -and $Data.GetType().ToString() -notin @('System.Collections.Hashtable', 'System.String'))
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Data.GetType().ToString() ,'Data'))
    }

    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $jsonStringData = ''
        if($null -eq $Data)
        {
            $jsonStringData = '{}'
        }
        else
        {
            if($Data.GetType().ToString() -eq 'System.Collections.Hashtable')
            {
                $jsonStringData = $Data | ConvertTo-Json -Depth 10
            }
            else
            {
                $jsonStringData = $Data
            }
        }
        
        $uri = Get-HPERedfishUriFromOdataId -Odataid $Odataid -Session $Session
        $method = "POST"
        $payload = $jsonStringData
        $cmdletName = "Invoke-HPERedfishAction"
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -Payload $payload -CmdletName $cmdletName -Session $Session

        try
        {
            $webStream = $webResponse.GetResponseStream()
            $respReader = New-Object System.IO.StreamReader($webStream)
            $resp = $respReader.ReadToEnd()
        
            $webResponse.Close()
            $webStream.Close()
            $respReader.Close()
    
            return $resp|ConvertFrom-Json
        }
        finally
        {
            if ($null -ne $webResponse -and $webResponse -is [System.IDisposable]){$webResponse.Dispose()}
            if ($null -ne $webStream -and $webStream -is [System.IDisposable]){$webStream.Dispose()}
            if ($null -ne $respReader -and $respReader -is [System.IDisposable]){$respReader.Dispose()}

        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Remove-HPERedfishData
{
<#
.SYNOPSIS
Executes HTTP DELETE method on destination server.

.DESCRIPTION
Executes HTTP DELETE method on the desitination server at the location pointed to by Odataid parameter. Example of usage of this cmdlet is removing an iLO user account.

.PARAMETER Odataid
Odataid of the data which is to be deleted.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI to create the complete URI along with the Odataid parameter. The root URI of the Redfish data source and the X-Auth-Token session identifier required for executing this cmdlet is obtained from Session parameter.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
- Edit-HPERedfishData is for HTTP PUT method
- Invoke-HPERedfishAction is for HTTP POST method
- Remove-HPERedfishData is for HTTP DELETE method
- Set-HPERedfishData is for HTTP PATCH method

See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.INPUTS
System.String
You can pipe the Odataid to Remove-HPERedfishData. Odataid points to the location where the DELETE method is to be executed.

.OUTPUTS
System.Management.Automation.PSCustomObject
Remove-HPERedfishData returns a PSObject that has message from the HTTP response. The response may be informational or may have a message requiring an action like server reset.

.EXAMPLE
PS C:\> $users = Get-HPERedfishDataRaw -Odataid /redfish/v1/accountService/accounts/ -Session $s
foreach($user in $users.Members.'@odata.id')
{
    $userDetails = Get-HPERedfishDataRaw -Odataid $user -Session $s
    if($userDetails.Username -eq 'user1')
    {
        Remove-HPERedfishData -Odataid $userDetails.'@odata.id' -Session $s
        break
    }
}


In this example, first, all accounts are retrieved in $users variable. This list is parsed one by one and when the 'user1' username is found, it is removed from the list of users.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
<#
    Edit-HPERedfishData is for HTTP PUT method
    Invoke-HPERedfishAction is for HTTP POST method
    Remove-HPERedfishData is for HTTP DELETE method
    Set-HPERedfishData is for HTTP PATCH method
#>
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    
    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $uri = Get-HPERedfishUriFromOdataId -Odataid $Odataid -Session $Session
        $method = "DELETE"
        $cmdletName = "Remove-HPERedfishData"
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -CmdletName $cmdletName -Session $session

        try
        {
            $webStream = $webResponse.GetResponseStream()
            $respReader = New-Object System.IO.StreamReader($webStream)
            $resp = $respReader.ReadToEnd()

            $webResponse.Close()
            $webStream.Close()
            $respReader.Close()

            return $resp|ConvertFrom-Json
        }
        finally
        {
            if ($null -ne $webResponse -and $webResponse -is [System.IDisposable]){$webResponse.Dispose()}
            if ($null -ne $webStream -and $webStream -is [System.IDisposable]){$webStream.Dispose()}
            if ($null -ne $respReader -and $respReader -is [System.IDisposable]){$respReader.Dispose()}
        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }
}

function Set-HPERedfishData
{
<#
.SYNOPSIS
Executes HTTP PATCH method on destination server.

.DESCRIPTION
Executes HTTP PATCH method at the specified Odataid. This cmdlet is used to update the value of an editable property in the redfish data source. A property name and the new value must be provided to modify a value. If the Property name is left blank or not specified, then the PATCH is done using the Value parameter on the Odataid. 

.PARAMETER Odataid
Odataid where the property is to be modified.

.PARAMETER Setting
Specifies a JSON string or a hashtable which has the name of the setting to be modified and the corresponding value. This parameter is the payload body of the HTTP PATCH request. Multiple properties can be modified using the same request by stating multiple name-value pairs in the same hashtable structure.
Example 1: $setting = @{'property1'= 'value1'}
Example 2: $setting = @{'property1'= 'value1'; 'property2'='value2'}
This can also be a complex(nested) hashtable. 
Example: $priv = @{}
          $priv.Add('RemoteConsolePriv',$true)
          $priv.Add('iLOConfigPriv',$true)
          $priv.Add('VirtualMediaPriv',$true)
          $priv.Add('UserConfigPriv',$true)
          $priv.Add('VirtualPowerAndResetPriv',$true)

          $hp = @{}
          $hp.Add('LoginName','user1')
          $hp.Add('Privileges',$priv)
    
          $oem = @{}
          $oem.Add('Hp',$hp)

          $user = @{}
          $user.Add('UserName','adminUser')
          $user.Add('Password','password123')
          $user.Add('Oem',$oem)

This example shows a complex $user object that is used as 'Setting' parameter value to update properties/privileges of a user. This is passed to the Odataid of the user whose details are to be updated.

.PARAMETER Session
Session PSObject returned by executing Connect-HPERedfish cmdlet. It must have RootURI to create the complete URI along with the Odataid parameter. The root URI of the Redfish data source and the X-Auth-Token session identifier required for executing this cmdlet is obtained from Session parameter.

.PARAMETER DisableCertificateAuthentication
If this switch parameter is present then server certificate authentication is disabled for the execution of this cmdlet. If not present it will execute according to the global certificate authentication setting. The default is to authenticate server certificates. See Enable-HPERedfishCertificateAuthentication and Disable-HPERedfishCertificateAuthentication to set the per PowerShell session default.

.NOTES
- Edit-HPERedfishData is for HTTP PUT method
- Invoke-HPERedfishAction is for HTTP POST method
- Remove-HPERedfishData is for HTTP DELETE method
- Set-HPERedfishData is for HTTP PATCH method

See typical usage examples in the HPERedfishExamples.ps1 file installed with this module.

.INPUTS
System.String
You can pipe the Odataid to Set-HPERedfishData. Odataid points to the location where the PATCH method is to be executed.

.OUTPUTS
System.Management.Automation.PSCustomObject
Set-HPERedfishData returns a PSObject that has message from the HTTP response. The response may be informational or may have a message requiring an action like server reset.

.EXAMPLE
PS C:\> $setting = @{'IndicatorLED' = 'Lit'}
PS C:\> $ret = Set-HPERedfishData -Odataid /redfish/v1/systems/1/ -Setting $setting -Session $s
PS C:\> $ret.error

@Message.ExtendedInfo            code                  message                                  
---------------------            ----                  -------                                  
{@{MessageId=Base.0.10.Success}} iLO.0.10.ExtendedInfo See @Message.ExtendedInfo for more inf...       

This example shows updating the 'IndicatorLED' field in computer system setting to set the value to 'Lit'.


.EXAMPLE
PS C:\> $LoginNameToModify = 'TimHorton'
PS C:\> $accounts = Get-HPERedfishDataRaw -Odataid '/redfish/v1/AccountService/Accounts/' -Session $s
PS C:\> $reqAccount = $null
        foreach($acc in $accounts.Members.'@odata.id')
        {
            $accountInfo = Get-HPERedfishDataRaw -Odataid $acc -Session $s
            if($accountInfo.UserName -eq $LoginNameToModify)
            {
                $reqAccount = $accountInfo
                break;
            }
        }
PS C:\> $priv = @{}
        $priv.Add('VirtualMediaPriv',$false)
        $priv.Add('UserConfigPriv',$false)
            
        $hp = @{}
        $hp.Add('Privileges',$priv)
    
        $oem = @{}
        $oem.Add('Hp',$hp)

        $user = @{}
        $user.Add('Oem',$oem)

PS C:\> $ret = Set-HPERedfishData -Odataid $reqAccount.'@odata.id' -Setting $user -Session $s
PS C:\> $ret

Messages                                  Name                        Type                       
--------                                  ----                        ----                       
{@{MessageID=Base.0.10.AccountModified}}  Extended Error Information  ExtendedError.0.9.6

This example shows modification of user privilege for a user. First the Odataid of the user 'TimHorton' is seacrched from Accounts Odataid. Then user object is created with the required privilege change. This object is then used as the setting parameter value for Set-HPERedfishData cmdlet.

.LINK
http://www.hpe.com/servers/powershell

#>
    param
    (
        [System.String]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        $Odataid,

        [System.Object]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Setting,

        [PSObject]
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        $Session,

        [switch]
        [parameter(Mandatory=$false)]
        $DisableCertificateAuthentication
    )
  
    if($null -eq $session -or $session -eq '')
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_MISSING')) ,'Session'))
    }
    if(($null -ne $Setting) -and $Setting.GetType().ToString() -notin @('System.Collections.Hashtable', 'System.String'))
    {
        throw $([string]::Format($(Get-Message('MSG_PARAMETER_INVALID_TYPE')), $Setting.GetType().ToString() ,'Setting'))
    }


    $OrigCertFlag = $script:CertificateAuthenticationFlag
    try
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $false
        }

        $jsonStringData = ''

        if($null -eq $Setting )
        {
            $jsonStringData = '{}'
        }
        else
        {
            if($Setting.GetType().ToString() -eq 'System.Collections.Hashtable')
            {
                $jsonStringData = $Setting | ConvertTo-Json -Depth 10
            }
            else
            {
                $jsonStringData = $Setting
            }
        }
    
        $uri = Get-HPERedfishUriFromOdataId -Odataid $Odataid -Session $Session
        $method = "PATCH"
        $payload = $jsonStringData
        $cmdletName = "Invoke-HPERedfishAction"
        $webResponse = Invoke-HttpWebRequest -Uri $uri -Method $method -Payload $payload -CmdletName $cmdletName -Session $session

        try
        {
            $webStream = $webResponse.GetResponseStream()
            $respReader = New-Object System.IO.StreamReader($webStream)
            $resp = $respReader.ReadToEnd()
        
            $webResponse.Close()
            $webStream.Close()
            $respReader.Close()  

            return $resp|ConvertFrom-Json
        } 
        finally
        {
            if (($null -ne $webResponse) -and ($webResponse -is [System.IDisposable])){$webResponse.Dispose()}
            if (($null -ne $webStream) -and ($webStream -is [System.IDisposable])){$webStream.Dispose()}
            if (($null -ne $respReader) -and ($respReader -is [System.IDisposable])){$respReader.Dispose()}
        }
    }
    finally
    {
        if($DisableCertificateAuthentication -eq $true)
        {
            $script:CertificateAuthenticationFlag = $OrigCertFlag
        }
    }

}

function Test-HPERedfishCertificateAuthentication{
<#
.SYNOPSIS
Tests the status of the server certificate authentication setting.

.DESCRIPTION
The Test-HPERedfishCertificateAuthentication cmdlet gets the status of the remote server certificate authentication setting of the current session. If the status is TRUE, the client looks for a valid iLO certificate to execute the cmdlet and returns an error if the iLO certificate is not valid. If the status is FALSE, the client does not authenticate the server certificate and no errors are generated for non-valid iLO certificates.

.NOTES
Disabling the certificate check should be used until a valid certificate has been installed on the device being connected to. Installing valid certificates that can be verified gives and extra level of network security.

.EXAMPLE
PS C:\> Test-HPERedfishCertificateAuthentication
false


FALSE means that server certificate authentication is disabled for this session of PowerShell.

.LINK
http://www.hpe.com/servers/powershell

#>
   [CmdletBinding(PositionalBinding=$false)]
   param() # no parameters	 
   return $script:CertificateAuthenticationFlag
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
