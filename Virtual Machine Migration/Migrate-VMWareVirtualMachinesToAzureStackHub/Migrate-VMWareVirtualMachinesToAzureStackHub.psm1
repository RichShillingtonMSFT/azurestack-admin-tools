Function Invoke-PowerCLICheck
{
    $PowerCLIModuleAvailable = Find-Module -Name VMware.PowerCLI

    $ModuleCheck = Get-Module -ListAvailable | Where-Object {$_.Name -eq 'VMware.PowerCLI'}
    if (!($ModuleCheck))
    {
        Write-Host "PowerCLI Module Version $($PowerCLIModuleAvailable.Version) was not found."
        Write-Host "Installing PowerCLI Module Version $($PowerCLIModuleAvailable.Version) ..."
        try 
        {
            Install-Module -Name VMware.PowerCLI -RequiredVersion $PowerCLIModuleAvailable.Version -AllowClobber -Force -Verbose     
        }
        catch 
        {
            Write-Warning -Message "Failed to install PowerCLI Version $($PowerCLIModuleAvailable.Version)"
            Write-Warning -Message $_
        }
    }
    else
    {
        if ($ModuleCheck.Version -lt $PowerCLIModuleAvailable.Version)
        {
            Write-Host "You are running an older version of PowerCLI"
            Write-Host "Version $($PowerCLIModuleAvailable.Version) is available"

            # PowerCLI Module Uninstall
            $Yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes'
            $No = New-Object System.Management.Automation.Host.ChoiceDescription '&No'
            $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)
            $Title = 'Update PowerCLI Module?'
            $Message = 'Do you want to remove the PowerCLI Module?'
            $UpdatePowerCLIModule = $host.ui.PromptForChoice($title, $message, $options, 0)

            if ($UpdatePowerCLIModule -eq 0)
            {
                Write-Host "Removing $($ModuleCheck.Name) Module Version $($ModuleCheck.Version) from memory"
                Remove-Module -Name $ModuleCheck.Name -Force -Verbose
                try 
                {
                    Write-Host "Uninstalling $($ModuleCheck.Name) Module Version $($ModuleCheck.Version)"
                    Uninstall-Module -Name $ModuleCheck.Name -Force -Verbose
                    Write-Host "Installing $($PowerCLIModuleAvailable.Name) Module Version $($PowerCLIModuleAvailable.Version)"
                    Install-Module -Name VMware.PowerCLI -RequiredVersion $PowerCLIModuleAvailable.Version -AllowClobber -Force -Verbose
                }
                catch 
                {
                    Write-Warning -Message "Failed to update $($PowerCLIModuleAvailable.Name) to version $($PowerCLIModuleAvailable.Version)"
                    Write-Warning -Message "Please attempt to manually upgrade the module"
                    Write-Warning -Message $_
                    break
                }

            }
            if ($UpdatePowerCLIModule -eq 1)
            {
                Write-Host "PowerCLI is installed."
                Import-Module -Name VMware.PowerCLI -Verbose
            }
        }
    }
}
Export-ModuleMember -Function Invoke-PowerCLICheck

Function Get-VMWareVMMigrationReadinessReport 
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name or IP of vCenter
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name or IP of vCentert. Example vCenter.contoso.local")]
        [String][String]$VCenterHost,

        # Specify the credentials of the Hypervisor Host
        [Parameter(Mandatory=$false,HelpMessage="Specify the credentials to connect to vCenter. Get-Credential")]
        [pscredential]$Credentials,
        
        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    $ErrorActionPreference = 'Stop'

    if (!($Credentials))
    {
        $Credentials = Get-Credential -Message 'Please Enter Your Credentials To Access The Hypervisor Host'
    }

    Write-Host "Checking for PowerCLI"
    Invoke-PowerCLICheck

    try 
    {
        Write-Host "Connecting to vCenter $VCenterHost"
        Connect-VIServer -Server $VCenterHost -Credential $Credentials -Force -Verbose
        Write-Host "Connected to vCenter $VCenterHost"
    }
    catch 
    {
        Write-Warning -Message "Error Connecting to vCenter Host $VCenterHost"
        Write-Warning -Message $_
        break
    }

    Write-Host "Getting list of VMs from $VCenterHost. Please wait..." -ForegroundColor Green
    $VCenterHostVMs = Get-VM | Select-Object -Property *

    $RequirementChecks = @(
        @{RequiredPersistence = "Persistent"}
        @{RequiredVhdType = "Thick"}
        @{RequiredVhdFormat = "VHD"}
    )

    $RequiredDiskSizes = @(
        @{SizeInGB = 128; SizeInBytes = 137438953472}
        @{SizeInGB = 256; SizeInBytes = 274877906944}
        @{SizeInGB = 512; SizeInBytes = 549755813888}
        @{SizeInGB = 1024; SizeInBytes = 1099511627776}
        @{SizeInGB = 2048; SizeInBytes = 2199023255552}
        @{SizeInGB = 4096; SizeInBytes = 4398046511104}
    )

    $MigrationReadyVMs = @()
    $MigrationNotReadyVMs = @()

    foreach ($VM in $VCenterHostVMs) 
    {
        $VMCheckFailCount = 0

        Write-Host "Getting VM Disk Information" -ForegroundColor Green
        $VMDisks = Get-HardDisk -VM $VM.Name | Select-Object -Property *

        foreach ($VMDisk in $VMDisks)
        {
            Write-Host "Checking VM Disk Format" -ForegroundColor Green
            $DiskFormat = $($VMDisk.Filename).Split('.')[-1]
            if ($DiskFormat -ne $RequirementChecks.RequiredVhdFormat)
            {
                $WarningMessage = "$($VM.Name) Disk $($VMDisk.Name) is a $DiskFormat and is not migration ready. The disk must be in VHD format."
                Write-Warning -Message $WarningMessage
                $MigrationNotReadyVMs += New-Object PSObject -Property ([ordered]@{VMName=$($VM.Name);VMHost=$VCenterHost;Disk=$DiskName;DiskType=$($VMDisk.VhdType);Message=$WarningMessage})
                $VMCheckFailCount++
            }

            Write-Host "Checking VM Disk Persistence" -ForegroundColor Green
            if ($VMDisk.Persistence -ne $RequirementChecks.RequiredPersistence)
            {
                $WarningMessage = "$($VM.Name) Disk $($VMDisk.Name) is not migration ready. The VM Must Use Persistent Disks."
                Write-Warning -Message $WarningMessage
                $MigrationNotReadyVMs += New-Object PSObject -Property ([ordered]@{VMName=$($VM.Name);VMHost=$VCenterHost;Message=$WarningMessage})
                $VMCheckFailCount++
            }

            Write-Host "Checking VM Disk Type" -ForegroundColor Green
            if ($VMDisk.StorageFormat -ne $RequirementChecks.RequiredVhdType)
            {
                
                $WarningMessage = "$($VM.Name) Disk $($VMDisk.Name) is not migration ready. The VM Must Use Thick Disks."
                Write-Warning -Message $WarningMessage
                $MigrationNotReadyVMs += New-Object PSObject -Property ([ordered]@{VMName=$($VM.Name);VMHost=$VCenterHost;Message=$WarningMessage})
                $VMCheckFailCount++
            }

            Write-Host "Checking VM Disk Size" -ForegroundColor Green
            if ($VMDisk.CapacityGB -notin $($RequiredDiskSizes.SizeInGB))
            {
                $RecommendedDiskSize = ($RequiredDiskSizes.SizeInGB | Where-Object {$_ -ge $CurrentDiskSizeInGB})[0]
                $Message = "$($VM.Name) Disk $($VMDisk.Name) is currently $($VMDisk.CapacityGB) GB. You must resize the disk to $RecommendedDiskSize GB."
                Write-Warning -Message $Message
                $MigrationNotReadyVMs += New-Object PSObject -Property ([ordered]@{VMName=$($VM.Name);VMHost=$VCenterHost;Disk=$DiskName;DiskSize=$CurrentDiskSizeInGB;Message=$Message})
                $VMCheckFailCount++
            }
        }

        if ($VMCheckFailCount -eq 0)
        {
            Write-Host "Virtual Machine $($VM.VMName) on host $VCenterHost is ready to migrate."
            $MigrationReadyVMs += New-Object PSObject -Property ([ordered]@{VMName=$($VM.Name);VMHost=$VCenterHost;Status='Ready To Migrate'})
        }
    }

    $MigrationReadyVMs | Export-Csv $FileSaveLocation\$('VMWareVMsReadyForMigration-' + $(Get-Date -f yyyy-MM-dd) + '.csv') -NoTypeInformation
    $MigrationNotReadyVMs | Export-Csv $FileSaveLocation\$('VMWareVMsNOTReadyForMigration-' + $(Get-Date -f yyyy-MM-dd) + '.csv') -NoTypeInformation
}
Export-ModuleMember -Function Get-VMWareVMMigrationReadinessReport

Function Install-WindowsAzureVirtualMachineAgent
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the credentials to connect to the virtual machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the credentials to connect to the virtual machine.")]
        [pscredential]$VirtualMachineCredentials,

        # Specify the path to store the Azure Virtual Machine Agent File
        [Parameter(Mandatory=$false,HelpMessage="Specify the path to store the Azure Virtual Machine Agent File. Example C:\AzureVirtualMachineAgent")]
        [string]$DownloadPath = 'C:\AzureVirtualMachineAgent'
    )

    $ErrorActionPreference = 'Stop'

    $VirtualMachineAgentUri = "https://go.microsoft.com/fwlink/?LinkID=394789"
    try
    {
        Test-NetConnection microsoft.com -CommonTCPPort HTTP -WarningAction Stop
    }
    catch
    {
        Write-Warning "Please make sure you have Internet Access and try again!"
        break
    }

    # File Destination
    $File = "$DownloadPath\WindowsAzureVmAgent.msi"

    # Validate Destination
    Write-Host "Checking Folder Path $DownloadPath"
    if (!(Test-Path $DownloadPath)) 
    {
        # Create the Download folder
        $null = New-Item -Type Directory -Path $DownloadPath -Force

        Write-Host "Checking if Azure Virtual Machine Agent is already downloaded"
        if (!(Test-Path $File))
        {
            # Download AzCopy zip for Windows
            Write-Host "Azure Virtual Machine Agent was not found. Downloading..."
            Start-BitsTransfer -Source $VirtualMachineAgentUri -Destination $File
        }
    }
    else 
    {
        Write-Host "Checking if Azure Virtual Machine Agent is already downloaded"
        if (!(Test-Path $File))
        {
            # Download AzCopy zip for Windows
            Write-Host "Azure Virtual Machine Agent was not found. Downloading..."
            Start-BitsTransfer -Source $VirtualMachineAgentUri -Destination $File
        }
    }
   
    $Session = New-PSSession -Credential $VirtualMachineCredentials -ComputerName $VirtualMachineName
    $RootPath = '\\' + $VirtualMachineName + '\Admin$'

    $PSDriveLetter = (Get-ChildItem Function:[f-z]: -n | Where-Object { !(test-path $_) } | Select-Object -First 1)
    try
    {
        $PSDrive = New-PSDrive -Name ($PSDriveLetter.Replace(':','')) -Credential $VirtualMachineCredentials -PSProvider FileSystem -Root $RootPath -Persist -ErrorAction Stop
    }
    catch [Exception]
    {
        if ($_.Exception -like "*The network path was not found*")
        {
            Write-Warning -Message "Could Not Connect to $RootPath"
            Write-Warning -Message "Please ensure that the Virtual Machine is Powered On, You have the correct permissions and file transfer is allowed in the Firewall."
            break
        }
        else
        {
            Write-Error $_.Exception
        }
    }

    $RemoteFolderPath = "$PSDriveLetter\AzureVirtualMachineAgent"
    $RemoteFilePath = "$RemoteFolderPath\WindowsAzureVmAgent.msi"

    # Validate Destination
    Write-Host "Checking Remote Folder Path $RemoteFolderPath"
    if (!(Test-Path $RemoteFolderPath)) 
    {
        # Create the Download folder
        Write-Host "Creating Directory $RemoteFolderPath"
        try 
        {
            New-Item -Type Directory -Path $RemoteFolderPath -Force -ErrorAction Stop | Out-Null
        }
        catch 
        {
            Write-Warning -Message "Error Creating Folder $RemoteFolderPath"
            break
        }
        
    }
    else 
    {
        Write-Host "Checking if Azure Virtual Machine Agent is already downloaded on the remote machine."
        if (!(Test-Path $RemoteFilePath))
        {
            # Download AzCopy zip for Windows
            Write-Host "Azure Virtual Machine Agent was not found. Copying..."
            try 
            {
                Copy-Item $File $RemoteFilePath -ErrorAction Stop
            }
            catch 
            {
                Write-Warning -Message "Error Copying File $RemoteFilePath"
                break
            }
        }
    }

    Write-Host "Installing Azure Virtual Machine Agent on $VirtualMachineName..."
    Invoke-Command -Session $Session -ScriptBlock {Start-Process msiexec.exe -ArgumentList "/package C:\Windows\AzureVirtualMachineAgent\WindowsAzureVmAgent.msi /quiet /log C:\Windows\AzureVirtualMachineAgent\install.log" -Wait}
    
    # Remove Persistent Drive
    $PSDrive | Remove-PSDrive -Force
    net use * /d /y | Out-Null

    Remove-PSSession $Session
}
Export-ModuleMember -Function Install-WindowsAzureVirtualMachineAgent

Function Invoke-WindowsAzureVirtualMachineSettingsConfiguration
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the credentials to connect to the virtual machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the credentials to connect to the virtual machine.")]
        [pscredential]$VirtualMachineCredentials
    )

    Write-Host "Making changes to $VirtualMachineName to support running on Azure"
    $Session = New-PSSession -Credential $VirtualMachineCredentials -ComputerName $VirtualMachineName

    Invoke-Command -Session $Session -ScriptBlock {
        try 
        {
            reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 01 /t REG_DWORD /d 0 /f

            netsh.exe winhttp reset proxy
        
            Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation -Name RealTimeIsUniversal -Value 1 -Type DWord -Force -Verbose
            Set-Service -Name w32time -StartupType Automatic -Verbose
        
            powercfg.exe /setactive SCHEME_MIN
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name TEMP -Value "%SystemRoot%\TEMP" -Type ExpandString -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name TMP -Value "%SystemRoot%\TEMP" -Type ExpandString -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fDenyTSConnections -Value 0 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name PortNumber -Value 3389 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name LanAdapter -Value 0 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SecurityLayer -Value 1 -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name fAllowSecProtocolNegotiation -Value 1 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name KeepAliveEnable -Value 1  -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name KeepAliveInterval -Value 1  -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name KeepAliveTimeout -Value 1 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fDisableAutoReconnect -Value 0 -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name fInheritReconnectSame -Value 1 -Type DWord -Force -Verbose
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name fReconnectSame -Value 0 -Type DWord -Force -Verbose
        
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name MaxInstanceCount -Value 4294967295 -Type DWord -Force -Verbose
        
            if ((Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').Property -contains 'SSLCertificateSHA1Hash')
            {
                Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SSLCertificateSHA1Hash -Force -Verbose
            }
        
            Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -Verbose
        
            Enable-PSRemoting -Force -Verbose

            Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -Enabled True -Verbose
        
            Set-NetFirewallRule -DisplayGroup 'Remote Desktop' -Enabled True -Verbose
        
            Set-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -Enabled True -Verbose
        }
        catch
        {
            Write-Warning $_
            break
        }
    }

    Remove-PSSession $Session
    Write-Host "Azure Virtual Machine Settings Configuration Complete" -ForegroundColor Green
}
Export-ModuleMember -Function Invoke-WindowsAzureVirtualMachineSettingsConfiguration

Function Invoke-VMWareVMExport
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the Name or IP of vCenter
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name or IP of vCentert. Example vCenter.contoso.local")]
        [String][String]$VCenterHost,

        # Specify the credentials of the Hypervisor Host
        [Parameter(Mandatory=$false,HelpMessage="Specify the credentials to connect to vCenter. Get-Credential")]
        [pscredential]$Credentials,
        
        # Specify the output location to store the Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the output location to store the Virtual Machine. Example C:\Temp")]
        [String]$VMSaveLocation,

        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    $ErrorActionPreference = 'Stop'

    if (!($Credentials))
    {
        $Credentials = Get-Credential -Message 'Please Enter Your Credentials To Access The Hypervisor Host'
    }

    Write-Host "Checking for PowerCLI"
    Invoke-PowerCLICheck

    try 
    {
        Write-Host "Connecting to vCenter $VCenterHost"
        Connect-VIServer -Server $VCenterHost -Credential $Credentials -Force -Verbose
        Write-Host "Connected to vCenter $VCenterHost"
    }
    catch 
    {
        Write-Warning -Message "Error Connecting to vCenter Host $VCenterHost"
        Write-Warning -Message $_
        break
    }

    # Power Off VM If Running
    Write-Host "Checking VM Power State"
    $VirtualMachine = Get-VM -Name $VirtualMachineName
    if ($VirtualMachine.PowerState -ne 'PoweredOff')
    {
        Write-Warning -Message "Virtual Machine $VirtualMachineName will be powered off."
        $VirtualMachine | Stop-VM -Verbose
        while ((Get-VM -Name $VirtualMachineName).PowerState -ne 'PoweredOff') 
        {
            Write-Warning -Message "Waiting for Virtual Machine $VirtualMachineName to power off..."
            Start-Sleep -Seconds 5
        }
    }

    try 
    {
        Write-Host "Exporting Virtual Machine $VirtualMachineName to $VMSaveLocation"
        Write-Host "This may take a while. Please wait..."
        $Export = Export-VApp -VM $VirtualMachineName -Destination $VMSaveLocation  
        Write-Host "Virtual Machine $VirtualMachineName has been exported to $VMSaveLocation" -ForegroundColor Green
    }
    catch 
    {
        Write-Warning -Message "Failed to export Virtual Machine $VirtualMachineName to $VMSaveLocation"
        $_
        break
    }

    $Export | Select-Object BaseName,Name,DirectoryName,FullName,Extension | Export-Csv $FileSaveLocation\$($VirtualMachineName + '-ExportData' + '.csv') -NoTypeInformation
}
Export-ModuleMember -Function Invoke-VMWareVMExport

Function Convert-VMDKToVHD
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    try 
    {
        Import-Module 'C:\Program Files\Microsoft Virtual Machine Converter\MvmcCmdlet.psd1' -ErrorAction Stop
    }
    catch 
    {
        Write-Warning -Message "Could not load Microsoft Virtual Machine Converter Module"
        Write-Warning -Message "Please verify that Microsoft Virtual Machine Converter is installed and try again."
    }

    $VirtualMachineFiles = Import-Csv ($FileSaveLocation + '\' + $VirtualMachineName + '-ExportData' + '.csv')
    $VirtualMachineVMDKLocations = ($VirtualMachineFiles | Where-Object {$_.FullName -like "*.vmdk"}).FullName

    foreach ($VirtualMachineVMDK in $VirtualMachineVMDKLocations)
    {
        Write-Host "Converting VMDK $VirtualMachineVMDK to a Fixed Size VHD File. This may take a while..."
        $DestinationPath = $VirtualMachineVMDK.Replace('vmdk','vhd')
        try 
        {
            ConvertTo-MvmcVirtualHardDisk -SourceLiteralPath $VirtualMachineVMDK -DestinationLiteralPath $DestinationPath -VhdType FixedHardDisk -VhdFormat Vhd -Verbose
        }
        catch 
        {
            Write-Warning -Message "Failed to convert $VirtualMachineVMDK to a Fixed Size VHD File."
            break
        }
    }
}
Export-ModuleMember -Function Convert-VMDKToVHD

Function Invoke-VMWareVHDRightSizing
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )
    
    $ModuleCheck = Get-Module | Where-Object {$_.Name -eq 'VMware.PowerCLI'}
    if ($ModuleCheck)
    {
        Remove-Module -Name 'VMware.PowerCLI' -Force
    }

    Import-Module Hyper-V -Force

    $RequiredDiskSizes = @(
        @{SizeInGB = 128; SizeInBytes = 137438953472}
        @{SizeInGB = 256; SizeInBytes = 274877906944}
        @{SizeInGB = 512; SizeInBytes = 549755813888}
        @{SizeInGB = 1024; SizeInBytes = 1099511627776}
        @{SizeInGB = 2048; SizeInBytes = 2199023255552}
        @{SizeInGB = 4096; SizeInBytes = 4398046511104}
    )
    
    Write-Host "Getting VM Disk Information" -ForegroundColor Green
    $VirtualMachineFiles = Import-Csv ($FileSaveLocation + '\' + $VirtualMachineName + '-ExportData' + '.csv')
   
    $VMDiskFiles = Get-ChildItem $VirtualMachineFiles[0].DirectoryName -Recurse -Include *.vhd

    foreach ($VMDiskFile in $VMDiskFiles)
    {
        $VMDisk = Get-VHD $VMDiskFile.FullName
        $DiskName = $($VMDisk.Path.Split('\') | Select-Object -Last 1)
        
        Write-Host "Checking $DiskName Disk Size" -ForegroundColor Green
        [Int]$CurrentDiskSizeInGB = (($VMDisk.Size)/1gb)
        if ($CurrentDiskSizeInGB -notin $($RequiredDiskSizes.SizeInGB))
        {
            [String]$RecommendedDiskSize = ($RequiredDiskSizes.SizeInGB | Where-Object {$_ -ge $CurrentDiskSizeInGB})[0]
            $NewDiskSizeInBytes = ($RequiredDiskSizes | Where-Object {$_.SizeInGB -eq $RecommendedDiskSize}).SizeInBytes
            $Message = "$($VirtualMachine.Name) Disk $DiskName is currently $CurrentDiskSizeInGB GB. I will resize the new VHD disk to $RecommendedDiskSize GB using Resize-VHD"
            Write-Warning -Message $Message
            Write-Host "Resizing Disk $($VMDisk.Path) to $RecommendedDiskSize GB. This may take a while..."
 
            try
            {
                Resize-VHD -Path $VMDisk.Path -SizeBytes $NewDiskSizeInBytes -Verbose
            }
            catch
            {
                Write-Warning $_
                break
            }
            
            Write-Host "Disk $($VMDisk.Path) is now $($RecommendedDiskSize + 'GB')" -ForegroundColor Green
        }
    }
    Write-Host "Disk Resizing Complete" -ForegroundColor Green
}
Export-ModuleMember -Function Invoke-HyperVVHDRightSizing

Function Invoke-CreateAuthHeader
{
    $AzureContext = Get-AzureRmContext
    $AzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $ProfileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($AzureProfile)
    $Token = $ProfileClient.AcquireAccessToken($AzureContext.Subscription.TenantId)
    $AuthHeader = @{
        'Content-Type'='application/json'
        'Authorization'='Bearer ' + $Token.AccessToken
    }

    return $AuthHeader
}
Export-ModuleMember -Function Invoke-CreateAuthHeader

Function Invoke-ResourceNameAvailability 
{
    [CmdletBinding()]
    Param 
    (
        
        [Parameter(Mandatory=$true,HelpMessage="Provide your Subscription ID. Example ddce26e8-4d72-4881-ae59-4b34d999528d")]
        $SubscriptionID,

        [Parameter(Mandatory=$true,HelpMessage="Specify the Name for the Resource. Example storageaccountname")]
        $ResourceName,

        [Parameter(Mandatory=$true,HelpMessage="Example Microsoft.Storage")]
        $ResourceKind,

        [Parameter(Mandatory=$true,HelpMessage="Example Microsoft.Storage/storageAccounts")]
        $ResourceType
    )

    $AzureContext = Get-AzureRmContext
    $restUri = $($AzureContext.Environment.ResourceManagerUrl) + "/subscriptions/$SubscriptionID/providers/$ResourceKind/checkNameAvailability?api-version=2017-10-01"
    
    $AuthHeader = Invoke-CreateAuthHeader
    $Body= @{
        'Name' = "$ResourceName"
        'Type' = "$ResourceType"
    } | ConvertTo-Json
    $Results = Invoke-RestMethod -Uri $restUri -Method Post -Headers $AuthHeader -Body $Body
    return $Results
}
Export-ModuleMember -Function Invoke-ResourceNameAvailability

Function Invoke-IPConfigurationsQuery
{
    [CmdletBinding()]
    Param 
    (
        [Parameter(Mandatory=$true,HelpMessage="Provide your Subscription ID. Example: ddce26e8-4d72-4881-ae59-4b34d999528d")]
        $SubscriptionID,

        [Parameter(Mandatory=$true,HelpMessage="Provide VNet Resource Group Name. Example: VNet-RG")]
        $ResourceGroupName,

        [Parameter(Mandatory=$true,HelpMessage="Provide the Virtual Network Name. Example: Vnet-001")]
        $VirtualNetworkName
    )

    $AzureContext = Get-AzureRmContext
    $restUri = $($AzureContext.Environment.ResourceManagerUrl) + "/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$VirtualNetworkName" + '?api-version=2017-10-01&$expand=subnets/ipConfigurations'
    $AuthHeader = Invoke-CreateAuthHeader
    $Results = Invoke-RestMethod -Uri $restUri -Method Get -Headers $AuthHeader
    return $Results
}
Export-ModuleMember -Function Invoke-ipConfigurationsQuery

Function Install-AzCopy 
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false,HelpMessage="Provide the path to AzCopy. Example: C:\AzCopy")]
        [string]$InstallPath = 'C:\AzCopy'
    )

    # Cleanup Destination
    if (Test-Path $InstallPath) {
        Get-ChildItem $InstallPath | Remove-Item -Confirm:$false -Force
    }

    # Zip Destination
    $zip = "$InstallPath\AzCopy.Zip"

    # Create the installation folder (eg. C:\AzCopy)
    $null = New-Item -Type Directory -Path $InstallPath -Force

    # Download AzCopy zip for Windows
    Start-BitsTransfer -Source "https://aka.ms/downloadazcopy-v10-windows" -Destination $zip

    # Expand the Zip file
    Expand-Archive $zip $InstallPath -Force

    # Move to $InstallPath
    Get-ChildItem "$($InstallPath)\*\*" | Move-Item -Destination "$($InstallPath)\" -Force

    #Cleanup - delete ZIP and old folder
    Remove-Item $zip -Force -Confirm:$false
    Get-ChildItem "$($InstallPath)\*" -Directory | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -Confirm:$false }

    # Add InstallPath to the System Path if it does not exist
    if ($env:PATH -notcontains $InstallPath) {
        $path = ($env:PATH -split ";")
        if (!($path -contains $InstallPath)) {
            $path += $InstallPath
            $env:PATH = ($path -join ";")
            $env:PATH = $env:PATH -replace ';;',';'
        }
        [Environment]::SetEnvironmentVariable("Path", ($env:path), [System.EnvironmentVariableTarget]::Machine)
    }
}
Export-ModuleMember -Function Install-AzCopy

Function Get-IPAddressesInSubnet
{
    [CmdletBinding()]
    Param
    (
        # CIDR notation network address, or using subnet mask. Examples: '192.168.0.1/24', '10.20.30.40/255.255.0.0'.
        [Parameter(Mandatory=$True,HelpMessage='CIDR notation network address, or using subnet mask. Examples: 192.168.0.1/24, 10.20.30.40/255.255.0.0')]
        [String]$NetworkAddress
    )

    $IPv4Regex = '(?:(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)\.){3}(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)'

    Function Convert-IPToBinary
    {
        Param(
            [string] $IP
        )
        $IP = $IP.Trim()
        if ($IP -match "\A${IPv4Regex}\z")
        {
            try
            {
                return ($IP.Split('.') | ForEach-Object { [System.Convert]::ToString([byte] $_, 2).PadLeft(8, '0') }) -join ''
            }
            catch
            {
                Write-Warning -Message "Error converting '$IP' to a binary string: $_"
                return $Null
            }
        }
        else
        {
            Write-Warning -Message "Invalid IP detected: '$IP'."
            return $Null
        }
    }

    Function Convert-BinaryToIP
    {
        Param(
            [string] $Binary
        )
        $Binary = $Binary -replace '\s+'
        if ($Binary.Length % 8)
        {
            Write-Warning -Message "Binary string '$Binary' is not evenly divisible by 8."
            return $Null
        }
        [int] $NumberOfBytes = $Binary.Length / 8
        $Bytes = @(foreach ($i in 0..($NumberOfBytes-1))
        {
            try
            {
                [System.Convert]::ToByte($Binary.Substring(($i * 8), 8), 2)
            }
            catch
            {
                Write-Warning -Message "Error converting '$Binary' to bytes. `$i was $i."
                return $Null
            }
        })
        return $Bytes -join '.'
    }

    Function Get-ProperCIDR
    {
        Param(
            [string] $CIDRString
        )
        $CIDRString = $CIDRString.Trim()
        $Object = '' | Select-Object -Property IP, NetworkLength
        if ($CIDRString -match "\A(?<IP>${IPv4Regex})\s*/\s*(?<NetworkLength>\d{1,2})\z")
        {
            if ([int] $Matches['NetworkLength'] -lt 0 -or [int] $Matches['NetworkLength'] -gt 32)
            {
                Write-Warning "Network length out of range (0-32) in CIDR string: '$CIDRString'."
                return
            }
            $Object.IP = $Matches['IP']
            $Object.NetworkLength = $Matches['NetworkLength']
        }
        elseif ($CIDRString -match "\A(?<IP>${IPv4Regex})[\s/]+(?<SubnetMask>${IPv4Regex})\z")
        {
            $Object.IP = $Matches['IP']
            $SubnetMask = $Matches['SubnetMask']
            if (-not ($BinarySubnetMask = Convert-IPToBinary $SubnetMask))
            {
                return
            }
            if ((($BinarySubnetMask) -replace '\A1+') -match '1')
            {
                Write-Warning -Message "Invalid subnet mask in CIDR string '$CIDRString'. Subnet mask: '$SubnetMask'."
                return
            }
            $Object.NetworkLength = [regex]::Matches($BinarySubnetMask, '1').Count
        }
        else
        {
            Write-Warning -Message "Invalid CIDR string: '${CIDRString}'. Valid examples: '192.168.1.0/24', '10.0.0.0/255.0.0.0'."
            return
        }
        if ($Object.IP -match '\A(?:(?:1\.){3}1|(?:0\.){3}0)\z')
        {
            Write-Warning "Invalid IP detected in CIDR string '${CIDRString}': '$($Object.IP)'. An IP can not be all ones or all zeroes."
            return
        }
        return $Object
    }

    Function Get-NetworkInformationFromProperCIDR
    {
        Param(
            [psobject] $CIDRObject
        )
        $Object = '' | Select-Object -Property IP, NetworkLength, SubnetMask, NetworkAddress, HostMin, HostMax, 
            Broadcast, UsableHosts, TotalHosts, IPEnumerated, BinaryIP, BinarySubnetMask, BinaryNetworkAddress,
            BinaryBroadcast
        $Object.IP = [string] $CIDRObject.IP
        $Object.BinaryIP = Convert-IPToBinary $Object.IP
        $Object.NetworkLength = [int32] $CIDRObject.NetworkLength
        $Object.SubnetMask = Convert-BinaryToIP ('1' * $Object.NetworkLength).PadRight(32, '0')
        $Object.BinarySubnetMask = ('1' * $Object.NetworkLength).PadRight(32, '0')
        $Object.BinaryNetworkAddress = $Object.BinaryIP.SubString(0, $Object.NetworkLength).PadRight(32, '0')
        $Object.NetworkAddress = Convert-BinaryToIP $Object.BinaryNetworkAddress
        if ($Object.NetworkLength -eq 32 -or $Object.NetworkLength -eq 31)
        {
            $Object.HostMin = $Object.IP
        }
        else
        {
            $Object.HostMin = Convert-BinaryToIP ([System.Convert]::ToString(([System.Convert]::ToInt64($Object.BinaryNetworkAddress, 2) + 1), 2)).PadLeft(32, '0')
        }

        [string] $BinaryBroadcastIP = $Object.BinaryNetworkAddress.SubString(0, $Object.NetworkLength).PadRight(32, '1')
        $Object.BinaryBroadcast = $BinaryBroadcastIP
        [int64] $DecimalHostMax = [System.Convert]::ToInt64($BinaryBroadcastIP, 2) - 1
        [string] $BinaryHostMax = [System.Convert]::ToString($DecimalHostMax, 2).PadLeft(32, '0')
        $Object.HostMax = Convert-BinaryToIP $BinaryHostMax
        $Object.TotalHosts = [int64][System.Convert]::ToString(([System.Convert]::ToInt64($BinaryBroadcastIP, 2) - [System.Convert]::ToInt64($Object.BinaryNetworkAddress, 2) + 1))
        $Object.UsableHosts = $Object.TotalHosts - 2
        if ($Object.NetworkLength -eq 32)
        {
            $Object.Broadcast = $Null
            $Object.UsableHosts = [int64] 1
            $Object.TotalHosts = [int64] 1
            $Object.HostMax = $Object.IP
        }
        elseif ($Object.NetworkLength -eq 31)
        {
            $Object.Broadcast = $Null
            $Object.UsableHosts = [int64] 2
            $Object.TotalHosts = [int64] 2
            [int64] $DecimalHostMax2 = [System.Convert]::ToInt64($BinaryBroadcastIP, 2)
            [string] $BinaryHostMax2 = [System.Convert]::ToString($DecimalHostMax2, 2).PadLeft(32, '0')
            $Object.HostMax = Convert-BinaryToIP $BinaryHostMax2
        }
        elseif ($Object.NetworkLength -eq 30)
        {
            $Object.UsableHosts = [int64] 2
            $Object.TotalHosts = [int64] 4
            $Object.Broadcast = Convert-BinaryToIP $BinaryBroadcastIP
        }
        else
        {
            $Object.Broadcast = Convert-BinaryToIP $BinaryBroadcastIP
        }
        $Object.IPEnumerated = @()
        return $Object
    }

    Function New-IPRange ($start, $end)
    {
        $ip1 = ([System.Net.IPAddress]$start).GetAddressBytes()
        [Array]::Reverse($ip1)
        $ip1 = ([System.Net.IPAddress]($ip1 -join '.')).Address
        $ip2 = ([System.Net.IPAddress]$end).GetAddressBytes()
        [Array]::Reverse($ip2)
        $ip2 = ([System.Net.IPAddress]($ip2 -join '.')).Address
  
        for ($x=$ip1; $x -le $ip2; $x++)
            {
                $ip = ([System.Net.IPAddress]$x).GetAddressBytes()
                [Array]::Reverse($ip)
                $ip -join '.'
            }
    }

    $SubnetDetails = $NetworkAddress | ForEach-Object { Get-ProperCIDR $_ } | ForEach-Object { Get-NetworkInformationFromProperCIDR $_ }
    $IPsInRange = New-IPRange -start $SubnetDetails.HostMin -end $SubnetDetails.HostMax
    return $IPsInRange
}
Export-ModuleMember -Function Get-IPAddressesInSubnet

Function Invoke-PublicIPCreation
{
    [CmdletBinding()]
    Param 
    (
        [Parameter(Mandatory=$true,HelpMessage='Specify the Public IP Assignment Type. Example: Static or Dynamic')]
        [ValidateSet('Static','Dynamic')]
        [String]$IPAddressType
    )

    $PublicIPNameCheckRegEx = '^[a-zA-Z0-9](?:[a-zA-Z0-9_-]*[a-zA-Z0-9])?$'

    # Create Public IP
    $ResourceNameAvailability = $false
    $ResourceNameValidation = $false
                    
    do 
    {
        $PublicIPName = Read-Host "Please provide a name for the Public IP"
                
        if (($PublicIPName -match $PublicIPNameCheckRegEx) -and ($PublicIPName.Length -ge 1) -and ($PublicIPName.Length -lt 80))
        {
            $ResourceNameValidation = $true
            $ResourceNameAvailabilityCheck = Get-AzureRmPublicIpAddress | Where-Object {$_.Name -eq $PublicIPName}  -ErrorAction SilentlyContinue
        }

        if ($PublicIPName -notmatch $PublicIPNameCheckRegEx)
        {
            Write-Warning -Message 'Public IP names only allow alphanumeric characters, periods, underscores, hyphens and parenthesis and cannot end in a period.'
        }

        if (($PublicIPName.Length -lt 1) -or ($PublicIPName.Length -gt 80))
        {
            Write-Warning -Message 'Public IP Names may only be between 1 and 90 characters'
        }
                
        if ($ResourceNameAvailabilityCheck)
        {
            Write-Warning -Message "Public IP Name $PublicIPName Already Exists"
            Write-Warning -Message "Please Choose Another Name"
            $ResourceNameAvailabilityCheck = Get-AzureRmPublicIpAddress | Where-Object {$_.Name -eq $PublicIPName} -ErrorAction SilentlyContinue
        }

        else
        {
            $ResourceNameAvailability = $true
        }

    }
    until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

    $PublicIP = New-AzureRmPublicIpAddress -Name $PublicIPName -ResourceGroupName $ResourceGroup.ResourceGroupName -Location $Location -AllocationMethod $IPAddressType
 
    return $PublicIP
}
Export-ModuleMember -Function Invoke-PublicIPCreation

Function Invoke-ResourceGroupSelectionCreation
{
    [CmdletBinding()]
    Param 
    (
        [Parameter(Mandatory=$true,HelpMessage='Provide a message to be displayed in the selection window.')]
        [String]$ResourceGroupMessage
    )

    $ResourceGroups = @()
    $ResourceGroups += 'New'
    $ResourceGroups += (Get-AzureRMResourceGroup).ResourceGroupName

    $ResourceGroupNameCheckRegEx = '^[-\w\._\(\)]*[-\w_\(\)]$'

    $ResourceGroupName = $ResourceGroups | Out-GridView -Title "$ResourceGroupMessage" -PassThru

    if ($ResourceGroupName -eq 'New')
    {
        # Create Resource Group
        $ResourceNameAvailability = $false
        $ResourceNameValidation = $false
                    
        do 
        {
            $ResourceGroupName = Read-Host "Please Enter a name for the Resource Group"
                
            if (($ResourceGroupName -match $ResourceGroupNameCheckRegEx) -and ($ResourceGroupName.Length -ge 1) -and ($ResourceGroupName.Length -lt 80))
            {
                $ResourceNameValidation = $true
                $ResourceNameAvailabilityCheck = Get-AzureRMResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            }

            if ($ResourceGroupName -notmatch $ResourceGroupNameCheckRegEx)
            {
                Write-Warning -Message 'Resource group names only allow alphanumeric characters, periods, underscores, hyphens and parenthesis and cannot end in a period.'
            }

            if (($ResourceGroupName.Length -lt 1) -or ($ResourceGroupName.Length -gt 90))
            {
                Write-Warning -Message 'Resource Group Names may only be between 1 and 90 characters'
            }
                
            if ($ResourceNameAvailabilityCheck)
            {
                Write-Warning -Message "Resource Group Name $ResourceGroupName Already Exists"
                Write-Warning -Message "Please Choose Another Name"
                $ResourceNameAvailabilityCheck = Get-AzureRMResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            }

            else
            {
                $ResourceNameAvailability = $true
            }

        } 
        until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

        $ResourceGroup = New-AzureRMResourceGroup -Name $ResourceGroupName -Location $Location -Verbose
    }
    else 
    {
        $ResourceGroup = Get-AzureRMResourceGroup -Name $ResourceGroupName
    }

    return $ResourceGroup

}
Export-ModuleMember -Function Invoke-ResourceGroupSelectionCreation

Function Invoke-StorageAccountSelectionCreation
{
    [CmdletBinding()]
    Param ()
    
    $Location = (Get-AzureRMLocation).Location
    
    $StorageAccounts = @()
    $StorageAccounts += 'New'
    $StorageAccounts += (Get-AzureRMStorageAccount).StorageAccountName
    $DestinationStorageAccountName = $StorageAccounts | Out-GridView -Title "Please Select an existing or new storage account." -PassThru

    If ($DestinationStorageAccountName -eq 'New')
    {
        $ResourceGroups = @()
        $ResourceGroups += 'New'
        $ResourceGroups += (Get-AzureRMResourceGroup).ResourceGroupName

        $ResourceGroupNameCheckRegEx = '^[-\w\._\(\)]*[-\w_\(\)]$'

        $StorageAccountResourceGroupName = $ResourceGroups | Out-GridView -Title "Please Select an existing or new Resource Group for the Storage Account." -PassThru

        if ($StorageAccountResourceGroupName -eq 'New')
        {
            # Create Resource Group
            $ResourceNameAvailability = $false
            $ResourceNameValidation = $false
                    
            do 
            {
                $StorageAccountResourceGroupName = Read-Host "Please Enter a name for the Resource Group"
                
                if (($StorageAccountResourceGroupName -match $ResourceGroupNameCheckRegEx) -and ($StorageAccountResourceGroupName.Length -ge 1) -and ($StorageAccountResourceGroupName.Length -lt 80))
                {
                    $ResourceNameValidation = $true
                    $ResourceNameAvailabilityCheck = Get-AzureRMResourceGroup -Name $StorageAccountResourceGroupName -ErrorAction SilentlyContinue
                }
                if ($StorageAccountResourceGroupName -notmatch $ResourceGroupNameCheckRegEx)
                {
                    Write-Warning -Message 'Resource group names only allow alphanumeric characters, periods, underscores, hyphens and parenthesis and cannot end in a period.'
                }
                if (($StorageAccountResourceGroupName.Length -lt 1) -or ($StorageAccountResourceGroupName.Length -gt 90))
                {
                    Write-Warning -Message 'Resource Group Names may only be between 1 and 90 characters'
                }
                
                if ($ResourceNameAvailabilityCheck)
                {
                    Write-Warning -Message "Resource Group Name $StorageAccountResourceGroupName Already Exists"
                    Write-Warning -Message "Please Choose Another Name"
                    $ResourceNameAvailabilityCheck = Get-AzureRMResourceGroup -Name $StorageAccountResourceGroupName -ErrorAction SilentlyContinue
                }
                else
                {
                    $ResourceNameAvailability = $true
                }

            } 
            until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

            $StorageAccountResourceGroup = New-AzureRMResourceGroup -Name $StorageAccountResourceGroupName -Location $Location -Verbose
        }
        else 
        {
            $StorageAccountResourceGroup = Get-AzureRMResourceGroup -Name $StorageAccountResourceGroupName
        }

        # Create Storage Account
        $ResourceNameAvailability = $false
        $ResourceKind = 'Microsoft.Storage'
        $ResourceType = 'Microsoft.Storage/storageAccounts'

        do 
        {
            $StorageAccountName = Read-Host "Please Enter a name for the new Storage Account"
            $ResourceNameCheck = Invoke-ResourceNameAvailability -ResourceName $StorageAccountName -ResourceType $ResourceType -SubscriptionID $SubscriptionID -ResourceKind $ResourceKind
            if (($ResourceNameCheck).nameAvailable -eq $true)
            {
                $ResourceNameAvailability = $true
            }
            else 
            {
                Write-Warning -message $ResourceNameCheck.message
            }
            
        } 
        until ($ResourceNameAvailability -eq $true)

        $DestinationStorageAccount = New-AzureRMStorageAccount -Name $StorageAccountName -ResourceGroupName $StorageAccountResourceGroup.ResourceGroupName -Location $Location -SkuName Standard_LRS -Kind Storage -Verbose

        # Create Storage Account Container
        $ResourceNameAvailability = $false
        $StorageAccountContainerNameRegex = '^[a-z0-9]+(-[a-z0-9]+)*$'

        do 
        {
            $StorageAccountContainerName = Read-Host "Please Choose a name for the Storage Account Container"
            if ($StorageAccountContainerName -notmatch $StorageAccountContainerNameRegex)
            {
                Write-Warning -Message 'Container names must be lowercase letters, numbers, and hyphens. It must Start with lowercase letter or number and cannot use consecutive hyphens'
            }
            if (($StorageAccountContainerName.Length -lt 3) -or ($StorageAccountContainerName.Length -gt 63))
            {
                Write-Warning -Message 'Container names must be between 3 and 63 characters'
            }
            elseif (($StorageAccountContainerName -match $StorageAccountContainerNameRegex) -and ($StorageAccountContainerName.Length -ge 3) -and ($StorageAccountContainerName.Length -le 63))
            {
                $ResourceNameAvailability = $true
            }
        } 
        until ($ResourceNameAvailability -eq $true)

        $DestinationStorageAccountContainer = New-AzureStorageContainer -Context $DestinationStorageAccount.Context -Name $StorageAccountContainerName -Permission Blob -Verbose

    }
    else 
    {
        # Proceed with existing Storage Account
        $DestinationStorageAccount = Get-AzureRMStorageAccount | Where-Object {$_.StorageAccountName -eq $DestinationStorageAccountName} | Select-Object -Property *
        $DestinationStorageAccountContainers = Get-AzureStorageContainer -Context $DestinationStorageAccount.Context | Where-Object {$_.PublicAccess -eq 'Blob'}
        if ($DestinationStorageAccountContainers.count -lt 1)
        {
            Write-Warning "No Containters Found with anonymous read access for blobs only"
            Write-Warning "Please change the container permissions or create a new one."
            break
        }
        else 
        {
            $DestinationStorageAccountContainer = $DestinationStorageAccountContainers | Out-GridView -Title "Please Select the storage account container." -PassThru
        }
        
    }

    return $DestinationStorageAccountContainer,$DestinationStorageAccount
}
Export-ModuleMember -Function Invoke-StorageAccountSelectionCreation

Function Invoke-VirtualNetworkSelectionCreation
{
    [CmdletBinding()]
    Param ()

    $ErrorActionPreference = 'Stop'
    # VM Network Configuration
    # Virtual Network and Subnet Selection
    $VirtualNetworks = @()
    $VirtualNetworks += 'New'
    $VirtualNetworks += (Get-AzureRmVirtualNetwork).Name

    $VirtualNetworkNameCheckRegEx = '^[a-zA-Z0-9](?:[a-zA-Z0-9_-]*[a-zA-Z0-9])?$'

    $VirtualNetworkName = $VirtualNetworks | Out-GridView -Title "Please Select an existing or new Virtual Network for the VM." -PassThru

    if ($VirtualNetworkName -eq 'New')
    {
        
        $AllVirtualNetworks = Get-AzureRmVirtualNetwork
        $VirtualNetworkResourceGroup = Invoke-ResourceGroupSelectionCreation -ResourceGroupMessage "Please Select an Existing or New Resource Group for the Virtual Network"

        # Create Resource Group
        $ResourceNameAvailabilityCheck = $false
        $ResourceNameValidation = $false
                    
        do 
        {
            $VirtualNetworkName = Read-Host "Please Enter a name for the Virtual Network"
                
            if (($VirtualNetworkName -match $VirtualNetworkNameCheckRegEx) -and ($VirtualNetworkName.Length -ge 2) -and ($VirtualNetworkName.Length -le 64))
            {
                $ResourceNameValidation = $true
                $ResourceNameAvailabilityCheck = Get-AzureRmVirtualNetwork | Where-Object {$_.Name -eq $VirtualNetworkName} -ErrorAction SilentlyContinue
            }

            if ($VirtualNetworkName -notmatch $VirtualNetworkNameCheckRegEx)
            {
                Write-Warning -Message 'Virtual Network Names only allow alphanumeric characters, underscores, hyphens and must start or end with alphanumeric characters.'
            }

            if (($VirtualNetworkName.Length -lt 2) -or ($VirtualNetworkName.Length -gt 64))
            {
                Write-Warning -Message 'Virtual Network Names may only be between 2 and 64 characters'
            }
                
            if ($ResourceNameAvailabilityCheck)
            {
                Write-Warning -Message "Virtual Network $VirtualNetworkName Already Exists"
                Write-Warning -Message "Please Choose Another Name"
                $ResourceNameAvailabilityCheck = Get-AzureRmVirtualNetwork | Where-Object {$_.Name -eq $VirtualNetworkName} -ErrorAction SilentlyContinue
            }

            else
            {
                $ResourceNameAvailability = $true
            }

        } 
        until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

        # Virtual Network Address Check & Create
        $VirtualNetworkAddressPrefixRegEx = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$'

        $AddressSpaceValidation = $false
        $VirtualNetworkAddressPrefixRegExCheck = $false

        do 
        {
            $VirtualNetworkAddressPrefix = Read-Host 'Please enter a Virtual Network Address Prefix. Example: 10.0.0.0/16'
            
            if ($AllVirtualNetworks.AddressSpace.AddressPrefixes -contains $VirtualNetworkAddressPrefix)
            {
                Write-Warning -Message "The Virtual Network Address Prefix you provided is already in use. Please select another one."
            }
               
            if ($VirtualNetworkAddressPrefix -notmatch $VirtualNetworkAddressPrefixRegEx)
            {
                Write-Warning -Message 'The Address Prefix entered is not in CIDR Format. Example: 10.0.0.0/16'
            }

            else
            {
                $AddressSpaceValidation = $true
                $VirtualNetworkAddressPrefixRegExCheck = $true
            }

        }
        until (($AddressSpaceValidation -eq $true) -and ($VirtualNetworkAddressPrefixRegExCheck -eq $true))

        #Subnet                  
        $ResourceNameAvailabilityCheck = $false
        $ResourceNameValidation = $false
                    
        do 
        {
            $SubnetName = Read-Host "Please enter a name for the new Subnet"

                
            if (($SubnetName -match $VirtualNetworkNameCheckRegEx) -and ($SubnetName.Length -ge 1) -and ($SubnetName.Length -le 80))
            {
                $ResourceNameAvailabilityCheck = $true
                $ResourceNameValidation = $true
            }

            if ($SubnetName -notmatch $VirtualNetworkNameCheckRegEx)
            {
                Write-Warning -Message 'Subnet Names only allow alphanumeric characters, underscores, hyphens and must start or end with alphanumeric characters.'
            }

            if (($SubnetName.Length -lt 1) -or ($SubnetName.Length -gt 80))
            {
                Write-Warning -Message 'Virtual Network Names may only be between 1 and 80 characters'
            }

        } 
        until (($ResourceNameAvailabilityCheck -eq $true) -and ($ResourceNameValidation -eq $true))

        $SubnetAddressPrefixRegEx = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$'

        $AddressSpaceValidation = $false
        $SubnetAddressPrefixRegExCheck = $false

        do 
        {
            $SubnetAddressPrefix = Read-Host 'Please enter a Subnet Address Prefix. Example: 10.1.0.0/24'
               
            if ($SubnetAddressPrefix -notmatch $SubnetAddressPrefixRegEx)
            {
                Write-Warning -Message 'The Address Prefix entered is not in CIDR Format. Example: 10.1.0.0/24'
            }

            else
            {
                $AddressSpaceValidation = $true
                $SubnetAddressPrefixRegExCheck = $true
            }
        }
        until (($AddressSpaceValidation -eq $true) -and ($SubnetAddressPrefixRegExCheck -eq $true))

        $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix
        $VirtualNetwork = New-AzureRmVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $VirtualNetworkResourceGroup.ResourceGroupName -Location $Location -AddressPrefix $VirtualNetworkAddressPrefix -Subnet $SubnetConfig -Verbose
        $VirtualNetworkSubnet = $VirtualNetwork.Subnets | Where-Object {$_.Name -eq $SubnetName}

    }
    else 
    {
        $VirtualNetwork = Get-AzureRmVirtualNetwork | Where-Object {$_.Name -eq $VirtualNetworkName}

        $VirtualNetworkSubnets = @()
        $VirtualNetworkSubnets += New-Object PSObject -Property ([ordered]@{Name='New';AddressPrefix=''})
        foreach ($Subnet in $VirtualNetwork.Subnets)
        {
            $VirtualNetworkSubnets += New-Object PSObject -Property ([ordered]@{Name=$($Subnet.Name);AddressPrefix=$($Subnet.AddressPrefix)})
        }

        $VirtualNetworkSubnet = $VirtualNetworkSubnets | Out-GridView -Title "Please Select an existing or new Virtual Network Subnet for the VM." -PassThru

        if ($VirtualNetworkSubnet.Name -eq 'New')
        {
            #Subnet                  
            $ResourceNameAvailabilityCheck = $false
            $ResourceNameValidation = $false
                    
            do 
            {
                $SubnetName = Read-Host "Please enter a name for the new Subnet"

                if (($SubnetName -match $VirtualNetworkNameCheckRegEx) -and ($SubnetName.Length -ge 1) -and ($SubnetName.Length -le 80))
                {
                    $ResourceNameAvailabilityCheck = $true
                    $ResourceNameValidation = $true
                }

                if ($SubnetName -notmatch $VirtualNetworkNameCheckRegEx)
                {
                    Write-Warning -Message 'Subnet Names only allow alphanumeric characters, underscores, hyphens and must start or end with alphanumeric characters.'
                }

                if (($SubnetName.Length -lt 1) -or ($SubnetName.Length -gt 80))
                {
                    Write-Warning -Message 'Virtual Network Names may only be between 1 and 80 characters'
                }
            } 
            until (($ResourceNameAvailabilityCheck -eq $true) -and ($ResourceNameValidation -eq $true))

            $SubnetAddressPrefixRegEx = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$'

            $AddressSpaceValidation = $false
            $SubnetAddressPrefixRegExCheck = $false

            do 
            {
                $SubnetAddressPrefix = Read-Host 'Please enter a Subnet Address Prefix. Example: 10.1.0.0/24'
               
                if ($SubnetAddressPrefix -notmatch $SubnetAddressPrefixRegEx)
                {
                    Write-Warning -Message 'The Address Prefix entered is not in CIDR Format. Example: 10.1.0.0/24'
                }

                else
                {
                    $AddressSpaceValidation = $true
                    $SubnetAddressPrefixRegExCheck = $true
                }
            }
            until (($AddressSpaceValidation -eq $true) -and ($SubnetAddressPrefixRegExCheck -eq $true))

            Add-AzureRMVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VirtualNetwork -AddressPrefix $SubnetAddressPrefix -Verbose
            $VirtualNetwork | Set-AzureRmVirtualNetwork -Verbose
            $VirtualNetwork = Get-AzureRmVirtualNetwork | Where-Object {$_.Name -eq $VirtualNetworkName}
            $VirtualNetworkSubnet = $VirtualNetwork.Subnets | Where-Object {$_.Name -eq $SubnetName}
            $VirtualNetworkResourceGroup = Get-AzureRMResourceGroup -Name $VirtualNetwork.ResourceGroupName

        }
        else
        {
            $VirtualNetworkSubnet = $VirtualNetwork.Subnets | Where-Object {$_.Name -eq $VirtualNetworkSubnet.Name}
            $VirtualNetworkResourceGroup = Get-AzureRMResourceGroup -Name $VirtualNetwork.ResourceGroupName
        }
    }
    return $VirtualNetworkResourceGroup.ResourceGroupName,$VirtualNetwork.Id,$VirtualNetworkSubnet.Id
}
Export-ModuleMember -Function Invoke-VirtualNetworkSelectionCreation

Function Get-VMWareAzureVirtualMachineSizeFromOVF
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the output location for the CSV File
        [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
        [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    $Location = (Get-AzureRMLocation).Location

    Write-Host "Getting VM Information from OVF file." -ForegroundColor Green
    $VirtualMachineFiles = Import-Csv ($FileSaveLocation + '\' + $VirtualMachineName + '-ExportData' + '.csv')

    # load it into an XML object
    $OVFPath = ($VirtualMachineFiles | Where-Object {$_.Extension -eq '.ovf'}).FullName
    $XML = New-Object -TypeName XML
    $XML.Load($OVFPath)

    [Int]$MemoryAssigned = (($XML.Envelope.VirtualSystem.VirtualHardwareSection.Item | Where-Object {$_.Description -eq 'Memory Size'}).VirtualQuantity)
    [Int]$HardDrivesCount = (($XML.Envelope.DiskSection.disk).Count)
    [Int]$ProcessorCount = (($XML.Envelope.VirtualSystem.VirtualHardwareSection.Item | Where-Object {$_.Description -eq 'Number of Virtual CPUs'}).VirtualQuantity)

    Write-Host "Getting list of VM Sizes from Azure. Please wait..." -ForegroundColor Green
    $AzureStackVMSizeList = Get-AzureRMVmSize -Location $Location

    $AzureStackVMSizeList | Where-Object {($_.NumberOfCores -ge $ProcessorCount) -and ($_.MemoryInMB -ge $MemoryAssigned) -and ($_.MaxDataDiskCount -ge $HardDrivesCount)} | Sort-Object Name,NumberofCores,MemoryInMB

    return $AzureStackVMSizeList
}
Export-ModuleMember -Function Get-HyperVAzureVirtualMachineSizeFromHost

function Invoke-VHDUploadToStorageAccount
{
    [CmdletBinding()]
    param 
    (
        [String]$StorageAccountDestinationURL,
        [String]$VHDFilePath
    )

    $env:AZCOPY_DEFAULT_SERVICE_API_VERSION="2017-11-09"
    azcopy copy $VHDFilePath $StorageAccountDestinationURL --blob-type=PageBlob
}
Export-ModuleMember -Function Invoke-VHDUploadToStorageAccount

Function Invoke-VMWareVMImageCopyHyperVToAzureStackHub
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the output location for the CSV File
	    [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	    [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    Install-AzCopy

    $AzureContextDetails = Get-AzureRmContext -ErrorAction SilentlyContinue
    if ($AzureContextDetails)
    {
        Write-Host "You are currently connected to Azure as $($AzureContextDetails.Account)" -ForegroundColor Green 
        Write-Host "Your current working Subsciption is $($AzureContextDetails.Subscription.Name) - $($AzureContextDetails.Subscription.Id)" -ForegroundColor Green 
        Write-Host "You are currently connected to Tenant ID is $($AzureContextDetails.Subscription.TenantId)" -ForegroundColor Green 

        # Azure connection choice
        $Continue = New-Object System.Management.Automation.Host.ChoiceDescription '&Continue'
        $Login = New-Object System.Management.Automation.Host.ChoiceDescription '&Login'
        $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Continue, $Login)
        $Title = 'Continue or Login?'
        $Message = 'Do you want to continue or login again and select a new environment?'
        $AzureConnectionChoice = $host.ui.PromptForChoice($title, $message, $options, 0)
    }
    if (($AzureConnectionChoice -eq 1) -or (!($AzureContextDetails)))
    {
        # Enviornment Selection
        $Environments = Get-AzureRMEnvironment
        $Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

        # Connect to Azure
        try
        {
            Connect-AzureRMAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
        }
        catch
        {
            Write-Error -Message $_.Exception
            break
        }

        try 
        {
            $Subscriptions = Get-AzureRMSubscription
            if ($Subscriptions.Count -gt '1')
            {
                $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
                Select-AzureRmSubscription $Subscription
                $SubscriptionID = $Subscription.SubscriptionID
            }
            else
            {
                $SubscriptionID = $Subscriptions.SubscriptionID
            }
        }
        catch
        {
            Write-Error -Message $_.Exception
            break
        }
    }

    $DestinationStorageAccount = Invoke-StorageAccountSelectionCreation
    [String]$DestinationStorageAccountContainerName = $($DestinationStorageAccount.name)
    $DestinationStorageAccount = Get-AzureRmStorageAccount -Name $($DestinationStorageAccount.context.StorageAccountName)[0] -ResourceGroupName $($DestinationStorageAccount.ResourceGroupName)

    Write-Host "Getting VM Disk Information" -ForegroundColor Green
    $VirtualMachineFiles = Import-Csv ($FileSaveLocation + '\' + $VirtualMachineName + '-ExportData' + '.csv')
    $VMDiskFiles = Get-ChildItem $VirtualMachineFiles[0].DirectoryName -Recurse -Include *.vhd

    # Create SAS Token
    $StartTime = Get-Date
    $EndTime = $startTime.AddHours(8.0)
    $SASToken = New-AzureStorageContainerSASToken -Context $DestinationStorageAccount.Context -Container $DestinationStorageAccountContainerName.Trim() -Permission rwdl -StartTime $StartTime -ExpiryTime $EndTime -ErrorAction Stop

    $DiskData = @()

    # Gather HardDrive Data and Upload VHDs to Azure Storage
    foreach ($VMDisk in $VMDiskFiles)
    {
        $DiskName = $($VMDisk.FullName.Split('\') | Select-Object -Last 1).ToString().ToLower()
        $DiskPath = $VMDisk.FullName.ToString().ToLower()

        $StorageAccountDestinationURL = $DestinationStorageAccount.Context.BlobEndPoint + $DestinationStorageAccountContainerName.Trim() + '/' + $VirtualMachineName + '/'+ $DiskName + $SASToken

        Write-Host "Copying $DiskName to Azure Storage Account. This may take some time..."
        Invoke-VHDUploadToStorageAccount -StorageAccountDestinationURL $StorageAccountDestinationURL -VHDFilePath $DiskPath

        $DiskNumber = ($XML.Envelope.References.File | Where-Object {$_.href -eq "$($($DiskName).Replace('vhd','vmdk'))"}).Id
        $DiskURL = $DestinationStorageAccount.Context.BlobEndPoint + $DestinationStorageAccountContainerName.Trim() + '/' + $VirtualMachineName + '/'+ $DiskName

        $DiskData += New-Object PSObject -Property ([ordered]@{VMName=$($VirtualMachineName);DiskName=$DiskName;DiskURL=$DiskURL;DiskNumber=$DiskNumber})
    }

    $DiskData | Sort-Object -Property DiskNumber | Export-Csv $FileSaveLocation\$($VirtualMachineName + '-DiskData' + '.csv') -NoTypeInformation
}
Export-ModuleMember -Function Invoke-VMWareVMImageCopyHyperVToAzureStackHub

Function New-AzureStackVirtualMachineFromHyperVAndDataFile
{
    [CmdletBinding()]
    Param 
    (
        # Specify the Name of the Target Virtual Machine
        [Parameter(Mandatory=$true,HelpMessage="Specify the Name of the Target Virtual Machine. Example VM-001")]
        $VirtualMachineName,

        # Specify the output location for the CSV File
	    [Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
	    [String]$FileSaveLocation = "$env:USERPROFILE\Documents\"
    )

    $ErrorActionPreference = 'Stop'

    $ImageData = Import-Csv (Get-ChildItem -Path $FileSaveLocation\$($VirtualMachineName + '-DiskData' + '.csv')).FullName
    
    $AzureContextDetails = Get-AzureRmContext -ErrorAction SilentlyContinue
    if ($AzureContextDetails)
    {
        Write-Host "You are currently connected to Azure as $($AzureContextDetails.Account)" -ForegroundColor Green 
        Write-Host "Your current working Subsciption is $($AzureContextDetails.Subscription.Name) - $($AzureContextDetails.Subscription.Id)" -ForegroundColor Green 
        Write-Host "You are currently connected to Tenant ID is $($AzureContextDetails.Subscription.TenantId)" -ForegroundColor Green 

        # Azure connection choice
        $Continue = New-Object System.Management.Automation.Host.ChoiceDescription '&Continue'
        $Login = New-Object System.Management.Automation.Host.ChoiceDescription '&Login'
        $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Continue, $Login)
        $Title = 'Continue or Login?'
        $Message = 'Do you want to continue or login again and select a new environment?'
        $AzureConnectionChoice = $host.ui.PromptForChoice($title, $message, $options, 0)
    }
    if (($AzureConnectionChoice -eq 1) -or (!($AzureContextDetails)))
    {
        # Enviornment Selection
        $Environments = Get-AzureRMEnvironment
        $Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

        # Connect to Azure
        try
        {
            Connect-AzureRMAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
        }
        catch
        {
            Write-Error -Message $_.Exception
            break
        }

        try 
        {
            $Subscriptions = Get-AzureRMSubscription
            if ($Subscriptions.Count -gt '1')
            {
                $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
                Select-AzureRmSubscription $Subscription
                $SubscriptionID = $Subscription.SubscriptionID
            }
            else
            {
                $SubscriptionID = $Subscriptions.SubscriptionID
            }
        }
        catch
        {
            Write-Error -Message $_.Exception
            break
        }
    }
    elseif (($AzureConnectionChoice -eq 0) -and ($AzureContextDetails)) 
    {
        $SubscriptionID = $($AzureContextDetails.Subscription.Id)
    }

    $Location = (Get-AzureRMLocation).Location

    # load it into an XML object
    $OVFPath = ($VirtualMachineFiles | Where-Object {$_.Extension -eq '.ovf'}).FullName
    $XML = New-Object -TypeName XML
    $XML.Load($OVFPath)
    if ($XML.Envelope.VirtualSystem.OperatingSystemSection.osType -like "windows*")
    {
        $VirtualMachineOperatingSystem = 'Windows'
    }
    else 
    {
        $VirtualMachineOperatingSystem = 'Linux'
    }

    $ResourceGroup = Invoke-ResourceGroupSelectionCreation -ResourceGroupMessage "Please Select an Existing or New Resource Group for the Virtual Machine $VirtualMachineName"

    $VMManagedDisks = @()

    foreach ($Disk in $ImageData)
    {
        Write-Host "Creating Managed Disk $($Disk.DiskName) in Resource Group $($ResourceGroup.ResourceGroupName)"
        $DiskConfig = New-AzureRmDiskConfig -Location $Location -AccountType StandardLRS -CreateOption Import -SourceUri $Disk.DiskURL
        $VMManagedDisk = New-AzureRmDisk -ResourceGroupName $ResourceGroup.ResourceGroupName -DiskName $Disk.DiskName -Disk $diskconfig
        $VMManagedDisks += $VMManagedDisk
    }

    $AzureStackVMSizeList = Get-VMWareAzureVirtualMachineSizeFromOVF -VirtualMachineName $VirtualMachineName
    $SelectedSize = $AzureStackVMSizeList | Out-GridView -Title "Please Select size for the new Virtual Machine." -PassThru

    # VM Configuration
    $VMConfig = New-AzureRmVMConfig -VMName $ImageData[0].VMName -VMSize $SelectedSize.Name

    # VM Disk Configuration
    $IsFirst = $True
    [Int]$LunNumber = 1

    foreach ($Disk in $ImageData)
    {
        $ManagedDisk = $VMManagedDisks | Where-Object {$_.Name -eq $Disk.DiskName}
        If ($IsFirst -eq $true)
        {
            if ($VirtualMachineOperatingSystem -eq 'Windows')
            {
                $VMConfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id -Windows
            }
            if ($VirtualMachineOperatingSystem -eq 'Linux')
            {
                $VMConfig = Set-AzureRmVMOSDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id -Linux
            }
            $IsFirst = $false
        }
        else
        {
            Add-AzureRmVMDataDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id -Lun $LunNumber
            $LunNumber++
        }   
    }

    # VM Network Configuration
    Write-Host "Gathering Network Information"
    $NetworkInfo = Invoke-VirtualNetworkSelectionCreation -Verbose

    # Private IP Assignment Type Choice
    $Dynamic = New-Object System.Management.Automation.Host.ChoiceDescription '&Dynamic'
    $Static = New-Object System.Management.Automation.Host.ChoiceDescription '&Static'
    $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Dynamic, $Static)
    $Title = 'Dynamic or Static?'
    $Message = 'Do you want the Private IP Address to be Dynamic or Static?'
    $PrivateIPAssignmentTypeResult = $host.ui.PromptForChoice($title, $message, $options, 0)

    if ($PrivateIPAssignmentTypeResult -eq 1)
    {
        $AvailableIPAddresses = @()
        Write-Host "Running IP Configuration Query"
        $Results = Invoke-ipConfigurationsQuery -SubscriptionID $SubscriptionID -ResourceGroupName ($NetworkInfo[2].Split('/')[4]) -VirtualNetworkName ($NetworkInfo[1].Split('/') | Select-Object -Last 1)
        $AllocatedIPs = ($Results.properties.subnets | Where-Object {$_.Name -eq ($NetworkInfo[2].Split('/') | Select-Object -Last 1)}).properties.ipConfigurations.properties.privateIPAddress
        $IPAddressesInSubnet = (Get-IPAddressesInSubnet -NetworkAddress (($Results.properties.subnets | Where-Object {$_.Name -eq ($NetworkInfo[2].Split('/') | Select-Object -Last 1)}).properties.addressPrefix))
        foreach ($IPAddresseInSubnet in $IPAddressesInSubnet | Where-Object {$_ -notin $AllocatedIPs})
        {
            $AvailableIPAddresses += $IPAddresseInSubnet
        }

        $PrivateIP = $AvailableIPAddresses | Out-GridView -Title "Please Select the Private IP to assign." -PassThru
    }

    # Public IP Choice
    $Yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes'
    $No = New-Object System.Management.Automation.Host.ChoiceDescription '&No'
    $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)
    $title = 'Public IP Address?'
    $message = 'Do you want to create a Public IP Address?'
    $PublicIPResult = $host.ui.PromptForChoice($title, $message, $options, 0)

    if ($PublicIPResult -eq 0)
    {
        # Public IP Assignment Type Choice
        $Dynamic = New-Object System.Management.Automation.Host.ChoiceDescription '&Dynamic'
        $Static = New-Object System.Management.Automation.Host.ChoiceDescription '&Static'
        $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Dynamic, $Static)
        $Title = 'Dynamic or Static?'
        $Message = 'Do you want the Public IP Address to be Dynamic or Static?'
        $PublicIPAssignmentTypeResult = $host.ui.PromptForChoice($title, $message, $options, 0)
    }

    # Dynamic Public IP and Dynamic Private IP
    if (($PublicIPResult -eq 0) -and ($PublicIPAssignmentTypeResult -eq 0) -and ($PrivateIPAssignmentTypeResult -eq 0))
    {
        $PublicIP = Invoke-PublicIPCreation -IPAddressType 'Dynamic' -Verbose
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -SubnetId $NetworkInfo[2] -PublicIpAddressId $PublicIP.Id -Verbose
    }
    # Dynamic Public IP and Static Private IP
    if (($PublicIPResult -eq 0) -and ($PublicIPAssignmentTypeResult -eq 0) -and ($PrivateIPAssignmentTypeResult -eq 1))
    {
        $PublicIP = Invoke-PublicIPCreation -IPAddressType 'Dynamic' -Verbose
        $IPconfig = New-AzureRmNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $PrivateIP -SubnetId $NetworkInfo[2] -PublicIpAddressId $PublicIP.Id -Verbose
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -IpConfiguration $IPconfig  -Verbose
    }
    # Static Public IP and Dynamic Private IP
    if (($PublicIPResult -eq 0) -and ($PublicIPAssignmentTypeResult -eq 1) -and ($PrivateIPAssignmentTypeResult -eq 0))
    {
        $PublicIP = Invoke-PublicIPCreation -IPAddressType 'Static'
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -SubnetId $NetworkInfo[2] -PublicIpAddressId $PublicIP.Id -Verbose
    }
    # Static Public IP and Static Private IP
    if (($PublicIPResult -eq 0) -and ($PublicIPAssignmentTypeResult -eq 1) -and ($PrivateIPAssignmentTypeResult -eq 1))
    {
        $PublicIP = Invoke-PublicIPCreation -IPAddressType 'Static'
        $IPconfig = New-AzureRmNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $PrivateIP -SubnetId $NetworkInfo[2] -PublicIpAddressId $PublicIP.Id -Verbose
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -IpConfiguration $IPconfig  -Verbose
    }
    # No Public IP and Dynamic Private IP
    if (($PublicIPResult -eq 1) -and ($PrivateIPAssignmentTypeResult -eq 0))
    {
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -SubnetId $NetworkInfo[2] -Verbose
    }
    # No Public IP and Static Private IP
    if (($PublicIPResult -eq 1) -and ($PrivateIPAssignmentTypeResult -eq 1))
    {
        $IPconfig = New-AzureRmNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $PrivateIP -SubnetId $NetworkInfo[2] -PublicIpAddressId $PublicIP.Id -Verbose
        $NetworkInterface = New-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup.ResourceGroupName -Name ($VirtualMachineName + '-NIC') -Location $Location -IpConfiguration $IPconfig  -Verbose
    }
    
    $VMConfig = Add-AzureRmVMNetworkInterface -VM $VMConfig -Id $NetworkInterface.Id -Verbose

    Write-Host "Creating New Virtual Machine $VirtualMachineName in Resource Group $($ResourceGroup.ResourceGroupName)."
    Write-Host "This may take a few minutes. Please wait..."
    New-AzureRmVM -VM $VMConfig -Location $Location -ResourceGroupName $ResourceGroup.ResourceGroupName -Verbose
}
Export-ModuleMember -Function New-AzureStackVirtualMachineFromHyperVAndDataFile