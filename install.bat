dub build
taskkill /F /IM totalcmd.exe
calldll kernel32.dll Sleep int:1000 >nul
mkdir c:\cloud\soft\TC\plugins\wdx\tckeyex
copy tckeyex.dll c:\cloud\soft\TC\plugins\wdx\tckeyex\tckeyex.wdx
