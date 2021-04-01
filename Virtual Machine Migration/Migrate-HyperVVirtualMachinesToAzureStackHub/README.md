# Migrate Hyper-V Virtual Machines to Azure Stack Hub

This PowerShell Module is used to Migrate Virtual Machines on Hyper-V to Azure Stack Hub.

## Requirements
- You must have the Hyper-V PowerShell Module installed
- Source Hyper-V Host and Source Virtual Machine Must have PSRemoting Enabled
- You must be able to connect to the Source Hyper-V Host and Source Virtual Machine via UNC Path
- This process will shutdown the Source Virtual Machine during migration

