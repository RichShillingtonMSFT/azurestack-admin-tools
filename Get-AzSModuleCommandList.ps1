$Modules = Get-Module -ListAvailable | Where-Object {$_.Name -like "AzS.*"}

$CommandList = @()

foreach ($Module in $Modules)
{
    $Commands = Get-Command -Module $Module.Name
    foreach ($Command in  $Commands)
    {
        $CommandList += New-Object PSObject -Property (@{Command=$($Command.Name);Module=$($Module.Name)})
    }
}

$CommandList | Sort-Object -Property Command