# Run-RemoteBatchCmd
A PowerShell script that will upload files to and run batch scripts/commands on remote PCs, then generate a success/fail report.

## Requirements
* **PS Remoting must be enabled on the remote computers.**
* **Update $domain variable** - Add your organization's domain to the $domain variable in Run-RemoteBatchCmd.ps1
* **Update $remoteDir variable** - If uploading files to a remote directory, add the directory path to the $remoteDir variable in Run-RemoteBatchCmd.ps1
* **BatchCmdCompList.txt** - This is a list of computers on which the commands will be run
* **BatchCmdCommands.ps1** - This is the script/commands that will run on each computer
 
## Summary
This script iterates through a list of computers, uploading files if necessary, and runs commands defined in **BatchCmdCommands.ps1** on each computer.

When connecting to a remote computer, this script will first test the connection to make sure the computer is reachable. It will then attempt to start the remote WinRM service, start a PSSession with the remote computer, then upload any file(s) specified by the user. If all of these are successful, it will run all commands defined in *BatchCmdCommands.ps1*. If all commands complete successfully, the computer will be marked successful in *BatchCmd-Report.csv*. If any of the commands return an error, the error is logged to *BatchCmd-Results.csv*. Any uploaded files are deleted upon completion of the commands, then the PSSession is closed and the next computer is processed.

Upon each subsequent run of this script, *BatchCmd-Report.csv* is reimported and only computers that were previously failed will be attempted again. Errors are appended to *BatchCmd-Results.csv*.

When using a new set of computers, you must update *BatchCmdCompList.txt* and delete *BatchCmd-Report.csv*.

When using a new set of commands, you must update *BatchCmdCommands.ps1* and delete *BatchCmd-Report.csv*.
