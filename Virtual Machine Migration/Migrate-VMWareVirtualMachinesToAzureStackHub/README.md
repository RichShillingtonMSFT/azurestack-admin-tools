# Migrate vmware vCenter Virtual Machines to Azure Stack Hub

This PowerShell Module is used to Migrate Virtual Machines on vmware vCenter to Azure Stack Hub.

***

## Requirements

- You must have the Hyper-V PowerShell Module installed
- The automation will install the PowerCLI module if it not already installed
- You must have enough disk space on your migration workstation to hold the virtual machine disks x2
- You must be able to connect to vCenter using PowerCLI
- This process will shutdown the Source Virtual Machine during migration
- You must have Microsoft Virtual Machine Converter installed.
    - You can find the .msi in this folder should you need it.   
- You must have an account in a Azure Stack Hub Subscription
- Virtual Machines MUST use BIOS NOT EFI. (I am working on this, but it will take some time.)

***

# Installation

Install this folder in your preferred PowerShell Modules directory.

From a PowerShell console run:

```
Import-Module -Name Migrate-VMWareVirtualMachinesToAzureStackHub
```
***

# Migration Process

The first step is to get the migration readiness reports.

From a PowerShell Window run: 

```
$VCenterHost = '[vCenter Host Name or IP]'

$Credentials = Get-Credential -Message 'Enter Your Credentials for vCenter'

Get-VMWareVMMigrationReadinessReport -VCenterHost $VCenterHost -Credentials $Credentials
```

This will a CSV files in your Documents folder.

- VMWareVMsNOTReadyForMigration[date].csv

Seeing as these are coming from vmware, they will need a little work before we can move on to migration.
This file will show you the changes that will happen when you run through this process.


Example: ![image](https://user-images.githubusercontent.com/43886859/113306225-dc7e0a80-92d1-11eb-802f-a6eea735fcf3.png)

***

## To Migrate a VM listed in the VMsReadyForMigration report, follow these steps:

### Install the Windows Azure Virtual Machine Agent:

```
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


### Export the Virtual Machine so we can get it ready

This process connects to vCenter and exports the VM to your local workstation.
Therefore you must ensure you use the name of the Source Vitual Machine for the $VirtualMachineName variable and ensure you have adequate disk space.

   **NOTE: This process will shutdown the source vm when performing the copy!**

```
$VCenterHost = '[vCenter Host Name or IP]'

$Credentials = Get-Credential -Message 'Enter Your Credentials for vCenter'

$VirtualMachineName = '[Name of the Virtual Machine to Migrate]'

$VMSaveLocation = '[Path to save the exported VM files]'

Invoke-VMWareVMExport -VirtualMachineName $VirtualMachineName -VCenterHost $VCenterHost -Credentials $Credentials -VMSaveLocation $VMSaveLocation
```

Once complete you will have a folder in the path you specified containing each virtual disk, and ovf file and some other files we don't care about.
This will also create a csv file in your documents folder [VirtualMachineName]-ExportData.csv. This file contains the paths to exported files so we can find them later.

### Convert VMDK to VHD

We need to make sure that the disks we exported are VHD files and that they are thick provisioned.
To accomplish this, we will run the following command.

```
Convert-VMDKToVHD -VirtualMachineName $VirtualMachineName
```

This command will pickup the [VirtualMachineName]-ExportData.csv that was created in the last step and convert all the VMDK files to thick provisioned VHDs using Microsoft Virtual Machine Converter


### Make sure the disks are the correct size

Once we have nice fixed size VHD files, we want to align them with a standard Azure disk size. To do that, just run the following command.

```
Invoke-VMWareVHDRightSizing -VirtualMachineName $VirtualMachineName
```

This will adjust the size of the VHD files to nearest match. 
For example if you have a 100gb disk, it will be upsized to 128gb. A 200gb disk will be upsized to 256gb.


### Copy the VHD files to Azure Stack Storage

This process will take all those happy VHD files and put them up in Azure Stack so we can make a new VM out of them.

```
$VirtualMachineName = '[Name of the Virtual Machine to Migrate]'

Invoke-VMWareVMImageCopyHyperVToAzureStackHub -VirtualMachineName $VirtualMachineName
```

You will be prompted to select an existing destination storage account or you can choose to create a new one. 
Only storage accounts with a blob container that allows Blob (anonymous read access for blobs only) will be displayed.

Once complete, a CSV file will be created in your Documents folder called [VMName]-DiskData.csv. 
This file contains the list of disks from the source VM as well as the URL so we can find them later. 

### Create the new VM on Azure Stack from the uploaded VHD

This process will create a new Virtual Machine in Azure Stack Hub from the VHD files we just uploaded.
It will use the files from all the previous steps.


```
$VirtualMachineName = '[Name of the Virtual Machine to Migrate]'

New-AzureStackVirtualMachineFromVMWareDataFile -VirtualMachineName  $VirtualMachineName
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

HAPPY MIGRATING!!
