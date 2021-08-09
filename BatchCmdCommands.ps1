New-Item -Path c:\flashplayeruninstall -itemtype Directory
$proxy=New-object System.Net.WebProxy
$webSession=new-object Microsoft.PowerShell.Commands.WebRequestSession
$webSession.Proxy=$proxy
Invoke-WebRequest -Uri https://fpdownload.macromedia.com/get/flashplayer/current/support/uninstall_flash_player.exe -OutFile c:\flashplayeruninstall\uninstall_flash_player.exe -WebSession $webSession -UseBasicParsing
$arguments = "-uninstall"
Start-Process c:\flashplayeruninstall\uninstall_flash_player.exe $arguments -NoNewWindow -Wait
Remove-Item -Path "c:\flashplayeruninstall" -Force  -Recurse -Confirm:$false