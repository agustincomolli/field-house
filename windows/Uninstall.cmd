@echo off
REM ============================================================================
REM The Field House — Live Wallpaper
REM Uninstall.cmd — atajo para desinstalar sin lidiar con la politica de
REM ejecucion de PowerShell.
REM
REM Windows bloquea por defecto la ejecucion de scripts .ps1 (Restricted).
REM Uninstall.ps1 no cambia esa politica de forma global ni persistente: este
REM .cmd simplemente le pasa -ExecutionPolicy Bypass acotado a esta unica
REM invocacion, asi que tu politica de PowerShell no se toca en ningun
REM momento. Podes hacer doble clic en este archivo, o correrlo desde una
REM consola con "Uninstall.cmd" (sin el punto y barra que hace falta con
REM PowerShell).
REM ============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Uninstall.ps1" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.
if %EXIT_CODE% neq 0 (
    echo La desinstalacion termino con un error ^(codigo %EXIT_CODE%^). Revisa los mensajes de arriba.
)

pause
exit /b %EXIT_CODE%
