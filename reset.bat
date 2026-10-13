@echo off
rem Deletes the servers, the game data copy, accounts and characters, for a fresh start.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\coh.ps1" reset %*
if errorlevel 1 pause
