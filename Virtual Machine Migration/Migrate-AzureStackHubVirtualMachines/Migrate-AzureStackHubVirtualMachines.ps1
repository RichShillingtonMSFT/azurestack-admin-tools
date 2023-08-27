# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select Source Virtual Machine Azure Stack Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

try 
{
    $Subscriptions = Get-AzSubscription
    if ($Subscriptions.Count -gt '1')
    {
        $Subscription = $Subscriptions | Out-GridView -Title "Please select the Subscription where the source Virtual Machine is located." -PassThru
        Set-AzContext $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}

$Location = Get-AzLocation
#endregion

$SourceVirtualMachines = Get-AzVM -Status | Select-Object -Property * | Sort-Object -Property Name

$SelectedVirtualMachines = $SourceVirtualMachines | Select-Object -Property Name,ResourceGroupName | Out-GridView -Title "Please select the Virtual Machine(s) to move." -PassThru

$VirtualMachinesToMove = $SourceVirtualMachines | Where-Object {$_.Name -in $SelectedVirtualMachines.Name}

Write-host "Would you like to change the destination Resource Group? (Default is No)" -ForegroundColor Yellow 
$ResourceGroupNameChange = Read-Host " ( Yes / No ) "

if ($ResourceGroupNameChange -eq 'Yes')
{
    $ResourceGroupNewName = Read-Host " Please provide a new Resource Group Name for your Virtual Machines "
}

foreach ($VirtualMachineToMove in $VirtualMachinesToMove)
{
    if ($ResourceGroupNewName)
    {
        $ResourceGroupOldName = $VirtualMachineToMove.ResourceGroupName
        $VirtualMachineToMove.ResourceGroupName = $ResourceGroupNewName
    }

    if ($VirtualMachineToMove.OSProfile.WindowsConfiguration)
    {
        $VirtualMachineOperatingSystem =  'Windows'
    }
    else
    {
        $VirtualMachineOperatingSystem =  'Linux'
    }

    $VirtualMachineNetworkInformation = @()
    $VirtualMachineVirtualNetworkInformation = @()
    $VirtualMachineVirtualNetworkSubnetInformation = @()
    $NetworkSecurityGroups = @()
    $RouteTables = @()
    $InterfaceNetworkSecurityGroupDetails = @()
    $InterfacePublicIPDetails = @()

    Write-Host "Gathering Network & Diagnostics settings information for $($VirtualMachineToMove.Name). Please wait..." -ForegroundColor Green
    foreach ($NetworkInterface in $VirtualMachineToMove.NetworkProfile.NetworkInterfaces.Id)
    {
        $InterfaceDetails = Get-AzNetworkInterface -Name $($($NetworkInterface.Split('/')[8])) -ResourceGroupName $($($NetworkInterface.Split('/')[4])) | Select-Object -Property *

        if ($ResourceGroupNewName)
        {
            if ($InterfaceDetails.ResourceGroupName -eq $ResourceGroupOldName)
            {
                $InterfaceDetails.ResourceGroupName = $ResourceGroupNewName
            }
        }

        $IfConfig = $InterfaceDetails.IpConfigurations

        $VirtualNetworkDetails = Get-AzVirtualNetwork -Name $($IfConfig.Subnet.Id.Split('/')[8]) -ResourceGroupName $($IfConfig.Subnet.Id.Split('/')[4]) | Select-Object -Property *

        if ($ResourceGroupNewName)
        {
            if ($VirtualNetworkDetails.ResourceGroupName -eq $ResourceGroupOldName)
            {
                $VirtualNetworkDetails.ResourceGroupName = $ResourceGroupNewName
            }
        }
        
        $VirtualMachineVirtualNetworkInformation += $VirtualNetworkDetails

        $VirtualNetworkSubnetDetails = Get-AzVirtualNetwork -Name $($IfConfig.Subnet.Id.Split('/')[8]) -ResourceGroupName $($IfConfig.Subnet.Id.Split('/')[4]) | Get-AzVirtualNetworkSubnetConfig -Name $($InterfaceDetails.IpConfigurations.Subnet.Id.Split('/')[10])

        $VirtualMachineVirtualNetworkSubnetInformation += $VirtualNetworkSubnetDetails

        $IPDetails = @()
        
        $IPDetails += New-Object PSObject -Property ([ordered]@{
        InterfaceName=$($InterfaceDetails.Name);
        Primary=$($InterfaceDetails.Primary)
        InterfaceNameResourceGroupName=$($InterfaceDetails.ResourceGroupName);
        InterfaceVirtualNetworkName=$($IfConfig.Subnet.Id.Split('/')[8]);
        InterfaceVirtualNetworkSubnetName=$($InterfaceDetails.IpConfigurations.Subnet.Id.Split('/')[10]);
        InterfacePrivateIPAddress=$($InterfaceDetails.IpConfigurations.PrivateIpAddress);
        InterfacePrivateIPAddressAllocationMethod=$($InterfaceDetails.IpConfigurations.PrivateIpAllocationMethod)})
        
        if ($InterfaceDetails.NetworkSecurityGroup.Id)
        {
            $NetworkSecurityGroupDetails = Get-AzNetworkSecurityGroup -Name $($($InterfaceDetails.NetworkSecurityGroup.Id.Split('/')[8])) -ResourceGroupName $($($InterfaceDetails.NetworkSecurityGroup.Id.Split('/')[4])) | Select-Object -Property *

            if ($ResourceGroupNewName)
            {
                if ($NetworkSecurityGroupDetails.ResourceGroupName -eq $ResourceGroupOldName)
                {
                    $NetworkSecurityGroupDetails.ResourceGroupName = $ResourceGroupNewName
                }
            }

            $InterfaceNetworkSecurityGroupDetails += $NetworkSecurityGroupDetails

            $IPDetails | Add-Member -MemberType NoteProperty -Name 'InterfaceNetworkSecurityGroupName' -Value $($($InterfaceDetails.NetworkSecurityGroup.Id.Split('/')[8]))
        }

        if ($InterfaceDetails.IpConfigurations.PublicIpAddress.Id)
        {
            $PublicIPDetails = Get-AzPublicIpAddress -Name $($InterfaceDetails.IpConfigurations.PublicIpAddress.Id.Split('/')[8]) -ResourceGroupName $($InterfaceDetails.IpConfigurations.PublicIpAddress.Id.Split('/')[4]) | Select-Object -Property *
            if ($ResourceGroupNewName)
            {
                if ($PublicIPDetails.ResourceGroupName -eq $ResourceGroupOldName)
                {
                    $PublicIPDetails.ResourceGroupName = $ResourceGroupNewName
                }
            }

            $InterfacePublicIPDetails += $PublicIPDetails

            $IPDetails | Add-Member -MemberType NoteProperty -Name 'InterfacePublicIPAddressName' -Value $($InterfacePublicIPDetails.Name)
            $IPDetails | Add-Member -MemberType NoteProperty -Name 'InterfacePublicIPAddress' -Value $($InterfacePublicIPDetails.IpAddress)
            $IPDetails | Add-Member -MemberType NoteProperty -Name 'InterfacePublicIPAddressAllocationMethod' -Value $($InterfacePublicIPDetails.PublicIpAllocationMethod)
            $IPDetails | Add-Member -MemberType NoteProperty -Name 'InterfacePublicIPAddressResourceGroupName' -Value $($InterfacePublicIPDetails.ResourceGroupName)
        }

        if ($VirtualNetworkSubnetDetails.RouteTable)
        {
            $VirtualNetworkSubnetNetworkRouteTableDetails = Get-AzRouteTable -ResourceGroupName $($VirtualNetworkSubnetDetails.RouteTable.Id.Split('/')[4]) -Name $($VirtualNetworkSubnetDetails.RouteTable.Id.Split('/')[8]) | Select-Object -Property *
            if ($ResourceGroupNewName)
            {            
                if ($VirtualNetworkSubnetNetworkRouteTableDetails.ResourceGroupName -eq $ResourceGroupOldName)
                {
                    $VirtualNetworkSubnetNetworkRouteTableDetails.ResourceGroupName = $ResourceGroupNewName
                }
            }

            $RouteTables += $VirtualNetworkSubnetNetworkRouteTableDetails
        }

        if ($VirtualNetworkSubnetDetails.NetworkSecurityGroup)
        {
            $VirtualNetworkSubnetNetworkSecurityGroupDetails =  Get-AzNetworkSecurityGroup -Name $($($VirtualNetworkSubnetDetails.NetworkSecurityGroup.Id.Split('/')[8])) -ResourceGroupName $($($VirtualNetworkSubnetDetails.NetworkSecurityGroup.Id.Split('/')[4])) | Select-Object -Property *
            if ($ResourceGroupNewName)
            {          
                if ($VirtualNetworkSubnetNetworkSecurityGroupDetails.ResourceGroupName -eq $ResourceGroupOldName)
                {
                    $VirtualNetworkSubnetNetworkSecurityGroupDetails.ResourceGroupName = $ResourceGroupNewName
                }
            }

            $NetworkSecurityGroups += $VirtualNetworkSubnetNetworkSecurityGroupDetails
        }

        $VirtualMachineNetworkInformation += $IPDetails
    }

    if ($VirtualMachineToMove.DiagnosticsProfile.BootDiagnostics)
    {
        $BootDiagnostictsSourceStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $(($VirtualMachineToMove.DiagnosticsProfile.BootDiagnostics).StorageUri.Replace('https://','').Split('.')[0])}
        if ($ResourceGroupNewName)
        {        
            if ($BootDiagnostictsSourceStorageAccount.ResourceGroupName -eq $ResourceGroupOldName)
            {
                $BootDiagnostictsSourceStorageAccount.ResourceGroupName = $ResourceGroupNewName
            }
        }
    }

    if ($VirtualMachinesToMove.AvailabilitySetReference.Id)
    {
        $VirtualMachineAvailabilitySet = Get-AzAvailabilitySet -ResourceGroupName $($VirtualMachinesToMove.AvailabilitySetReference.Id.Split('/')[4]) -Name $($VirtualMachinesToMove.AvailabilitySetReference.Id.Split('/')[8]) | Select-Object -Property *
        if ($ResourceGroupNewName)
        {        
            if ($VirtualMachineAvailabilitySet.ResourceGroupName -eq $ResourceGroupOldName)
            {
                $VirtualMachineAvailabilitySet.ResourceGroupName = $ResourceGroupNewName
            }
        }
    }

    if ($ResourceGroupNewName)
    {
        $VirtualMachineDiagnosticsExtension = Get-AzVMDiagnosticsExtension -ResourceGroupName $ResourceGroupOldName -VMName $($VirtualMachineToMove.Name) -ErrorAction SilentlyContinue
        $VirtualMachineDiagnosticsExtension.ResourceGroupName = $ResourceGroupNewName
    }
    else
    {
        $VirtualMachineDiagnosticsExtension = Get-AzVMDiagnosticsExtension -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -VMName $($VirtualMachineToMove.Name) -ErrorAction SilentlyContinue
    }
    
    if ($VirtualMachineDiagnosticsExtension)
    {
        $VirtualMachineDiagnosticsExtensionPublicSettings = $VirtualMachineDiagnosticsExtension.PublicSettings | ConvertFrom-Json
        $VirtualMachineDiagnosticsExtensionStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $($VirtualMachineDiagnosticsExtensionPublicSettings.StorageAccount)}
        $VirtualMachineDiagnosticsExtensionPublicSettingsXML = (ConvertFrom-Json -InputObject $VirtualMachineDiagnosticsExtension.PublicSettings).WadCfg
        if ($ResourceGroupNewName)
        {        
            if ($VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName -eq $ResourceGroupOldName)
            {
                $VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName = $ResourceGroupNewName
            }
        }
    }

    if ($VirtualMachineToMove.PowerState -eq 'VM running')
    {
        Write-Warning "The Virtual Machine selected is currently running!"
        Write-host "The Virtual Machine must be SHUTDOWN to proceed! Do you want to continue? (Default is No)" -ForegroundColor Yellow 
        $ShutdownAnswer = Read-Host " ( Yes / No ) "

        if (($ShutdownAnswer -eq 'No') -or (!($ShutdownAnswer)))
        {
            Break
        }
        else
        {
            Write-Host "Shutting down Virtual Machine $VirtualMachineName. Please wait..." -ForegroundColor Yellow
            if ($ResourceGroupNewName)
            {
                Stop-AzVM -Name $VirtualMachineToMove.Name -ResourceGroupName $ResourceGroupOldName -Force
            }
            else
            {
                Stop-AzVM -Name $VirtualMachineToMove.Name -ResourceGroupName $VirtualMachineToMove.ResourceGroupName -Force
            }
        }
    }

    $OperatingSystemDiskDetails = @()
    $DataDisksDetails = @()

    Write-Host "Creating a Disk Access Url for the Operating System Virtual Hard Disk. Please wait..." -ForegroundColor Green
    if ($ResourceGroupNewName)
    {
        $OSDiskAccessUrl = Grant-AzDiskAccess -ResourceGroupName $ResourceGroupOldName -DiskName $($VirtualMachineToMove.StorageProfile.OsDisk.Name) -Access Read -DurationInSecond 8000
    }
    else
    {
        $OSDiskAccessUrl = Grant-AzDiskAccess -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -DiskName $($VirtualMachineToMove.StorageProfile.OsDisk.Name) -Access Read -DurationInSecond 8000
    }

    $OperatingSystemDiskDetails += @{OSDiskName = $($VirtualMachineToMove.StorageProfile.OsDisk.Name);OSDiskAccessUrl = $($OSDiskAccessUrl.AccessSAS)}

    [Int]$DataDisksCount = 1
    Write-Host "Found $($($VirtualMachineToMove.StorageProfile.DataDisks).Count) Data Disks" -ForegroundColor Green

    foreach ($DataDisk in $($VirtualMachineToMove.StorageProfile.DataDisks))
    {
        Write-Host "Creating a Disk Access Url for Data Disk $DataDisksCount. Please wait..." -ForegroundColor Green
    
        if ($ResourceGroupNewName)
        {
            $DataDiskAccessUrl = Grant-AzDiskAccess -ResourceGroupName $ResourceGroupOldName -DiskName $($DataDisk.Name) -Access Read -DurationInSecond 8000
            $DataDiskDetails = [psobject]::new()
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskName' -Value $($DataDisk.Name)
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskLun' -Value $($DataDisk.Lun)
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskAccessUrl' -Value $($DataDiskAccessUrl.AccessSAS)
            $DataDisksDetails += $DataDiskDetails
            $DataDisksCount ++
        }
        else
        {
            $DataDiskAccessUrl = Grant-AzDiskAccess -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -DiskName $($DataDisk.Name) -Access Read -DurationInSecond 8000
            $DataDiskDetails = [psobject]::new()
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskName' -Value $($DataDisk.Name)
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskLun' -Value $($DataDisk.Lun)
            $DataDiskDetails | Add-Member -MemberType NoteProperty -Name 'DataDiskAccessUrl' -Value $($DataDiskAccessUrl.AccessSAS)
            $DataDisksDetails += $DataDiskDetails
            $DataDisksCount ++
        }
    }

    # Enviornment Selection
    $Environments = Get-AzEnvironment
    $Environment = $Environments | Out-GridView -Title "Please Select the Destination Virtual Machine Azure Stack Enviornment." -PassThru

    #region Connect to Azure
    try
    {
        Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
    }
    catch
    {
        Write-Error -Message $_.Exception
        break
    }

    try 
    {
        $Subscriptions = Get-AzSubscription
        if ($Subscriptions.Count -gt '1')
        {
            $Subscription = $Subscriptions | Out-GridView -Title "Please select the Subscription for the Destination Virtual Machine." -PassThru
            Set-AzContext $Subscription
        }
    }
    catch
    {
        Write-Error -Message $_.Exception
        break
    }

    $Location = Get-AzLocation
    #endregion

    if (!(Get-AzResourceGroup -Name $VirtualMachineToMove.ResourceGroupName -Location $Location -ErrorAction Ignore))
    {
        Write-Host "Resource Group $($VirtualMachineToMove.ResourceGroupName) was not found" -ForegroundColor Yellow
        Write-Host "Creating Resource Group $($VirtualMachineToMove.ResourceGroupName)" -ForegroundColor Green
        $DestinationResourceGroup = New-AzResourceGroup -Name $VirtualMachineToMove.ResourceGroupName -Location $Location.Location
    }
    else
    {
        $DestinationResourceGroup = Get-AzResourceGroup -Name $VirtualMachineToMove.ResourceGroupName -Location $Location
    }

    $StorageAccountName = 'migration' + (Get-Random -Minimum 100000 -Maximum 1000000) + 'sa'
    Write-Host "Creating Migration Storage Account $StorageAccountName" -ForegroundColor Green
    $DestinationStorageAccount = New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -Location $Location.Location -SkuName Standard_LRS -Kind Storage -Verbose
    $DestinationStorageAccountContainer = New-AzStorageContainer -Context $DestinationStorageAccount.Context -Name vmdisks -Permission Container -Verbose

    $OperatingSystemDiskVHDName = $OperatingSystemDiskDetails.OSDiskName + '.vhd'

<#  This will be used if/when AzCopy works with Hub Disk Access URLs
    Write-Host "Creating a SAS Token for the Storage Account Container" -ForegroundColor Green
    $StartTime = Get-Date
    $EndTime = $startTime.AddHours(24.0)
    $SASToken = New-AzStorageContainerSASToken -Context $DestinationStorageAccount.Context -Container $DestinationStorageAccountContainer -Permission rwdl -StartTime $StartTime -ExpiryTime $EndTime -ErrorAction Stop
    $DestinationUrl = $($DestinationStorageAccountContainer.Context.BlobEndPoint) + $($DestinationStorageAccountContainer.Name) + '/' + $OperatingSystemDiskVHDName + $SASToken
#>
    Write-Host "Copying OS Disk to migration Storage Account. This may take some time. Please wait..." -ForegroundColor Green
    Start-AzStorageBlobCopy -AbsoluteUri $($OperatingSystemDiskDetails.OSDiskAccessUrl) -DestBlob $OperatingSystemDiskVHDName -DestContainer $($DestinationStorageAccountContainer.Name) -DestContext $DestinationStorageAccount.Context
    Get-AzStorageBlobCopyState -Blob $OperatingSystemDiskVHDName -Container $($DestinationStorageAccountContainer.Name) -Context $DestinationStorageAccount.Context -WaitForComplete

    if ($DataDisksDetails)
    {
        [Int]$DataDiskProgressCount = 1
        foreach ($DataDisk in $DataDisksDetails)
        {
            $DataDiskVHDName = $DataDisk.DataDiskName + '.vhd'
            $DestinationUrl = $($DestinationStorageAccountContainer.Context.BlobEndPoint) + $($DestinationStorageAccountContainer.Name) + '/' + $DataDiskVHDName + $SASToken
            Write-Host "Copying Data Disk $DataDiskProgressCount of $($DataDisksDetails.Count) to migration Storage Account. This may take some time. Please wait..." -ForegroundColor Green
            Start-AzStorageBlobCopy -AbsoluteUri $($DataDisk.DataDiskAccessUrl) -DestBlob $DataDiskVHDName -DestContainer $($DestinationStorageAccountContainer.Name) -DestContext $DestinationStorageAccount.Context
            Get-AzStorageBlobCopyState -Blob $DataDiskVHDName -Container $($DestinationStorageAccountContainer.Name) -Context $DestinationStorageAccount.Context -WaitForComplete
            $DataDiskProgressCount ++
        }
    }

    if ($VirtualMachineToMove.AvailabilitySetReference)
    {
        if (!($DestinationVirtualMachineAvailabilitySet = Get-AzAvailabilitySet -ResourceGroupName $VirtualMachineAvailabilitySet.ResourceGroupName -Name $VirtualMachineAvailabilitySet.Name -ErrorAction Ignore))
        {
            Write-Host "Availability Set $($VirtualMachineAvailabilitySet.Name) in Resource Group $($VirtualMachineAvailabilitySet.ResourceGroupName) was not found!" -ForegroundColor Yellow
            Write-Host "Creating Availability Set $($VirtualMachineAvailabilitySet.Name) in Resource Group $($VirtualMachineAvailabilitySet.ResourceGroupName)" -ForegroundColor Green
            if (!(Get-AzResourceGroup -Name $($VirtualMachineAvailabilitySet.ResourceGroupName) -ErrorAction Ignore))
            {
                New-AzResourceGroup -Name $($VirtualMachineAvailabilitySet.ResourceGroupName) -Location $Location.Location
            }
            $DestinationVirtualMachineAvailabilitySet = New-AzAvailabilitySet -ResourceGroupName $VirtualMachineAvailabilitySet.ResourceGroupName `
                -Name $VirtualMachineAvailabilitySet.Name `
                -Location $Location.Location `
                -PlatformUpdateDomainCount $($VirtualMachineAvailabilitySet.PlatformUpdateDomainCount) `
                -PlatformFaultDomainCount $($VirtualMachineAvailabilitySet.PlatformFaultDomainCount) `
                -Sku $($VirtualMachineAvailabilitySet.Sku)
        }
    }

    if ($VirtualMachineToMove.DiagnosticsProfile.BootDiagnostics)
    {
        if (!($DestinationVirtualMachineBootDiagnosticsStorageAccount = Get-AzStorageAccount -ResourceGroupName $BootDiagnostictsSourceStorageAccount.ResourceGroupName -Name $BootDiagnostictsSourceStorageAccount.StorageAccountName -ErrorAction Ignore))
        {
            Write-Host "Virtual Machine Boot Diagnostics StorageAccount $($BootDiagnostictsSourceStorageAccount.StorageAccountName) was not found in Resource Group $($BootDiagnostictsSourceStorageAccount.ResourceGroupName)" -ForegroundColor Yellow
            Write-Host "Creating Virtual Machine Diagnostics StorageAccount" -ForegroundColor Green
            if (!(Get-AzResourceGroup -Name $($BootDiagnostictsSourceStorageAccount.ResourceGroupName) -ErrorAction Ignore))
            {
                New-AzResourceGroup -Name $($BootDiagnostictsSourceStorageAccount.ResourceGroupName) -Location $Location.Location
            }
            $DestinationVirtualMachineBootDiagnosticsStorageAccount = New-AzStorageAccount -ResourceGroupName $BootDiagnostictsSourceStorageAccount.ResourceGroupName -Name $BootDiagnostictsSourceStorageAccount.StorageAccountName -SkuName Standard_LRS -Location $Location.Location -ErrorAction Stop
        }
    }
    
    # Create Nic NSG
    $DestinationInterfaceNetworkSecurityGroups = @()
    if ($InterfaceNetworkSecurityGroupDetails)
    {
        Write-Host "Checking for Network Interface Network Security Groups"
        foreach ($InterfaceNetworkSecurityGroup in $InterfaceNetworkSecurityGroupDetails)
        {
            if (!($DestinationInterfaceNetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name $($InterfaceNetworkSecurityGroup.Name) -ResourceGroupName $($InterfaceNetworkSecurityGroup.ResourceGroupName) -ErrorAction Ignore))
            {
                Write-Host "Network Security Group $($InterfaceNetworkSecurityGroup.Name) in Resource Group $($InterfaceNetworkSecurityGroup.ResourceGroupName) was not found!" -ForegroundColor Yellow
                Write-Host "Creating Network Security Group $($InterfaceNetworkSecurityGroup.Name) in Resource Group $($InterfaceNetworkSecurityGroup.ResourceGroupName)" -ForegroundColor Green
                if (!(Get-AzResourceGroup -Name $($InterfaceNetworkSecurityGroup.ResourceGroupName) -ErrorAction Ignore))
                {
                    New-AzResourceGroup -Name $($InterfaceNetworkSecurityGroup.ResourceGroupName) -Location $Location.Location
                }

                $DestinationInterfaceNetworkSecurityGroup = New-AzNetworkSecurityGroup -Name $($InterfaceNetworkSecurityGroup.Name) `
                    -ResourceGroupName $($InterfaceNetworkSecurityGroup.ResourceGroupName) `
                    -Location $Location.Location -Force
                $DestinationInterfaceNetworkSecurityGroup.SecurityRules = $InterfaceNetworkSecurityGroup.SecurityRules
                $DestinationInterfaceNetworkSecurityGroup | Set-AzNetworkSecurityGroup
                $DestinationInterfaceNetworkSecurityGroups += $DestinationInterfaceNetworkSecurityGroup
            }
            else
            {
                $DestinationInterfaceNetworkSecurityGroups += $DestinationInterfaceNetworkSecurityGroup
            }
        }
    }

    $DestinationPublicIPs = @()
    Write-Host "Checking Public IPs" -ForegroundColor Green
    if ($InterfacePublicIPDetails)
    {
        Foreach ($InterfacePublicIP in $InterfacePublicIPDetails)
        {
            if (!($DestinationPublicIP = Get-AzPublicIpAddress -Name $InterfacePublicIP.Name -ResourceGroupName $InterfacePublicIP.ResourceGroupName -ErrorAction Ignore))
            {
                Write-Host "Public IP $($InterfacePublicIP.Name) in Resource Group $($InterfacePublicIP.ResourceGroupName) was not found!" -ForegroundColor Yellow
                Write-Host "Creating Public IP $($InterfacePublicIP.Name) in Resource Group $($InterfacePublicIP.ResourceGroupName)" -ForegroundColor Green

                if (!(Get-AzResourceGroup -Name $($InterfacePublicIP.ResourceGroupName) -ErrorAction Ignore))
                {
                    New-AzResourceGroup -Name $($InterfacePublicIP.ResourceGroupName) -Location $Location.Location
                }
                $DestinationPublicIP = New-AzPublicIpAddress -Name $($InterfacePublicIP.Name) `
                    -ResourceGroupName $($InterfacePublicIP.ResourceGroupName) `
                    -AllocationMethod $($InterfacePublicIP.PublicIpAllocationMethod) `
                    -Location $Location.Location -Sku $($InterfacePublicIP.Sku.Name)

                $DestinationPublicIPs += $DestinationPublicIP
            }
            else
            {
                $DestinationPublicIPs += $DestinationPublicIP
            }
        }
    }

    $ExistingVirtualNetworks = Get-AzVirtualNetwork
    foreach ($VirtualNetwork in $VirtualMachineVirtualNetworkInformation)
    {
        if ($ExistingVirtualNetworks.Name -notcontains $VirtualNetwork.Name)
        {
            Write-Warning "The Virtual Network $($VirtualNetwork.Name) was not found!"
            Write-host "Would you like to create the Virtual Network from the Source Azure Stack Subscription? (Default is No)" -ForegroundColor Yellow 
            $CreateVirtualNetworkAnswer = Read-Host " ( Yes / No ) "

            if (($CreateVirtualNetworkAnswer -eq 'No') -or (!($CreateVirtualNetworkAnswer)))
            {
                $VirtualNetworks = @()
                $VirtualNetworks += (Get-AzVirtualNetwork).Name

                $VirtualNetworkNameCheckRegEx = '^[a-zA-Z0-9](?:[a-zA-Z0-9_-]*[a-zA-Z0-9])?$'

                $VirtualNetworkName = $VirtualNetworks | Out-GridView -Title "Please Select an existing Virtual Network for the Virtual Machine." -PassThru

                $DestinationVirtualNetwork = Get-AzVirtualNetwork | Where-Object {$_.Name -eq $VirtualNetworkName}

                $VirtualNetworkSubnets = @()
                foreach ($Subnet in $VirtualNetwork.Subnets)
                {
                    $VirtualNetworkSubnets += New-Object PSObject -Property ([ordered]@{Name=$($Subnet.Name);AddressPrefix=$($Subnet.AddressPrefix)})
                }
                $VirtualNetworkSubnet = $VirtualNetworkSubnets | Out-GridView -Title "Please Select an existing Virtual Network Subnet for the Virtual Machine." -PassThru

                $VirtualNetworkSubnet = $VirtualNetwork.Subnets | Where-Object {$_.Name -eq $VirtualNetworkSubnet.Name}
                $DestinationSubnetConfig = $DestinationVirtualNetwork | Get-AzVirtualNetworkSubnetConfig -Name $VirtualNetworkSubnet.Name
                $DestinationVirtualNetworkResourceGroup = Get-AzResourceGroup -Name $VirtualNetwork.ResourceGroupName

            }
            else
            {           
                if (!(Get-AzResourceGroup -Name $VirtualNetwork.ResourceGroupName -Location $Location.Location -ErrorAction Ignore))
                {
                    Write-Host "Resource Group $($VirtualNetwork.ResourceGroupName) was not found" -ForegroundColor Yellow
                    Write-Host "Creating Resource Group $($VirtualNetwork.ResourceGroupName)" -ForegroundColor Green
                    $DestinationVirtualNetworkResourceGroup = New-AzResourceGroup -Name $($VirtualNetwork.ResourceGroupName) -Location $Location.Location
                }
                else
                {
                    $DestinationVirtualNetworkResourceGroup = Get-AzResourceGroup -Name $($VirtualNetwork.ResourceGroupName) -Location $Location
                }

                Write-Host "Creating Virtual Network $($VirtualNetwork.Name) in Resource Group $($VirtualNetwork.ResourceGroupName) Please wait..." -ForegroundColor Green

                foreach ($VirtualNetworkSubnet in $VirtualNetwork.Subnets)
                {
                    
                    $Params = @{
                        Name=$($VirtualNetworkSubnet.Name)
                        AddressPrefix=$($VirtualNetworkSubnet.AddressPrefix)
                    }
                    if ($VirtualNetworkSubnet.RouteTable.Id)
                    {
                        $SubnetRouteTable = $DestinationVirtualNetworkSubnetNetworkRouteTables | Where-Object {$_.Name -eq $VirtualNetworkSubnet.RouteTable.Id.Split('/')[8]} 
                        $Params += @{RouteTableId=$($SubnetRouteTable.Id)}
                    }
                    if ($VirtualNetworkSubnet.NetworkSecurityGroup.Id)
                    {
                        $NetworkSecurityGroup = $DestinationSubnetNetworkSecurityGroups | Where-Object {$_.Name -eq $VirtualNetworkSubnet.NetworkSecurityGroup.Id.Split('/')[8]}
                        $Params += @{NetworkSecurityGroupId=$($NetworkSecurityGroup.Id)}
                    }

                    $DestinationSubnetConfig = New-AzVirtualNetworkSubnetConfig @Params

                }
                $DestinationVirtualNetwork = New-AzVirtualNetwork -Name $VirtualNetwork.Name `
                    -ResourceGroupName $VirtualNetwork.ResourceGroupName `
                    -Location $Location.Location `
                    -Subnet $DestinationSubnetConfig -AddressPrefix $VirtualNetwork.AddressSpace.AddressPrefixes

                #Create Subnet NSG
                $DestinationSubnetNetworkSecurityGroups = @()
                if ($VirtualMachineVirtualNetworkSubnetInformation.NetworkSecurityGroup.Id)
                {
                    foreach ($VirtualNetworkSubnetNetworkSecurityGroupId in $($VirtualMachineVirtualNetworkSubnetInformation.NetworkSecurityGroup.Id))
                    {
                        if (!($DestinationSubnetNetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name $VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[8] -ResourceGroupName $VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4] -ErrorAction Ignore))
                        {
                            Write-Host "Network Security Group $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[8]) in Resource Group $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4]) was not found!" -ForegroundColor Yellow
                            Write-Host "Creating Network Security Group $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[8]) in Resource Group $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4])" -ForegroundColor Green
                            if (!(Get-AzResourceGroup -Name $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4]) -ErrorAction Ignore))
                            {
                                New-AzResourceGroup -Name $($VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4]) -Location $Location.Location
                            }
                            $DestinationSubnetNetworkSecurityGroup = New-AzNetworkSecurityGroup -Name $VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[8] `
                                -ResourceGroupName $VirtualNetworkSubnetNetworkSecurityGroupId.Split('/')[4] `
                                -Location $Location.Location
                            $DestinationVirtualNetworkSubnetNetworkSecurityGroupDetails = $VirtualNetworkSubnetNetworkSecurityGroupDetails | Where-Object {$_.Id -eq $VirtualNetworkSubnetNetworkSecurityGroupId}
                            $DestinationSubnetNetworkSecurityGroup.SecurityRules = $DestinationVirtualNetworkSubnetNetworkSecurityGroupDetails.SecurityRules
                            $DestinationSubnetNetworkSecurityGroup | Set-AzNetworkSecurityGroup
                            $DestinationSubnetNetworkSecurityGroups += $DestinationSubnetNetworkSecurityGroup
                        }
                        else
                        {
                            $DestinationSubnetNetworkSecurityGroups += $DestinationSubnetNetworkSecurityGroup
                        }
                    }
                }

                #Create RouteTable
                $DestinationVirtualNetworkSubnetNetworkRouteTables = @()
                if ($RouteTables)
                {
                    Write-Host "Checking Route Tables" -ForegroundColor Green
        
                    foreach ($RouteTable in $RouteTables)
                    {
                        if (!($DestinationVirtualNetworkSubnetNetworkRouteTable = Get-AzRouteTable -ResourceGroupName $RouteTable.ResourceGroupName -Name $RouteTable.Name -ErrorAction Ignore))
                        {
                            Write-Host "Route Table $($RouteTable.Name) in Resource Group $($RouteTable.ResourceGroupName) was not found!" -ForegroundColor Yellow
                            Write-Host "Creating Route Table $($RouteTable.Name) in Resource Group $($RouteTable.ResourceGroupName)" -ForegroundColor Green

                            if (!(Get-AzResourceGroup -Name $($RouteTable.ResourceGroupName) -ErrorAction Ignore))
                            {
                                New-AzResourceGroup -Name $($RouteTable.ResourceGroupName) -Location $Location.Location
                            }
                            $DestinationVirtualNetworkSubnetNetworkRouteTable = New-AzRouteTable -Name $RouteTable.Name `
                                -ResourceGroupName $RouteTable.ResourceGroupName `
                                -Location $Location.Location
                            $DestinationVirtualNetworkSubnetNetworkRouteTable.Routes = $RouteTable.Routes
                            $DestinationVirtualNetworkSubnetNetworkRouteTable | Set-AzRouteTable
                
                        }
                        else
                        {
                            $DestinationVirtualNetworkSubnetNetworkRouteTables += $DestinationVirtualNetworkSubnetNetworkRouteTable
                        }
                    }
                }
            }
        }
    }

    $VirtualMachineManagedDisks = @()
    
    Write-Host "Getting Virtual Machine Disk information" -ForegroundColor Green
    $Disks = Get-AzStorageBlob -Container $($DestinationStorageAccountContainer.Name) -Context $DestinationStorageAccount.Context | Select-Object -Property *

    $VMManagedDisks = @()

    $OperatingSystemDisk = $Disks | Where-Object {$_.Name -like "$($VirtualMachineToMove.StorageProfile.OsDisk.Name)*"}
    $SourceUri = $OperatingSystemDisk.Context.BlobEndPoint + $($DestinationStorageAccountContainer.Name) + '/' + $OperatingSystemDiskDetails.OSDiskName + '.vhd'

    Write-Host "Creating Managed Disk $($OperatingSystemDisk.Name.Replace('.vhd','')) in Resource Group $($VirtualMachineToMove.ResourceGroupName)"
    $DiskConfig = New-AzDiskConfig -Location $Location.Location -AccountType Standard_LRS -CreateOption Import -SourceUri $SourceUri -StorageAccountId $DestinationStorageAccount.Id
    $VMManagedDisk = New-AzDisk -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -DiskName $($OperatingSystemDisk.Name.Replace('.vhd','')) -Disk $DiskConfig
    $VMManagedDisks += $VMManagedDisk

    foreach ($Disk in ($Disks | Where-Object {$_.Name -notlike "$($VirtualMachineToMove.StorageProfile.OsDisk.Name)*"}))
    {
        $SourceUri = $Disk.Context.BlobEndPoint + $($DestinationStorageAccountContainer.Name) + '/' + $Disk.Name
        $DiskConfig = New-AzDiskConfig -Location $Location.Location -AccountType Standard_LRS -CreateOption Import -SourceUri $SourceUri -StorageAccountId $DestinationStorageAccount.Id
        $VMManagedDisk = New-AzDisk -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName) -DiskName $($Disk.Name.Replace('.vhd','')) -Disk $DiskConfig
        $VMManagedDisks += $VMManagedDisk
    }

    # VM Configuration
    $VMConfigParams = @{
        VMSize=$($VirtualMachineToMove.HardwareProfile.VmSize)
        VMName=$($VirtualMachineToMove.Name)
    }

    if ($VirtualMachineAvailabilitySet)
    {
        $VMConfigParams += @{AvailabilitySetId=$($DestinationVirtualMachineAvailabilitySet.Id)}
    }

    $VMConfig = New-AzVMConfig @VMConfigParams

    foreach ($ManagedDisk in $VMManagedDisks)
    {
        if ($ManagedDisk.Name -eq $($OperatingSystemDisk.Name.Replace('.vhd','')))
        {
            if ($VirtualMachineOperatingSystem -eq 'Windows')
            {
                $VMConfig = Set-AzVMOSDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id -Windows
            }
            if ($VirtualMachineOperatingSystem -eq 'Linux')
            {
                $VMConfig = Set-AzVMOSDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id  -Linux
            }
        }
        else
        {
            $DataDisk = $DataDisksDetails | Where-Object {$_.DataDiskName -eq $($ManagedDisk.Name)}
            Add-AzVMDataDisk -VM $VMConfig -Name $ManagedDisk.Name -CreateOption Attach -ManagedDiskId $ManagedDisk.Id -Lun $DataDisk.DataDiskLun
        }
    }

    foreach ($VirtualMachineNIC in $VirtualMachineNetworkInformation)
    {
        $NetworkInterfaceParams = @{
            ResourceGroupName=$VirtualMachineNIC.InterfaceNameResourceGroupName
            Name=$VirtualMachineNIC.InterfaceName
            Location=$Location.Location
            SubnetId=($DestinationVirtualNetwork.Subnets | Where-Object {$_.Name -eq $VirtualNetworkSubnetDetails.Name}).Id
        }

        if ($VirtualMachineNIC.InterfacePublicIPAddressAllocationMethod)
        {
            $NetworkInterfaceParams += @{PublicIpAddressId=$(($DestinationPublicIPs | Where-Object {$_.Name -eq $($VirtualMachineNIC).InterfacePublicIPAddressName}).Id)}
        }

        if ($VirtualMachineNIC.InterfaceNetworkSecurityGroupName)
        {
            $NetworkInterfaceParams += @{NetworkSecurityGroupId=$(($DestinationInterfaceNetworkSecurityGroups | Where-Object {$_.Name -eq $($VirtualMachineNIC).InterfaceNetworkSecurityGroupName}).Id)}
        }

        $NetworkInterface = New-AzNetworkInterface @NetworkInterfaceParams
        if ($($VirtualMachineNIC.Primary) -eq $true)
        {
            Add-AzVMNetworkInterface -VM $VMConfig -Id $NetworkInterface.Id -Primary -Verbose
            Write-Host "Setting $($NetworkInterface.Id) as Primary" -ForegroundColor Green
        }
        if ($($VirtualMachineNIC.Primary) -ne $true)
        {
            Add-AzVMNetworkInterface -VM $VMConfig -Id $NetworkInterface.Id -Verbose
            Write-Host "Setting $($NetworkInterface.Id) as Secondary" -ForegroundColor Yellow
        }
    }

    if ($VirtualMachineToMove.DiagnosticsProfile.BootDiagnostics.Enabled -eq $true)
    {
        Set-AzVMBootDiagnostic -VM $VMConfig -Enable -ResourceGroupName $DestinationVirtualMachineBootDiagnosticsStorageAccount.ResourceGroupName -StorageAccountName $DestinationVirtualMachineBootDiagnosticsStorageAccount.StorageAccountName
    }

    if ($VirtualMachineDiagnosticsExtension)
    {
        if (!($DestinationVirtualMachineDiagnosticsStorageAccount = Get-AzStorageAccount -ResourceGroupName $VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName -Name $VirtualMachineDiagnosticsExtensionStorageAccount.StorageAccountName -ErrorAction Ignore))
        {
            Write-Host "Virtual Machine Diagnostics StorageAccount $($VirtualMachineDiagnosticsExtensionStorageAccount.StorageAccountName) was not found in Resource Group $($VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName)" -ForegroundColor Yellow
            Write-Host "Creating Virtual Machine Diagnostics StorageAccount" -ForegroundColor Green
            if (!(Get-AzResourceGroup -Name $($VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName) -ErrorAction Ignore))
            {
                New-AzResourceGroup -Name $($VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName) -Location $Location.Location
            }
            $DestinationVirtualMachineDiagnosticsStorageAccount = New-AzStorageAccount -ResourceGroupName $VirtualMachineDiagnosticsExtensionStorageAccount.ResourceGroupName -Name $VirtualMachineDiagnosticsExtensionStorageAccount.StorageAccountName -SkuName Standard_LRS -Location $Location.Location -ErrorAction Stop
        }

        #$EncodedConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($VirtualMachineDiagnosticsExtensionPublicSettingsXML))
        #Set-AzVMDiagnosticsExtension -VM $VMConfig -StorageContext $DestinationVirtualMachineDiagnosticsStorageAccount.Context -ResourceGroupName $DestinationVirtualMachineDiagnosticsStorageAccount.ResourceGroupName 
    }

    Write-Host "Creating New Virtual Machine $($VirtualMachineToMove.Name) in Resource Group $($VirtualMachineToMove.ResourceGroupName)" -ForegroundColor Green
    Write-Host "This may take a few minutes. Please wait..." -ForegroundColor Green
    New-AzVM -VM $VMConfig -Location $Location.Location -ResourceGroupName $($VirtualMachineToMove.ResourceGroupName)
}

Remove-AzStorageAccount -ResourceGroupName $DestinationStorageAccount.ResourceGroupName -Name $DestinationStorageAccount.StorageAccountName -Force
