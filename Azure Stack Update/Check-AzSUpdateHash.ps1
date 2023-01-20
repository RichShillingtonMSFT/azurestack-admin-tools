
$UpdatePath = 'C:\Updates\AzS_Update_1.2102.31.152.zip'
$XMLPath = 'C:\Updates\metadata.xml'
Function Test-UpdateHash
{
    [CmdletBinding()]
    Param
    (
    [String]$UpdatePath,
    [String]$XMLPath
    )
    
    [xml]$Hash = Get-Content $XMLPath
    $UpdateHash = (Get-FileHash $UpdatePath).Hash

    If ($UpdateHash -eq $($Hash.UpdatePackageManifest.UpdateInfo.PackageHash))
    {
        Write-Host "You're good to go!" -ForegroundColor Green
    }
    else
    {
        Write-Host "Your update is busted!" -ForegroundColor Red
    }
}

Test-UpdateHash -UpdatePath $UpdatePath -XMLPath $XMLPath