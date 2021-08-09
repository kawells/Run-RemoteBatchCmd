Set-ExecutionPolicy -ExecutionPolicy bypass -Scope Process

# Get timestamp for error logs
function Get-TimeStamp { return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date) }

# Declare vars
$domain = "win.nara.gov" # Name of domain containing computers, used to temporarily add as trusted host for PSSession
$computerList = "batchcmdcomputerlist.txt" # Name of text file with computer list, names only. IP addresses do not work
$commandList = "batchcmdcommands.txt" # Name of text file with cmd list
$logFileName = "batchcmdresults.csv" # Name of csv log
$logFilePath = $PSScriptRoot + "\" + $logFileName
$computerListPath = $PSScriptRoot + '\' + $computerList 
$commandListPath = $PSScriptRoot + '\' + $commandList
$command = $null # Stores the most recent command
$computer = $null # Stores the most recent remote computer
$result = $null # Stores the results of the most recent command
$errorLog = $null # Stores the entire script errors
$cmdError = $null # Stores last command error


# Import computer list separated by line or exit
try {
    Write-Host "Getting computer list..."
    $computerList = (Get-Content $computerListPath -ErrorAction Stop)
    Write-Host "Getting computer list successful." 
}
catch { Write-Host "Error: Getting computer list failed. Check that file exists."; Exit }

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
$newTrustedHost = "*.$domain"
$curTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).value
if ($curTrustedHosts) {
    $newTrustedHosts = "$curTrustedHosts, $newTrustedHost" 
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newTrustedHosts }
else { Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$newTrustedHost" }

# Run all commands on all computers in list
Write-Host "Running commands on remote computers...`n"
foreach ($computer in $computerList) {
    if(Test-Connection $computer -ErrorAction SilentlyContinue -ErrorVariable cmdError){ # Only proceed if computer is remotely accessible
        # Add computer to trusted hosts
        NARA-B05826
        # Try to start WinRM on remote computer or move on to next computer
        try { 
            Write-Host "Starting WinRM service on $computer..."
            Set-Service -Name WinRM -ComputerName $computer -StartupType Manual -Status Running -ErrorAction Stop -ErrorVariable cmdError
            # Try to create PS Session on remote computer and run commands, then close session
            try {
                Write-Host "Starting PSSession on $computer..."
                $session = New-PSSession -ComputerName $computer -ErrorAction Stop -ErrorVariable cmdError
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
                        Write-Host "Successfully ran command `"$command`" on $computer." # To suppress result output, comment out this line
                        # $result # To suppress result output, comment out this line
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
            }
        }
        catch {
            Write-Host "Error: Unable to start WinRM service on $computer."
            if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="WinRM";Error=$($cmdError);Time=$(Get-TimeStamp)} ) } # Write to log if WinRM fails
        }
        # Revert trusted hosts to before script ran
        if ($curTrustedHosts) { Set-Item WSMan:\localhost\Client\TrustedHosts $curTrustedHosts }
        else { Clear-Item WSMan:\localhost\Client\TrustedHosts }
    }
    else {
        Write-Host "Error: $computer is not reachable."
        if ($cmdError) { $errorLog += @( [pscustomobject]@{ComputerName=$computer;Command="Ping";Error=$($cmdError);Time=$(Get-TimeStamp)} ) }
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
    Write-Host "Error writing log."
}