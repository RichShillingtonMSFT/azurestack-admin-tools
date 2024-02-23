$UpdateDownloadPath = 'C:\2311update'

Function Test-UpdateHash
{
    [CmdletBinding()]
    Param
    (
        [String]$UpdateDownloadPath
    )
    
    $UpdateFiles = Get-ChildItem -Path $UpdateDownloadPath
    $XMLFile = ($UpdateFiles | Where-Object {$_.FullName -like "*.xml"}).FullName
    $ZipFiles = $UpdateFiles | Where-Object {$_.FullName -like "*.zip"}
    [xml]$HashList = Get-Content $XMLFile

    foreach ($ZipFile in $ZipFiles)
    {
        Write-Host "Checking Update File $($ZipFile.Name)" -ForegroundColor Cyan

        if ($($HashList.UpdatePackageManifest.UpdateInfo.PackageHash) -contains $((Get-FileHash $ZipFile.Fullname).Hash))
        {
            Write-Host "Update File $($ZipFile.Name) is valid" -ForegroundColor Green
        }
        else
        {
            Write-Host "Update File $($ZipFile.Name) is NOT valid" -ForegroundColor Red
        }
    }
}

Test-UpdateHash -UpdateDownloadPath $UpdateDownloadPath