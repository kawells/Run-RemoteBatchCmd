# Run-RemoteBatchCmd
A PowerShell script that will run batch scripts/commands on remote PCs and generate a report of success/fail.

## Requirements
* Add your organization's **domain** to the $domain variable in Run-RemoteBatchCmd.ps1
* If uploading files to a remote directory, add the **directory path** to the $remoteDir variable in Run-RemoteBatchCmd.ps1
* PS Remoting must be enabled on the remote computers.
* **BatchCmdCompList.txt** - This is a list of computers on which the commands will be run
* **BatchCmdCommands.ps1** - This is the script/commands that will run on each computer
 
## Summary
This script will first generate a *BatchCmd-Report.csv* that is used to track the status of running the commands on each computer. Upon each run, it will update the report with (Success/Fail) and current time depending on whether any of the commands returned an error. It also logs any errors to *BatchCmd-Results.csv*.
