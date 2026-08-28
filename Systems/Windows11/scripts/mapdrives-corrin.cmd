@echo off
setlocal EnableExtensions

set "SERVER=caladan"
set "USER=caladan\corrin-user"

REM Clear existing mapped drives
net use W: /delete /y >nul 2>&1
net use Y: /delete /y >nul 2>&1
net use Z: /delete /y >nul 2>&1

REM Clear all existing sessions to caladan, including IPC$
net use \\%SERVER%\IPC$ /delete /y >nul 2>&1
net use \\%SERVER%\* /delete /y >nul 2>&1

REM Force Windows to use the stored Credential Manager password for caladan\rich
net use \\%SERVER%\IPC$ /user:%USER%
if errorlevel 1 (
  echo Failed to authenticate to \\%SERVER% as %USER%.
  echo Make sure Credential Manager has an entry for %SERVER% using %USER%.
  pause
  exit /b 1
)

REM Persistent mappings reuse the authenticated caladan\rich session
net use W: "\\%SERVER%\hbrake" /persistent:yes
net use Y: "\\%SERVER%\img" /persistent:yes
net use Z: "\\%SERVER%\media" /persistent:yes

echo.
echo Done.
net use
pause