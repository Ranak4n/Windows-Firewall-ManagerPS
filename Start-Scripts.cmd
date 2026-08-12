@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Firewall-Manager.ps1"

if not exist "%PS_SCRIPT%" (
    echo Script PowerShell introuvable : %PS_SCRIPT%
    exit /b 1
)

echo Demande des droits administrateur pour modifier les regles pare-feu...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','""%PS_SCRIPT%""'" 

endlocal
