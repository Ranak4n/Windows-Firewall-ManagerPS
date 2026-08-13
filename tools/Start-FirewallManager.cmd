@echo off
setlocal

rem Lanceur de l'interface graphique, avec demande d'elevation.
rem L'interface fonctionne aussi sans droits administrateur, mais en
rem consultation seule : la creation et la suppression de regles les exigent.

set "SCRIPT_DIR=%~dp0"
set "GUI_SCRIPT=%SCRIPT_DIR%..\src\Gui\Start-FwmGui.ps1"

if not exist "%GUI_SCRIPT%" (
    echo Interface introuvable : %GUI_SCRIPT%
    pause
    exit /b 1
)

rem PowerShell 7 est requis : thread STA pour WPF et selecteur de dossier .NET 8+.
where pwsh >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 est requis mais n'a pas ete trouve.
    echo Installez-le avec : winget install --id Microsoft.PowerShell -e
    pause
    exit /b 1
)

rem Pas de -NoExit : aucune console ne doit survivre a la fermeture de la fenetre.
pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath 'pwsh' -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%GUI_SCRIPT%\"'"

endlocal
