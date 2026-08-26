<#
============================================================================
The Field House — Live Wallpaper
Uninstall.ps1 — desinstalador (Windows 10 / 11)
Versión: ver el archivo VERSION

Elimina las Tareas Programadas y borra los archivos instalados por
Install.ps1. Pregunta antes de borrar la configuración y los logs, por si
el usuario quiere conservarlos para una reinstalación futura.
============================================================================
#>

[CmdletBinding()]
param(
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppVersion = (Get-Content (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim()

if ($Version) {
    Write-Output "The Field House — Live Wallpaper v$AppVersion — desinstalador (Windows)"
    exit 0
}

function Write-Info    { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "OK  $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "!   $Msg" -ForegroundColor Yellow }

$DatosApp = Join-Path $env:LOCALAPPDATA 'FieldHouse'
$ConfigDir = Join-Path $env:APPDATA 'FieldHouse'
$TaskName = 'FieldHouseWallpaper'
$TaskNameLogin = 'FieldHouseWallpaperLogin'

Write-Host ""
Write-Host "====================================================================="
Write-Host "       THE FIELD HOUSE — DESINSTALADOR (v$AppVersion)"
Write-Host "====================================================================="
Write-Host ""
$confirm = Read-Host "¿Confirmás que querés desinstalar The Field House? [s/N]"
if ($confirm -notmatch '^[sSyY]$') {
    Write-Host "Cancelado."
    exit 0
}

Write-Host ""
Write-Info "Eliminando las Tareas Programadas..."

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskNameLogin -Confirm:$false -ErrorAction SilentlyContinue

Write-Success "Tareas programadas removidas."

Write-Info "Eliminando programa, imágenes y logs..."
# Los logs viven en $DatosApp\state (a diferencia de la versión Linux, que
# los separa en XDG_STATE_HOME); se borran acá junto con el resto del
# programa, no en el paso de configuración de abajo.
Remove-Item -Path $DatosApp -Recurse -Force -ErrorAction SilentlyContinue
Write-Success "Borrado: $DatosApp"

Write-Host ""
$confirmConfig = Read-Host "¿Borrar también la configuración (ciudad, franjas horarias) en ${ConfigDir}? [s/N]"
if ($confirmConfig -match '^[sSyY]$') {
    Remove-Item -Path $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "Configuración borrada."
} else {
    Write-Warn "Se conservó $ConfigDir. Si reinstalás más adelante, tu ciudad y franjas horarias van a seguir ahí."
}

Write-Host ""
Write-Host "====================================================================="
Write-Host "         THE FIELD HOUSE — DESINSTALACIÓN COMPLETADA" -ForegroundColor Green
Write-Host "====================================================================="
Write-Host ""
