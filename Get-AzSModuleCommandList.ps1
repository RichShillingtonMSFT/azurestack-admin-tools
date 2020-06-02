$Modules = Get-Module -ListAvailable | Where-Object {$_.Name -like "AzS.*"}

$CommandList = @()

foreach ($Module in $Modules)
{
    $CommandList += (Get-Command -Module $Module.Name).Name
}

$CommandList | Sort-Object