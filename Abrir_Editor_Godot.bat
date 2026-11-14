@echo off
set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"
start "" "C:\Users\Usuario\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --editor --path "%PROJ%"
