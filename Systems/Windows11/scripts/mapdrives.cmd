@echo off
net use w: /del /y 2>nul
net use x: /del /y 2>nul
net use y: /del /y 2>nul
net use z: /del /y 2>nul

net use w: \\caladan\hbrake /user:rherd
net use x: \\caladan\foo
net use y: \\caladan\img
net use z: \\caladan\media

if %errorlevel% neq 0 (
    echo One or more drives failed to map.
    pause
)