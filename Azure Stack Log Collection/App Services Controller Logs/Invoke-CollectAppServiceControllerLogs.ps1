$logDirectory = "C:\Temp\Logs"

if (!(Test-Path $logDirectory))
{
    New-Item -Path $logDirectory -ItemType Directory
}

[String]$CurrentDate=($((get-date).GetDateTimeFormats()[105])).replace(":","")
if (test-path -Path $logDirectory -PathType Any){
        Remove-Item -Path $logDirectory -Recurse -Force -Confirm:$false | Out-Null
    } 
New-Item -path $logDirectory -ItemType Directory -Force | out-null
Start-Transcript -path "$logDirectory\$($env:COMPUTERNAME)-AppRPLogCollection$($CurrentDate).txt"
$collectionScript = { 
    $node = $env:computername
    $nodename = $using:server
    $DataCollectionDir = "c:\temp\CSS_AppServiceLogs"
    #Remove CSS_AppServiceLogs directory if already exists
    if (test-path -Path $DataCollectionDir -PathType Any){
        Remove-Item -Path $DataCollectionDir -Recurse -Force -Confirm:$false | Out-Null
    }
 
    #Create CSS_AppServiceLogs directory 
    New-Item -path $DataCollectionDir -ItemType Directory -Force | out-null
    Start-Transcript -path "$DataCollectionDir\$($env:COMPUTERNAME)-AppRPLogCollection$($Using:CurrentDate).txt"
    Write-Host -ForegroundColor White "******************************************************************************************************"
    Write-Host -ForegroundColor White "                             Starting log collection on" $node "(" $($nodename.name) ")"
    Write-Host -ForegroundColor White "******************************************************************************************************"
 
    $sharename = "CSS"
 
    #Logs to collect
    $CollectGuestLogsPath = "C:\WindowsAzure\GuestAgent*\"
    $CollectGuestLogsPath2 = "C:\WindowsAzure\Packages\"
    $httplogdirectory = "C:\DWASFiles\Log\"
    $ftpLogDirectory = "C:\inetpub\logs\LogFiles\"
    $WebsitesInstalldir = "C:\WebsitesInstall\"
    $windowsEventLogdir = "C:\Windows\System32\winevt\Logs"
    $webPILogdir = "C:\Program Files\IIS\Microsoft Web farm framework\roles\resources\antareslogs"
    $packagesdir = "C:\Packages"
 
    #Create CSS share
    New-SmbShare -Name $sharename -Path $DataCollectionDir -FullAccess "$env:UserDomain\$env:UserName" | Out-Null   
 
    #Starting CollectGuestLogs
    Write-host "Collect Guest Logs (CollectGuestLogs.exe) started on" $node -ForegroundColor Green
    if (test-path -Path $CollectGuestLogsPath -PathType Any){
       start-process "$CollectGuestLogsPath\CollectGuestLogs.exe" -Verb runAs -WorkingDirectory $CollectGuestLogsPath -wait ;
        Move-Item $CollectGuestLogsPath\*.zip -Destination $DataCollectionDir\ -Force 
        Move-Item $CollectGuestLogsPath\*.zip.json -Destination $DataCollectionDir\ -Force
        Dir $DataCollectionDir\*.zip.json | rename-item -newname {  $_.name  -replace ".zip.json",".json"  }  
    }
    elseif(test-path -Path $CollectGuestLogsPath2 -PathType Any){
        start-process "$CollectGuestLogsPath2\CollectGuestLogs.exe" -Verb runAs -WorkingDirectory $CollectGuestLogsPath2 -wait ;
        Move-Item $CollectGuestLogsPath2\*.zip -Destination $DataCollectionDir\ -Force 
        Move-Item $CollectGuestLogsPath2\*.zip.json -Destination $DataCollectionDir\ -Force
        Dir $DataCollectionDir\*.zip.json | rename-item -newname {  $_.name  -replace ".zip.json",".json"  }
    }
 
    Write-host "Collect Guest Logs completed on" $node -ForegroundColor Green
 
    if ($node -notlike "CN*"){
        #Collecting IIS logs
        Write-host "Collect IIS logs $($httplogdirectory)started on" $node -ForegroundColor Yellow
        Copy-Item $httplogdirectory\ -Recurse -Destination $DataCollectionDir\HTTPLogs -Force 
        Write-host "Collect IIS logs completed on" $node -ForegroundColor Yellow
 
        #Collecting WFF logs
        Write-host "Collect WFF logs $($webPILogdir)started on" $node -ForegroundColor Green
        Copy-Item $webPILogdir\ -Recurse -Destination $DataCollectionDir\ 
        Write-host "Collect WFF logs completed on" $node -ForegroundColor Green  
    }
 
    #Collect FTP logs on Publisher servers
    if ($node -like "FTP*"){
        #Collecting FTP logs
        Write-host "Collect FTP logs $($ftpLogDirectory) started on" $node -ForegroundColor Yellow
        Copy-Item $ftpLogDirectory\ -Recurse -Destination $DataCollectionDir\FTPLogs -Force 
        Write-host "Collect FTP logs completed on" $node -ForegroundColor Yellow
    }
 
 
    #Collecting Event logs
    Write-host "Collect Event logs (WebSites logs) started on" $node -ForegroundColor Yellow
    Copy-Item $windowsEventLogdir\Microsoft-Windows-WebSites%4Administrative.evtx -Destination $DataCollectionDir\
    Copy-Item $windowsEventLogdir\Microsoft-Windows-WebSites%4Operational.evtx -Destination $DataCollectionDir\
    Copy-Item $windowsEventLogdir\Microsoft-Windows-WebSites%4Verbose.evtx -Destination $DataCollectionDir\ 
    Write-host "Collect Event logs completed on" $node -ForegroundColor Yellow
 
    #Collecting WebsitesInstall logs
    Write-host "Collect WebsitesInstall logs $($WebsitesInstalldir) started on" $node -ForegroundColor Green
    Copy-Item $WebsitesInstalldir\ -Recurse -Destination $DataCollectionDir\ 
    Write-host "Collect WebsitesInstall logs completed on" $node -ForegroundColor Green     
 
    #Collecting C:\Packages
    Write-host "Collect C:\Packages started on" $node -ForegroundColor Yellow
    Copy-Item $packagesdir\ -Recurse -Destination $DataCollectionDir\ 
    Write-host "Collect C:\Packages completed on" $node -ForegroundColor Yellow       
 
    write-host "Compressing Files" -ForegroundColor Green
    Stop-Transcript
    Compress-Archive -Path $DataCollectionDir\*  -DestinationPath $DataCollectionDir\$($nodename.name).$env:computername.zip -Force 
    Get-ChildItem -Path $DataCollectionDir\ -Recurse | Where-Object {$_.Name -notlike "*$($nodename.name).*"} | Remove-Item -Recurse -Force -Confirm:$false
}
 
$cleanupScript = { 
    Write-Host -ForegroundColor Yellow "Starting log cleanup on" $env:computername
    $DataCollectionDir = "c:\temp\CSS_AppServiceLogs"    
    $sharename = "CSS"       
 
    #Remove CSS share
    Get-SmbShare -name $sharename | Remove-SmbShare -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
 
    #Remove CSS_AppServiceLogs directory if already exists
    if (test-path -Path $DataCollectionDir -PathType Any){
        Remove-Item -Path $DataCollectionDir -Recurse -Force -Confirm:$false | Out-Null
    }       
 
}
 
$workerCred = Get-Credential -Message "Enter credentials for Worker Admin"
 
[int]$TimeOut=Read-Host "What do you want to set the timeout to in minutes? (Default 15 minutes)"
[int]$AppEvents=Read-Host "How many days of App RP Events do you want to capture? (Default 14 days)"
 
if($AppEvents -eq $null){
    write-host "Default timer will be set to 15 minutes"
    [int]$AppEvents=14
}
if($TimeOut -eq $null){
    write-host "Default timer will be set to 15 minutes"
    [int]$TimeOut=15
}
 
$Timer=($Timeout*60)/15
$RunningJobNames=$null
$roleServers = Get-AppServiceServer
$roleServers | select Name, Status, Role, CpuPercentage, MemoryPercentage, ServerState, PlatformVersion | ft > $logDirectory"\Get-AppServiceServer.txt"
$roleServers | ConvertTo-Json | Out-File $logDirectory"\AppServiceServer.json"
Get-AppServiceEvent -StartTime (get-date).adddays(-$AppEvents) | ConvertTo-Json | Out-File $logDirectory"\AppServiceEvent.json"
Get-AppServiceOperation -OperatorName ActiveController| ConvertTo-Json | Out-File $logDirectory"\AppServiceOperationActiveController.json"
Get-AppServiceOperation -OperatorName WFF| ConvertTo-Json | Out-File $logDirectory"\AppServiceOperationWFF.json"
 
#Log collection
foreach ($server in $roleServers) {
 
    if (test-netconnection $server.name -port 5985){
        if($server.role -eq "WebWorker")
        {
            Invoke-Command -ComputerName $($server.name) -ScriptBlock $collectionScript -Credential $workerCred -AsJob -JobName $CurrentDate-$($server.name) |out-null
        }
        else
                {
        Invoke-Command -ComputerName $($server.name) -ScriptBlock $collectionScript -AsJob -JobName $CurrentDate-$($server.name)|out-null
    }
        write-host "Starting data collection on $($server.role)-$($server.name)"
    }else {
        write-warning "Data collection on $($server.role)-$($server.name) cannot proceed as it is unavailable to TCP Port 5985"
    }
}
#Log collection wait
do{
    $AllJobs=get-job -Name $CurrentDate*
    $JobsCompleted=$AllJobs | ? state -like Completed
    $JobsRunning=$AllJobs | ? state -like Running
    write-host "$((get-date).GetDateTimeFormats()[94]) - Sleeping for 15 seconds until data collection job completion - ($($JobsCompleted.count) of $($AllJobs.count))"
    $Timer--
    write-host "Timeout will occur in $($Timer*15) seconds"
    Start-Sleep -Seconds 15
}
Until(($($JobsCompleted.count) -eq $($AllJobs.count)) -or ($timer -eq 1))
 
if (!($($JobsCompleted.count) -eq $($AllJobs.count)) -and ($timer -eq 0)){
    $RunningJobNames=$($JobsRunning.name)|%{$($_.replace($CurrentDate,"")).trimstart("-")}
    Write-Warning "Timeout expired.  Jobs did not complete on following servers:"
    Write-Warning "$RunningJobNames"
    Write-Warning "Please capture the logs off manually on these VMs (each VM will have logs under C:\temp)"
}else {
    Write-host "Log collection completed.  Working on copying data off to $logDirectory"
}
 
 
[String]$CopyDataDate=($((get-date).GetDateTimeFormats()[105])).replace(":","")
#Log copying
foreach ($server in $roleServers) {
    if($RunningJobNames -notcontains $server.name){
        if($Server.Role -eq "WebWorker"){
            Start-Job {
                $workerSession = New-PSSession -Credential $using:workerCred -ComputerName $($using:server.name)
                Copy-Item -FromSession $workerSession -Path c:\temp\CSS_AppServiceLogs\*.zip -Destination $using:logDirectory
                Remove-PSSession $workerSession
            } -Name $CopyDataDate-$($server.name) |out-null
        }
        else{
            Start-Job {Copy-Item \\$($using:server.name)\CSS\* -Destination $using:logDirectory} -Name $CopyDataDate-$($server.name) |out-null
        }
    }
    else{
        Write-Warning "Please manually collect the logs off of $($server.name) off of its C:\temp folder and clean-up as the data collection job did not complete within the timeout window"
    }
}
#Log copying wait
do{
    $AllJobs=get-job -Name $CopyDataDate*
    $CopyJobsCompleted=$AllJobs | ? {$_.state -like "Completed" -or $_.state -like "Failed"}
    $CopyJobsRunning=$AllJobs | ? state -like Running
    write-host "$((get-date).GetDateTimeFormats()[94]) - Sleeping for 15 seconds until data move job completion - ($($CopyJobsCompleted.count) of $($AllJobs.count))"
    write-host "Waiting 15 seconds"
    Start-Sleep -Seconds 15
}
Until(($($CopyJobsCompleted.count) -eq $($AllJobs.count)))
 
 
#Log cleanup
foreach ($server in $roleServers) {
    if($RunningJobNames -notcontains $server.name){
        if($Server.Role -eq "WebWorker"){
            $workerSession = New-PSSession -Credential $workerCred -ComputerName $($server.name)
            Invoke-Command -Session $workerSession -ScriptBlock $cleanupScript
            Remove-PSSession $workerSession
        }
        else{
            Invoke-Command -ComputerName $($server.name) -ScriptBlock $cleanupScript
        }
    }
    else{
        Write-Warning "Please manually collect the logs off of $($server.name) off of its C:\temp folder and clean-up as the data collection job did not complete within the timeout window"
    }
}
 
write-host "Cleaning up job info"
$JobsCompleted,$CopyJobsCompleted|remove-job
Stop-Transcript