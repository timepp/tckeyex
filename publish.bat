copy /y release\* publish
del tckeyex.zip
powershell.exe -nologo -noprofile -command "& { Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::CreateFromDirectory('publish', 'tckeyex.zip'); }"

