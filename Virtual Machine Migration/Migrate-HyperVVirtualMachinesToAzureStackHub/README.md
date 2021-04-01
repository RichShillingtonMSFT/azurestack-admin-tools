# Migrate Hyper-V Virtual Machines to Azure Stack Hub

This PowerShell Module is used to Migrate Virtual Machines on Hyper-V to Azure Stack Hub.

***

## Requirements

- You must have the Hyper-V PowerShell Module installed
- Source Hyper-V Host and Source Virtual Machine Must have PSRemoting Enabled
- You must be able to connect to the Source Hyper-V Host and Source Virtual Machine via UNC Path
- This process will shutdown the Source Virtual Machine during migration
- You must have enough free space on the source Hyper-V server to accommodate thick provisioned disk as well as backup copies for repaired VMs
- You must have an account in a Azure Stack Hub Subscription

***

# Installation

Install this folder in your preferred PowerShell Modules directory.

From a PowerShell console run:
- Import-Module -Name Migrate-HyperVVirtualMachinesToAzureStackHub
- Import-Module -Name Hyper-V

***

# Migration Process

The first step is to get the migration readiness reports.

From a PowerShell Window run: 

$HypervisorHost = '[HyperVisor Host Name or IP]'

$Credentials = Get-Credential -Message 'Enter Your Credentials for The Source Hypervisor Host'

Get-HyperVVMMigrationReadinessReport -HypervisorHost $HypervisorHost -Credentials $Credentials

This will save two CSV files in your Documents folder.

- VMsNOTReadyForMigration[date].csv

Example: ![image](https://user-images.githubusercontent.com/43886859/113286428-307cf500-92ba-11eb-9899-67ac1a0101bd.png)

- VMsReadyForMigration[date].csv

Example:

![image](https://user-images.githubusercontent.com/43886859/113286475-412d6b00-92ba-11eb-8792-bc57ac9c4e2e.png)

***

## To Migrate a VM listed in the VMsReadyForMigration report, follow these steps:

### Install the Windows Azure Virtual Machine Agent:

```
$Credentials = Get-Credential -Message 'Enter Your Credentials for The Source Hypervisor Host'

$VirtualMachineCredentials = Get-Credential -Message 'Enter Your Credentials for The Source Virtual Machine'

$VirtualMachineName = '[Name or IP of the Virtual Machine to Migrate]'

Install-WindowsAzureVirtualMachineAgent -VirtualMachineCredentials $VirtualMachineCredentials -VirtualMachineName $VirtualMachineName -Verbose
```

This portion of the automation currently only supports Windows VMs. To install the Virtual Machine Agent on Linux, please follow the instructions here: [Move Specialized Linux VM](https://docs.microsoft.com/en-us/azure-stack/user/vm-move-specialized?view=azs-2008&tabs=port-linux#generalize-the-vhd)

### Make configuration changes on the Source Virtual Machine required to run in Azure

```
Invoke-WindowsAzureVirtualMachineSettingsConfiguration -VirtualMachineCredentials $VirtualMachineCredentials -VirtualMachineName $VirtualMachineName -Verbose
```

This portion of the automation currently only supports Windows VMs. To prepare Linux to run in Azure, please follow the instructions here: [Move Specialized Linux VM](https://docs.microsoft.com/en-us/azure-stack/user/vm-move-specialized?view=azs-2008&tabs=port-linux#generalize-the-vhd)


### Copy the VHD files to Azure Stack Storage

This process is perfomed on the Hyper-V Host via PSRemoting. Therefore you must ensure you use the name of the Source Vitual Machine for the $VirtualMachineName variable.

   **NOTE: This process will shutdown the source vm when performing the copy!**

```
$VirtualMachineName = '[Name of the Virtual Machine to Migrate]'

Invoke-HyperVVMImageCopyToAzureStackHub -VirtualMachineName $VirtualMachineName -HypervisorHost $HypervisorHost -Credentials $Credentials
```

You will be prompted to select an existing destination storage account or you can choose to create a new one. Only storage accounts with a blob container that allows Blob (anonymous read access for blobs only) will be displayed.

Once complete, a CSV file will be created in your Documents folder called [VMName]-DiskData.csv. This file contains the list of disks from the source VM as well as their controller number and location. It will be used in the next step to ensure that disks are put in the proper order on the new Azure Stack Hub VM.

### Create the new VM on Azure Stack from the uploaded VHD

This process will connect to the Hyper-V Host to determine the current source VM hardware settings. Therefore like the previous step, you must use the VM name and not the IP.

```
$VirtualMachineName = '[Name of the Virtual Machine to Migrate]'

$VirtualMachineOperatingSystem = '[Windows or Linux]'

New-AzureStackVirtualMachineFromHyperVAndDataFile -VirtualMachineName $VirtualMachineName -HypervisorHost $HypervisorHost -Credentials $Credentials -VirtualMachineOperatingSystem $VirtualMachineOperatingSystem
```

During execution you will need to respond to several prompts.

- What Resource Group do you want to store the new VM in
    - A list of Resource Groups will be displayed as well as the option to create a new one 

- What Virtual Network and Subnet do you want to use for the NIC
    - You will also be given the option to create a new VNet and Subnet

- Do you want the Private IP Address to be Dynamic or Static
    - If you choose Static a list of available IPs from the selected subnet will be displayed for you to choose from.

- Do you want to create a Public IP

- Do you want the Public IP to be Dynamic or Static

- You will be prompted to select a size for the new VM.
    - Only sizes equal to or greater than the original configuration of the source VM will be displayed.
 
***

## To Migrate a VM listed in the VMsNOTReadyForMigration report, follow these steps:

This process requires some automated "fixes" prior to migration. These include:
- Making sure the virtual disks are VHD format and not VHDX
- Ensuring the disk sizes align with Azure standard sizes
- Converting thin provisioned disks to thick disks

**NOTE! The repair process will use a lot of disk space!**

There will be a backup copy of each disk created for fallback

There will also be a new thick provisioned VHD created for each VHDX disk.

The VHD size will be increased to Azure standard sizes. 
Example: If VHD1 is 100Gb, it will be expanded to 128gb. If it is 200gb, it will be expanded to 256gb.

### Install the Windows Azure Virtual Machine Agent:

```
$Credentials = Get-Credential -Message 'Enter Your Credentials for The Source Hypervisor Host'

$VirtualMachineCredentials = Get-Credential -Message 'Enter Your Credentials for The Source Virtual Machine'

$VirtualMachineName = '[Name or IP of the Virtual Machine to Migrate]'

Install-WindowsAzureVirtualMachineAgent -VirtualMachineCredentials $VirtualMachineCredentials -VirtualMachineName $VirtualMachineName -Verbose
```

This portion of the automation currently only supports Windows VMs. To install the Virtual Machine Agent on Linux, please follow the instructions here: [Move Specialized Linux VM](https://docs.microsoft.com/en-us/azure-stack/user/vm-move-specialized?view=azs-2008&tabs=port-linux#generalize-the-vhd)

### Make configuration changes on the Source Virtual Machine required to run in Azure

```
Invoke-WindowsAzureVirtualMachineSettingsConfiguration -VirtualMachineCredentials $VirtualMachineCredentials -VirtualMachineName $VirtualMachineName -Verbose
```

This portion of the automation currently only supports Windows VMs. To prepare Linux to run in Azure, please follow the instructions here: [Move Specialized Linux VM](https://docs.microsoft.com/en-us/azure-stack/user/vm-move-specialized?view=azs-2008&tabs=port-linux#generalize-the-vhd)

