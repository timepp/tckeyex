taskkill /F /IM totalcmd.exe
taskkill /F /IM totalcmd64.exe
calldll kernel32.dll Sleep int:1000 >nul
mkdir c:\cloud\soft\TC\plugins\wdx\tckeyex
copy debug\tckeyex.wdx c:\cloud\soft\TC\plugins\wdx\tckeyex\tckeyex.wdx
copy debug\tckeyex.wdx64 c:\cloud\soft\TC\plugins\wdx\tckeyex\tckeyex.wdx64
copy tckeyex.ini c:\cloud\soft\TC\plugins\wdx\tckeyex\tckeyex.ini
