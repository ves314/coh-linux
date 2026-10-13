@echo off
rem Saves every character and stops the City of Heroes servers.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\coh.ps1" stop %*
if errorlevel 1 pause
