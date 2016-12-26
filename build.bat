@echo off

call makeversion.bat

mkdir debug 2>nul
mkdir release 2>nul

dub build 
move /y tckeyex.dll debug\tckeyex.wdx

dub build -a x86_64
move /y tckeyex.dll debug\tckeyex.wdx64

dub build -b release
move /y tckeyex.dll release\tckeyex.wdx

dub build -b release -a x86_64
move /y tckeyex.dll release\tckeyex.wdx64
