:: generate version_.d which define a version string with the help of git

@echo Generating version file...
@set GITVER=unknown
@for /f %%i in ('git describe --long --all --dirty') do @set GITVER=%%i
@echo module version_; > source\version_.d
@echo enum appVersion = "%GITVER%"; >> source\version_.d
