$DownloadLocation = 'C:\ASDK2102'

if (!(Test-Path $DownloadLocation))
{
    New-Item -Path $DownloadLocation -ItemType Directory
}

$URIS = @(
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit.exe'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-1.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-10.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-11.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-12.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-13.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-2.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-3.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-4.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-5.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-6.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-7.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-8.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2102.0.9/AzureStackDevelopmentKit-9.bin'
)

foreach ($URI in $URIS)
{
    $FileName = $URI.Split('/') | Select-Object -Last 1
    Invoke-WebRequest -Uri $URI -UseBasicParsing -OutFile $DownloadLocation\$FileName
}