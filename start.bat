@echo off
rem Sets up City of Heroes on first run, then starts the servers and the game.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\coh.ps1" start %*
if errorlevel 1 pause
