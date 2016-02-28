@echo off

call makeversion.bat

dub build -b release
copy /y tckeyex.dll tckeyex.wdx

dub build -b release -a x86_64
copy /y tckeyex.dll tckeyex.wdx64