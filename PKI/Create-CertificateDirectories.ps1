# Deployment Folders
$Destination = 'C:\Certificates\Deployment'
New-Item 'C:\Certificates\Deployment' -ItemType Directory
$Directories = 'ACSBlob', 'ACSQueue', 'ACSTable', 'Admin Extension Host', 'Admin Portal', 'ARM Admin', 'ARM Public', 'KeyVault', 'KeyVaultInternal', 'Public Extension Host', 'Public Portal'
$Directories | ForEach-Object { New-Item -Path (Join-Path $Destination $PSITEM) -ItemType Directory -Force}

# App Service Folders
$AppServicesDirectory = 'C:\Certificates\AppServices'
New-Item $AppServicesDirectory -ItemType Directory
$AppServiceSubDirectories = 'DefaultDomain', 'Identity', 'API', 'Publishing'
$AppServiceSubDirectories | ForEach-Object { New-Item -Path (Join-Path $AppServicesDirectory $PSITEM) -ItemType Directory -Force}

# Other Folders
$OtherFoldersDirectory = 'C:\Certificates\'
$OtherFolders = 'DBAdapter','EventHubs','IoTHub'
$OtherFolders | ForEach-Object { New-Item -Path (Join-Path $OtherFoldersDirectory $PSITEM) -ItemType Directory -Force}
