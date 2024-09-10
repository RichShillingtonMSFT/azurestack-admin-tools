
$DownloadLocation = 'C:\ASDK2301'

if (!(Test-Path $DownloadLocation))
{
    New-Item -Path $DownloadLocation -ItemType Directory
}

$URIS = @(
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit.exe'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-1.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-10.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-11.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-12.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-13.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-14.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-15.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-16.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-17.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-18.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-19.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-20.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-21.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-2.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-3.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-4.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-5.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-6.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-7.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-8.bin'
'https://azurestackhub.azureedge.net/PR/download/ASDK_1.2301.0.14/AzureStackDevelopmentKit-9.bin'
)

foreach ($URI in $URIS)
{
    $FileName = $URI.Split('/') | Select-Object -Last 1
    Invoke-WebRequest -Uri $URI -UseBasicParsing -OutFile $DownloadLocation\$FileName
}
