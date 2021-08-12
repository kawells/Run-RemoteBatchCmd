<#
.NAME
    Run-RemoteBatchCmd
.SYNOPSIS
    This script will run all PowerShell commands that you define in BatchCmdCommands.ps1 on all computers
    that you define in batchcmdcomputerlist.txt. It will generate a report.csv, which is used to track the
    success/failure on each computer. Success is defined as all commands were processed without any errors.
    Failure is defined as any command on one computer returned an error.
    
    On subsequent runs of this script, if the report.csv is still present, it will load the failed computers and
    attempt to run the PowerShell commands on those computers again, then update the report with the current
    status. It also logs all errors to batchcmdresults.csv, and will append to this log on subsequent runs
    of this script.
.NOTES
    Author: Kevin Wells
    Script must be run as domain user with admin rights.
    Remote computers must be configured to support PowerShell remoting.
    All related files must be placed in the same folder as this script.
    Change the $domain variable below to match the domain of your organization.
    1.0 | 09/09/2021 | Kevin Wells
        Initial Version
    1.1 | 09/12/2021 | Kevin Wells
        Added option to upload file(s) to remote computers
        Fixed divide by zero bug
.LINK
    github.com/kawells
#>

Set-ExecutionPolicy -ExecutionPolicy bypass -Scope Process

## Declaring functions
# Get timestamp for error logs
function Get-TimeStamp { return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date) }

# Get filenames to upload from user
function Get-FileNames {
    $selection = $null # Stores selection in CLI menu
    $fileName = $null
    $fileNames = $null # Stores filenames for upload
    $fileNames = @()
    while ($selection -ne "n") {
        # If user has entered filenames, list them
        if ($fileNames -ne $null) { 
            foreach ($filename in $fileNames) { Write-Host "File $filename will be uploaded to remote computers." }
            $selection = Read-Host "`nDo you need to upload any more files to the remote computers? [y/n]"
        }
        # If user has not entered filenames, prompt until user exits menu with 'n'
        else { $selection = Read-Host "`nDo you need to upload any files to the remote computers? [y/n]" }
        switch ($selection) {
            'y'{
                Write-Host "File should be located in the same folder as the script."
                $tempFileName = Read-Host "Enter the file name (no path included)"
                # If file exists and is not already in list, add to fileNames
                if ((Test-Path -Path $PSScriptRoot\$tempFileName -PathType Leaf) -And ($tempFileName -NotIn $fileNames)) { $fileNames += $tempFileName }
                else { Write-Warning "File could not be located. Ensure that file name is correct and the file is located in the same folder as the script." }
            }
            'n'{ break }
            default{ Write-Warning "Invalid selection." }
        }
    }
    return $fileNames
}

## Declare vars
# Environment-specific vars
$domain =           "domain" # Name of domain containing computers, used to temporarily add as trusted host for PSSession
$remoteDir =        "remoteDir" # Writeable remote directory where files will be temporarily uploaded
# Other vars
$computerList =     "BatchCmdCompList.txt" # Name of text file with computer list, names only. IP addresses do not work
$commandList =      "BatchCmdCommands.ps1" # Name of ps1 file with cmd list
$logFileName =      "BatchCmd-Results.csv" # Name of csv log
$reportFileName =   "BatchCmd-Report.csv" # Name of report file
$computerListPath = "$PSScriptRoot\$computerList" 
$commandListPath =  "$PSScriptRoot\$commandList"
$logFilePath =      "$PSScriptRoot\$logFileName"
$reportFilePath =   "$PSScriptRoot\$reportFileName"
$fileNames =        Get-FileNames # Stores file names for upload
$command =          $null # Stores the most recent command
$computer =         $null # Stores the most recent remote computer
$result =           $null # Stores the results of the most recent command
$errorLog =         $null # Stores the entire script errors
$report =           $null # Stores the master report
$cmdError =         $null # Stores last command error

# Allow TLS if running Invoke-WebRequest or Invoke-RestMethod
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor
[Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Create a new report or import the previous report
try {
    if(!(Test-Path -Path $reportFilePath -PathType Leaf)) {
        $report = @()
        $report | Export-Csv -Path $reportFilePath -NoTypeInformation
        Write-Host "`nCreated new report at $reportFilePath."
        # Import computer list separated by line or exit
        try {
            Write-Host "Getting computer list..."
            $computerList = (Get-Content $computerListPath -ErrorAction Stop)
            Write-Host "Getting computer list successful."
            foreach ($computer in $computerList) { $report += @( [pscustomobject]@{ComputerName=$computer;Status="Fail";Time=$null} ) }
        }
        catch { Write-Error "Getting computer list failed. Check that file exists. Exiting."; Exit }
    }
    else {
        Write-Host "Importing results of previous report..."
        $report = (Import-Csv -Path $reportFilePath -ErrorAction Stop)
        Write-Host "Imported results from $reportFilePath."
    }
}
catch { Write-Error "Unable to import report. Check that report file is not currently open. Exiting."; Exit }

# Test to see if there are any computers that are still failed
if (!($report | Where-Object { $_.Status -eq "Fail" })) { Write-Host "`nAll computers in the report are successful. No further work necessary."; Exit }

# Import command list separated by line or exit
try {
    Write-Host "Getting command list..."
    $commandList = (Get-Content $commandListPath -ErrorAction Stop)
    Write-Host "Getting command list successful."
}
catch { Write-Error "Getting command list failed. Check that file exists. Exiting."; Exit }

# Start local WinRM service or exit
try {
    Write-Host "Starting local WinRM service..."
    Set-Service -Name WinRM -StartupType Manual -Status Running -ErrorAction Stop
    Write-Host "Starting local WinRM service successful."
}
catch { Write-Error "Starting local WinRM service failed."; Exit }

# Adding domain to trusted hosts list or creating new entry if list does not already exist
Write-Host "Adding domain to trusted hosts..."
try {
    $newTrustedHost = "*.$domain"
    $curTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).value
    if ($curTrustedHosts) {
        $newTrustedHosts = "$curTrustedHosts, $newTrustedHost" 
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newTrustedHosts -Force -ErrorAction Stop
    }
    else { Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$newTrustedHost" -Force -ErrorAction Stop}
    Write-Host "Adding domain to trusted hosts successful."
}
catch { Write-Error "Adding domain to trusted hosts failed. Exiting."; Exit }

# Run all commands on all computers in list
Write-Host "Running commands on remote computers...`n"
$i = 0 # Set progress counter
foreach ($computer in (($report | Where-Object { $_.Status -eq "Fail" } ).ComputerName)) {
    # Display progress bar if computers are gt 1
    if (($report | Where-Object { $_.Status -eq "Fail" } ).Count) {
        $perct = ($i / (($report | Where-Object { $_.Status -eq "Fail" } ).Count)) * 100
        Write-Progress -Activity "Total Progress..." -Status "Running commands on computer: $computer" -PercentComplete $perct
    }
    # Only record errors for current computer
    $cmdError = $null
    # Only proceed if computer is remotely accessible
    if(Test-Connection "$computer.$domain" -ErrorAction SilentlyContinue -ErrorVariable cmdError){
        # Try to start WinRM on remote computer or move on to next computer
        try { 
            Write-Host "Starting WinRM service on $computer..."
            Set-Service -Name WinRM -ComputerName "$computer.$domain" -StartupType Manual -Status Running -ErrorAction Stop -ErrorVariable cmdError
            # Try to create PS Session on remote computer and run commands, then close session
            try {
                Write-Host "Starting PSSession on $computer..."
                $session = New-PSSession -ComputerName "$computer.$domain" -ErrorAction Stop -ErrorVariable cmdError
                # Upload file(s) to remote computer
                if ($fileNames) {
                    try {
                        foreach ($filename in $fileNames){
                            Write-Host "Uploading $fileName to $computer..."
                            Copy-Item "$PSScriptRoot\$fileName" –Destination "$remoteDir\$fileName" –ToSession $session -ErrorAction Stop -ErrorVariable cmdError
                            Write-Host "Uploading $fileName to $computer successful."
                        }
                        
                    }
                    catch {
                        Write-Warning "Uploading $fileName to $computer failed. See log for details."
                        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="Upload $fileName";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if upload fails
                    }
                }
                # Run each command
                foreach ($command in $commandList) {
                    try {
                        $parameters = @{
                            Session = $session
                            ScriptBlock = [Scriptblock]::Create($command)
                            ErrorAction = "Stop"
                            ErrorVariable = "cmdError"
                        }
                        $result = ( Invoke-Command @parameters | Format-Table -AutoSize )
                        $cmdError = "Success"
                        $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command=$command;Error=$($cmdError);Time=$(Get-TimeStamp) } ) # Write to overall log
                        Write-Host "Successfully ran command `"$command`" on $computer."
                        #$result # To suppress result output, comment out this line
                    }
                    catch {
                        Write-Warning "Unable to run `"$command`" on $computer. See log for details."
                        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command=$command;Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if Command fails
                    }
                }
                # Cleanup transferred files 
                if ($fileNames) {
                    try {
                        foreach ($fileName in $fileNames) {
                            Write-Host "Deleting $fileName on $computer..."
                            $removePath = "$remoteDir\$fileName"
                            Invoke-Command -Session $session { Remove-Item $Using:removePath -Force -Confirm:$false -ErrorAction Stop -ErrorVariable cmdError }
                            Write-Host "Deleting $fileName on $computer successful."
                        }
                    }
                    catch {
                        Write-Warning "Deleting $fileName on $computer failed. See log for details."
                        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="Delete $fileName";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if delete fails
                    }
                }
                Remove-PSSession -session $session
            }
            catch {
                Write-Warning "Unable to start PSSession on $computer."
                if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="PSSession";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if PSSession fails
                ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
                ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
            }
        }
        catch {
            Write-Warning "Unable to start WinRM service on $computer."
            if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="WinRM";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if WinRM fails
            ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
            ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
        }
        # Revert trusted hosts to before script ran
        if ($curTrustedHosts) { Set-Item WSMan:\localhost\Client\TrustedHosts $curTrustedHosts -Force}
        else { Clear-Item WSMan:\localhost\Client\TrustedHosts -Force}
    }
    else {
        Write-Warning "$computer is not reachable."
        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="Ping";Error=$($cmdError);Time=$(Get-TimeStamp)} ) }
    }
    # Updating report with Success/Fail
    if (!($errorLog | Where-Object { $_.ComputerName -eq $computer } | Where-Object { $_.Error -ne "Success" } )) {
        Write-Host "All commands run on $computer were successful.`n"
        ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Success"
        ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
    }
    else {
        ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
        ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
    }
    $i++
}

# Save error log
try {
    if(!(Test-Path -Path $logFilePath -PathType Leaf)) {
        $errorLog | Export-Csv -Path $logFilePath -NoTypeInformation
        Write-Host "Created new error log at $logFilePath."
    }
    else {
        $errorLog | Export-CSV -Path $logFilePath -Append
        Write-Host "Added to existing error log at $logFilePath."
    }
}
catch { Write-Error "Saving error log failed. Check that error log file is not currently open." }

# Save report
try {
    $report | Export-CSV -Path $reportFilePath -NoTypeInformation
    Write-Host "Updated report at $reportFilePath."
}
catch { Write-Error "Updating report failed. Check that report file is not currently open." }
