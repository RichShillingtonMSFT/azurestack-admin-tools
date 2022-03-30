# Gather Azure Stack Hub Physical Disk Information from BMC

This script can be used to pull physical disk information from an Azure Stack Hub that has iDrac for BMC. This includes Dell stamps and Microsoft Rugged Stamp.

## Requirements

- You must have the BMC credentials (iDrac login)
- You must run this on a host that has connectivity to the BMC.
- You must specify the number of nodes in your stamp. Do not include the HLH in the total.

From a PowerShell console run:
```
#NumberOfNodes is the total count of nodes on the stamp. From 4 - 16.
#FirstBMCNodeIP is the IP of the HLH idrac.

.\Export-AzSHubDiskInfoToCSV.ps1 -NumberOfNodes '4' -FirstBMCNodeIP '10.0.1.2'
```

This will save a CSV file in your Documents folder unless you specify an alternate location using the -FileSaveLocation parameter.

- ASHDiskData-[date].csv

Example Output: ![Example](https://user-images.githubusercontent.com/43886859/160815731-e806f5f8-06e0-4b14-8d57-d22dc2d9ec91.jpg)

