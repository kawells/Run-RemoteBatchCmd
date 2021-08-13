$domain =           "mydomain.com" # Name of domain containing computers, used to temporarily add as trusted host for PSSession
$remoteDir =        "c:\remoteDir" # Writeable remote directory full path where files will be temporarily uploaded
$localDataFolder =  "RemoteBatchCmd" # Name of writeable local directory where reports/logs/files will be saved and/or uploaded from
$localDataPath =    [Environment]::GetFolderPath("MyDocuments") + "\" + $localDataFolder # Full local path in MyDocuments
