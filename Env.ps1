$domain =           "domain" # Name of domain containing computers, used to temporarily add as trusted host for PSSession
$remoteDir =        "remoteDir" # Writeable remote directory where files will be temporarily uploaded
$localDataFolder =  "\RemoteBatchCmd" # Name of writeable local directory where reports/logs/files will be saved and/or uploaded from
$localDataPath =    [Environment]::GetFolderPath("MyDocuments") + "\RemoteBatchCmd" # Full local path
