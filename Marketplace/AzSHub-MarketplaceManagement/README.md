# Azure Stack Hub Marketplace Management

Use this module to help you with maintaining your Azure Stack Hub Marketplace.

***

## Requirements

- You must have the Azure Stack RM modules installed for the version of Stack Hub you are running.
-- For help installing the PowerShell Modules see https://github.com/RichShillingtonMSFT/azurestack-admin-tools/blob/25a256d9ed69d93826a197a040bae13c43cce759/Operator%20Workstation%20Setup/Install-AzureStackToolsPowerShellModules.ps1
- You must connect to Azure Stack using an account that has access to the Default Provider Subscription

***

# Installation

Install this folder in your preferred PowerShell Modules directory.

From a PowerShell console run:
```
Import-Module -Name AzSHub-MarketplaceManagement
```

***

# Export a list of your Marketplace Items

If you are building a new Azure Stack Hub, deploying an ASDK for testing or recovering after a failure, 
making sure you have all the Marketplace items you need can be a time consuming process.

After you have all the items downloaded that you want in your Marketplace, you can run Export-MarketPlaceItemsToCSV to create a CSV export of your items.
You can use this to restore the identical items to any Azure Stack Hub or ASDK.

This command will export a CSV file to $env:USERPROFILE\Documents\MarketPlaceItems-[StackName]-[Date].csv.
You can change the export location by using the -FileSaveLocation parameter.

From a PowerShell console run:
```
Import-Module -Name AzSHub-MarketplaceManagement

Export-MarketPlaceItemsToCSV -FileSaveLocation 'C:\Marketplace\'

```

***

# Restore your Marketplace items from a the exported list

Using the exported Marketplace CSV file you created, you can run this on any Azure Stack Hub to restore your Marketplace items.
This will compare your list to the downloaded items in your Marketplace. Any missing items will be queued for download.

From a PowerShell console run:
```
Import-Module -Name AzSHub-MarketplaceManagement

Restore-MarketPlaceItemsFromCSV -CSVFileLocation 'C:\Marketplace\MarketPlaceItems-[StackName]-[Date].csv'

```

***


# Update your Marketplace items

Microsoft and our Partners are always updating the content available in the Marketplace. Keeping up with what changed was a time consuming process.
Not anymore. You can use Invoke-MarketPlaceItemsUpdate to automatically download the latest versions of your Marketplace items.
Current versions will remain downloaded until you decide to clean them up.

From a PowerShell console run:
```
Import-Module -Name AzSHub-MarketplaceManagement

Invoke-MarketPlaceItemsUpdate

```
After the command is run, you can pick ALL or select individual items to update.

***

# Clean up your Marketplace items

After updating your Marketplace items and testing any new downloads, you will want to clean up duplicates.

From a PowerShell console run:
```
Import-Module -Name AzSHub-MarketplaceManagement

Invoke-MarketPlaceItemsCleanup
```
After the command is run you will be presented with a list of items that already have newer versions downloaded.
You can pick ALL or select individual items to remove.


