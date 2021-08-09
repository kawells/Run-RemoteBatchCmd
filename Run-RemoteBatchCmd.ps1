<#
.NAME
    Active Directory Tools
.SYNOPSIS
    This script will run all PowerShell commands that you define in BatchCmdCommands.ps1 on all computers
    that you define in batchcmdcomputerlist.txt. It will generate a report.csv, which  is used to track the
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
.LINK
    github.com/kawells
#>

Set-ExecutionPolicy -ExecutionPolicy bypass -Scope Process

# Get timestamp for error logs
function Get-TimeStamp { return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date) }

# Declare vars
$domain = "yourdomain" # Name of domain containing computers, used to temporarily add as trusted host for PSSession
$computerList = "batchcmdcomputerlist.txt" # Name of text file with computer list, names only. IP addresses do not work
$commandList = "BatchCmdCommands.ps1" # Name of ps1 file with cmd list
$logFileName = "batchcmdresults.csv" # Name of csv log
$reportFileName = "report.csv" # Name of report file
$computerListPath = "$PSScriptRoot\$computerList" 
$commandListPath = "$PSScriptRoot\$commandList"
$logFilePath = "$PSScriptRoot\$logFileName"
$reportFilePath = "$PSScriptRoot\$reportFileName"
$command = $null # Stores the most recent command
$computer = $null # Stores the most recent remote computer
$result = $null # Stores the results of the most recent command
$errorLog = $null # Stores the entire script errors
$report = $null # Stores the master report
$cmdError = $null # Stores last command error

# Allow TLS if running Invoke-WebRequest or Invoke-RestMethod
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor
[Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Create a new report or import the previous report
try {
    if(!(Test-Path -Path $reportFilePath -PathType Leaf)) {
        New-Item $reportFilePath -ItemType File
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
        catch { Write-Host "Error: Getting computer list failed. Check that file exists."; Exit }
    }
    else {
        Write-Host "Importing results of previous report..."
        $report = (Import-Csv -Path $reportFilePath -ErrorAction Stop)
        Write-Host "Imported results from $reportFilePath."
    }
}
catch {
    Write-Host "Error updating report. Check that report file is not currently open."
}


# Import command list separated by line or exit
try {
    Write-Host "Getting command list..."
    $commandList = (Get-Content $commandListPath -ErrorAction Stop)
    Write-Host "Getting command list successful."
}
catch { Write-Host "Error: Getting command list failed. Check that file exists."; Exit }

# Start local WinRM service or exit
try {
    Write-Host "Starting local WinRM service..."
    Set-Service -Name WinRM -StartupType Manual -Status Running -ErrorAction Stop
    Write-Host "Starting local WinRM service successful."
}
catch { Write-Host "Error: Starting local WinRM service failed."; Exit }

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
catch { Write-Host "Error: Adding domain to trusted hosts failed."; Exit }

# Run all commands on all computers in list
Write-Host "Running commands on remote computers...`n"
foreach ($computer in (($report | Where-Object { $_.Status -eq "Fail" } ).ComputerName)) {
    $cmdError = $null
    if(Test-Connection "$computer.$domain" -ErrorAction SilentlyContinue -ErrorVariable cmdError){ # Only proceed if computer is remotely accessible
        # Try to start WinRM on remote computer or move on to next computer
        try { 
            Write-Host "Starting WinRM service on $computer..."
            Set-Service -Name WinRM -ComputerName "$computer.$domain" -StartupType Manual -Status Running -ErrorAction Stop -ErrorVariable cmdError
            # Try to create PS Session on remote computer and run commands, then close session
            try {
                Write-Host "Starting PSSession on $computer..."
                $session = New-PSSession -ComputerName "$computer.$domain" -ErrorAction Stop -ErrorVariable cmdError
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
                        $result # To suppress result output, comment out this line
                    }
                    catch {
                        Write-Host "Error: unable to run `"$command`" on $computer. See log for details."
                        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command=$command;Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if Command fails
                    }
                }
                Remove-PSSession -session $session
            }
            catch {
                Write-Host "Error: Unable to start PSSession on $computer."
                if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="PSSession";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if PSSession fails
                ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
                ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
            }
        }
        catch {
            Write-Host "Error: Unable to start WinRM service on $computer."
            if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="WinRM";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if WinRM fails
            ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
            ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
        }
        # Revert trusted hosts to before script ran
        if ($curTrustedHosts) { Set-Item WSMan:\localhost\Client\TrustedHosts $curTrustedHosts -Force}
        else { Clear-Item WSMan:\localhost\Client\TrustedHosts -Force}
    }
    else {
        Write-Host "Error: $computer is not reachable."
        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="Ping";Error=$($cmdError);Time=$(Get-TimeStamp)} ) }
    }
    # Updating report with Success/Fail
    if (!($errorLog | Where-Object { $_.ComputerName -eq $computer } | Where-Object { $_.Error -ne "Success" } )) {
        ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Success"
        ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
    }
    else { 
        ($report | Where-Object { $_.ComputerName -eq $computer }).Status = "Fail"
        ($report | Where-Object { $_.ComputerName -eq $computer }).Time = $(Get-TimeStamp)
    }
}

# Save error log
try {
    if(!(Test-Path -Path $logFilePath -PathType Leaf)) {
        New-Item $logFilePath -ItemType File
        $errorLog | Export-Csv -Path $logFilePath -NoTypeInformation
        Write-Host "`nCreated new error log at $logFilePath."
    }
    else {
        $errorLog | Export-CSV -Path $logFilePath -Append
        Write-Host "`nAdded to existing error log at $logFilePath."
    }
}
catch {
    Write-Host "Error writing log. Check that log file is not currently open."
}

# Save report
try {
    $report | Export-CSV -Path $reportFilePath -NoTypeInformation
    Write-Host "`nUpdated report at $reportFilePath."
}
catch {
    Write-Host "Error updating report. Check that report file is not currently open."
}
