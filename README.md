# Run-RemoteBatchCmd
A PowerShell script that will run batch scripts/commands on remote PCs and generate a report of success/fail.

Note that you must supply the following:
  batchcmdcomputerlist.txt # This is a list of computers on which the commands will be run
  BatchCmdCommands.ps1 # This is the script/commands that will run on each computer
  
This script will first generate a report.csv that is used to track the status of running the commands on each computer.
Upon each run, it will update the report with (Success/Fail) and current time depending on whether any of the commands returned an error.
