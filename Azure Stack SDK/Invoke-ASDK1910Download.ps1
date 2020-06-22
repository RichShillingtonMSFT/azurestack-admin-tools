$DownloadLocation = 'C:\ASDK1910'

if (!(Test-Path $DownloadLocation))
{
    New-Item -Path $DownloadLocation -ItemType Directory
}

$URIS = @(
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit.exe'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-1.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-2.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-3.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-4.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-5.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-6.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-7.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-8.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-9.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-10.bin'
'https://azurestack.azureedge.net/asdk1910-58/AzureStackDevelopmentKit-11.bin'
)

foreach ($URI in $URIS)
{
    $FileName = $URI.Split('/') | Select-Object -Last 1
    Invoke-WebRequest -Uri $URI -UseBasicParsing -OutFile $DownloadLocation\$FileName
}