@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Firewall-Manager.ps1"

if not exist "%PS_SCRIPT%" (
    echo Script PowerShell introuvable : %PS_SCRIPT%
    exit /b 1
)

rem PowerShell 7 (pwsh) en priorite, repli sur Windows PowerShell 5.1.
set "PS_EXE=pwsh"
where pwsh >nul 2>&1 || set "PS_EXE=powershell"

echo Demande des droits administrateur pour modifier les regles pare-feu...
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath '%PS_EXE%' -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','\"%PS_SCRIPT%\"'"

endlocal
