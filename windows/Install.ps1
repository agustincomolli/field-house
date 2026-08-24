<#
============================================================================
The Field House — Live Wallpaper
Install.ps1 — instalador (Windows 10 / 11)
Versión: 1.2.0

Instala la app para el usuario actual (sin privilegios de administrador,
todo en las rutas estándar de %LOCALAPPDATA%/%APPDATA%), detecta la
ubicación automáticamente para sugerirla como ciudad, y registra la Tarea
Programada que ejecuta el cambio de fondo cada hora y al iniciar sesión.

Uso:
  .\Install.ps1                instalación normal (resguarda una
                                 instalación previa si existe, ver -NoBackup)
  .\Install.ps1 -NoBackup      si hay una instalación previa, la borra
                                 directamente en vez de resguardarla con un
                                 sufijo .bak.FECHAHORA. Perdés cualquier
                                 imagen o configuración personalizada que no
                                 hayas resguardado vos mismo antes.
  .\Install.ps1 -Help          muestra esta ayuda
  .\Install.ps1 -Version       muestra la versión del instalador
============================================================================
#>

[CmdletBinding()]
param(
    [switch]$NoBackup,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$VERSION = '1.2.0'

# ----------------------------------------------------------------------------
# Colores (mismo estilo que la versión Linux, para consistencia visual)
# ----------------------------------------------------------------------------

function Write-Info    { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "OK  $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "!   $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "X   $Msg" -ForegroundColor Red }

if ($Version) {
    Write-Output "The Field House — Live Wallpaper v$VERSION — instalador (Windows)"
    exit 0
}

if ($Help) {
    @"
The Field House — Live Wallpaper v$VERSION — instalador (Windows)

Uso:
  .\Install.ps1               Instalación normal. Si hay una instalación
                                previa, la resguarda con un sufijo
                                .bak.FECHAHORA antes de instalar la nueva.
  .\Install.ps1 -NoBackup     Si hay una instalación previa, la borra
                                directamente en vez de resguardarla. Perdés
                                cualquier imagen o configuración
                                personalizada que no hayas resguardado vos
                                mismo antes.
  .\Install.ps1 -Help         Muestra esta ayuda.
  .\Install.ps1 -Version      Muestra la versión del instalador.
"@ | Write-Output
    exit 0
}

# ----------------------------------------------------------------------------
# Rutas de instalación (convención estándar de Windows)
# ----------------------------------------------------------------------------

$DatosApp = Join-Path $env:LOCALAPPDATA 'FieldHouse'
$ConfigDir = Join-Path $env:APPDATA 'FieldHouse'
$ConfigFile = Join-Path $ConfigDir 'config.json'
$StateDir = Join-Path $DatosApp 'state'
$TaskName = 'FieldHouseWallpaper'
$TaskNameLogin = 'FieldHouseWallpaperLogin'

# Carpeta donde está este instalador (para copiar el motor y las imágenes).
$Origen = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "====================================================================="
Write-Host "       THE FIELD HOUSE — LIVE WALLPAPER — INSTALADOR (v$VERSION)"
Write-Host "====================================================================="
Write-Host ""
Write-Host "Este programa cambia el fondo de pantalla de Windows automáticamente"
Write-Host "según la hora del día y el clima de tu ciudad."
Write-Host ""
Write-Host "Se va a instalar en:"
Write-Host "  Programa e imágenes : $DatosApp"
Write-Host "  Configuración        : $ConfigDir"
Write-Host "  Logs                 : $StateDir"
Write-Host ""

# ----------------------------------------------------------------------------
# Detección de instalación previa
# ----------------------------------------------------------------------------
# Reinstalar NO borra sin resguardo: si ya existe una instalación anterior
# (carpetas o tareas programadas), se la MUEVE a un sufijo .bak.FECHAHORA en
# la misma ubicación antes de instalar la nueva. Así, si el usuario tenía
# imágenes personalizadas en fondos/, quedan recuperables incluso si
# confirmó la reinstalación sin darse cuenta de que eso las iba a reemplazar.

$tareaPreviaExiste = $false
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { $tareaPreviaExiste = $true }
    if (Get-ScheduledTask -TaskName $TaskNameLogin -ErrorAction SilentlyContinue) { $tareaPreviaExiste = $true }
} catch {
    # Get-ScheduledTask puede no estar disponible en ediciones muy acotadas
    # de Windows; se asume que no hay tarea previa en ese caso.
    Write-Verbose "No se pudieron consultar las tareas programadas existentes."
}

$hayInstalacionPrevia = (Test-Path $DatosApp) -or (Test-Path $ConfigDir) -or $tareaPreviaExiste

if ($hayInstalacionPrevia) {
    Write-Host ""
    Write-Warn "Se detectó una instalación previa de The Field House."
    if ($NoBackup) {
        Write-Host "  Corriste el instalador con -NoBackup: el programa, las imágenes"
        Write-Host "  (incluidas las que hayas personalizado), la configuración y los"
        Write-Host "  logs actuales se van a BORRAR de forma DEFINITIVA antes de instalar"
        Write-Host "  la versión nueva. No hay forma de recuperarlos después de esto."
        Write-Host ""
        $confirmReinstall = Read-Host "¿Reinstalar borrando la instalación anterior sin resguardo? [s/N]"
    } else {
        Write-Host "  Antes de instalar la versión nueva, el programa, las imágenes"
        Write-Host "  (incluidas las que hayas personalizado) y la configuración actuales"
        Write-Host "  se van a MOVER a una copia de resguardo con sufijo '.bak.FECHAHORA'"
        Write-Host "  en el mismo lugar donde están ahora. No se borra nada de forma"
        Write-Host "  irreversible; podés recuperarlos a mano después, o borrar la copia"
        Write-Host "  vos mismo cuando ya no la necesites. (Usá -NoBackup si preferís"
        Write-Host "  borrar directamente sin resguardo.)"
        Write-Host ""
        $confirmReinstall = Read-Host "¿Reinstalar? Se resguardará la instalación anterior. [s/N]"
    }
    if ($confirmReinstall -notmatch '^[sSyY]$') {
        Write-Host "Instalación cancelada."
        exit 0
    }
} else {
    $confirmInstall = Read-Host "¿Continuar? [S/n]"
    if ($confirmInstall -match '^[nN]$') {
        Write-Host "Instalación cancelada."
        exit 0
    }
}

if ($hayInstalacionPrevia) {
    # Se borran (no se resguardan) las tareas programadas: son punteros a
    # rutas fijas, no datos del usuario; se regeneran solas al instalar.
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskNameLogin -Confirm:$false -ErrorAction SilentlyContinue

    if ($NoBackup) {
        Write-Info "Eliminando la instalación previa (sin resguardo)..."
        Remove-Item -Path $DatosApp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Instalación previa eliminada. Continuando con una instalación limpia."
    } else {
        Write-Info "Resguardando la instalación previa..."
        $sufijoBak = ".bak.$(Get-Date -Format 'yyyyMMddHHmmss')"

        foreach ($dir in @($DatosApp, $ConfigDir)) {
            if (Test-Path $dir) {
                Move-Item -Path $dir -Destination "$dir$sufijoBak" -Force
            }
        }

        Write-Success "Instalación previa resguardada con el sufijo '$sufijoBak' junto a cada carpeta original."
    }
}

# ----------------------------------------------------------------------------
# 1) Detección automática de ubicación
# ----------------------------------------------------------------------------
# Se usa ip-api.com (HTTP, gratuito, sin API key para uso no comercial y
# volumen bajo) para resolver ciudad + país a partir de la IP pública. Si
# falla, o el usuario no está conforme, se le pide que la escriba a mano.

Write-Host ""
Write-Info "1/4 - Detectando tu ubicación automáticamente..."

$ciudadDetectada = ''
$ciudadLegible = ''

try {
    $geo = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,city,countryCode' -TimeoutSec 8 -ErrorAction Stop
    if ($geo.status -eq 'success' -and $geo.city -and $geo.countryCode) {
        # wttr.in espera el nombre de ciudad sin espacios, pegado al código
        # de país funciona bien como desambiguador (igual que "CanuelasAR").
        $ciudadDetectada = ($geo.city -replace ' ', '') + $geo.countryCode
        $ciudadLegible = "$($geo.city), $($geo.countryCode)"
    }
} catch {
    # Sin internet, o el servicio no respondió: se cae al ingreso manual.
    Write-Verbose "No se pudo detectar la ubicación automáticamente."
}

if ($ciudadDetectada) {
    Write-Success "Ubicación detectada: $ciudadLegible"
    Write-Host ""
    Write-Host "Se va a usar como ciudad para consultar el clima: $ciudadDetectada"
    $confirmCiudad = Read-Host "¿Es correcta? [S/n]"
    if ($confirmCiudad -match '^[nN]$') {
        $ciudadDetectada = ''
    }
} else {
    Write-Warn "No se pudo detectar la ubicación automáticamente (sin internet o el servicio no respondió)."
}

if (-not $ciudadDetectada) {
    Write-Host ""
    Write-Host "Ingresá tu ciudad manualmente, sin espacios ni tildes, seguida del"
    Write-Host "código de país si tu ciudad tiene nombres repetidos en el mundo"
    Write-Host "(por ejemplo: CanuelasAR, LondonGB, ParisFR)."
    Write-Host ""
    Write-Host "Podés probar qué te devuelve wttr.in para un nombre antes de"
    Write-Host "confirmarlo, abriendo en otra ventana de PowerShell:"
    Write-Host '  Invoke-RestMethod "https://wttr.in/TuCiudad?format=%C"'
    Write-Host ""
    $ciudadDetectada = Read-Host "Ciudad"
    while (-not $ciudadDetectada) {
        Write-Warn "No puede quedar vacío."
        $ciudadDetectada = Read-Host "Ciudad"
    }
}

# Misma validación que aplica Change-Wallpaper.ps1 en el arranque: si el
# nombre tuviera caracteres que rompen la URL de wttr.in, nadie se enteraría
# hasta ver un fondo raro. Mejor fallar acá, con el valor a la vista.
if ($ciudadDetectada -notmatch '^[A-Za-z0-9.,_-]+$') {
    Write-Err "Ciudad inválida: '$ciudadDetectada'. Solo letras y números (sin espacios ni tildes), opcionalmente . , _ o -. Ej: CanuelasAR, LondonGB."
    exit 1
}

Write-Success "Ciudad configurada: $ciudadDetectada"

# ----------------------------------------------------------------------------
# Modo de horarios (fijo por defecto; auto según la salida/puesta del sol)
# ----------------------------------------------------------------------------

Write-Host ""
Write-Info "Modo de horarios..."
Write-Host "  - 'fijo':  horarios fijos (amanecer 06:00, mediodía 10:00, atardecer 15:00, noche 20:00),"
Write-Host "             siempre iguales, sin importar la estación del año."
Write-Host "  - 'auto':  franjas según la salida y puesta real del sol en tu ciudad (mediodía ="
Write-Host "             punto medio, noche = puesta + 2 hs). Requiere internet para calcularlas."
$modoHorarios = Read-Host "¿Cuál querés? [fijo/auto] (default: fijo)"
if (-not $modoHorarios) { $modoHorarios = 'fijo' }
if ($modoHorarios -notin @('fijo', 'auto')) {
    Write-Err "Modo inválido: '$modoHorarios'. Debe ser 'fijo' o 'auto'."
    exit 1
}
Write-Success "Horarios: $modoHorarios"

# ----------------------------------------------------------------------------
# 2) Copiar programa e imágenes
# ----------------------------------------------------------------------------

Write-Host ""
Write-Info "2/4 - Instalando archivos..."

New-Item -ItemType Directory -Path (Join-Path $DatosApp 'bin') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DatosApp 'fondos') -Force | Out-Null
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

Copy-Item -Path (Join-Path $Origen 'Change-Wallpaper.ps1') -Destination (Join-Path $DatosApp 'bin\Change-Wallpaper.ps1') -Force
Copy-Item -Path (Join-Path $Origen '..\fondos\*.jpg') -Destination (Join-Path $DatosApp 'fondos') -Force

# Verificación: si la copia falló parcialmente (por ejemplo un .jpg
# ilegible), el motor se quejaría de imágenes faltantes recién al correr.
# Mejor avisarlo acá, mientras la instalación está fresca.
$fondosCopiados = (Get-ChildItem -Path (Join-Path $DatosApp 'fondos') -Filter '*.jpg' -File -ErrorAction SilentlyContinue).Count
if ($fondosCopiados -ne 9) {
    Write-Err "La copia de imágenes no quedó completa: se encontraron $fondosCopiados de 9 archivos .jpg. Revisá la carpeta 'fondos\' del repositorio."
    exit 1
}

Write-Success "Programa instalado en $DatosApp"

# ----------------------------------------------------------------------------
# 3) Generar archivo de configuración
# ----------------------------------------------------------------------------

Write-Host ""
Write-Info "3/4 - Generando configuración..."

$configObj = [PSCustomObject]@{
    CarpetaFondos          = Join-Path $DatosApp 'fondos'
    Ciudad                 = $ciudadDetectada
    ModoHorarios            = $modoHorarios
    HoraInicioAmanecer     = '06:00'
    HoraInicioMediodia     = '10:00'
    HoraInicioAtardecer    = '15:00'
    HoraInicioNoche        = '20:00'
    EsperaInicialSegundos  = 15
    ReintentosClimaInicial = 3
    EsperaReintentoClima   = 60
    TtlCacheClima          = 600
    MaxLogBytes            = 1048576
}

$configObj | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8

Write-Success "Configuración guardada en $ConfigFile"

# ----------------------------------------------------------------------------
# 4) Registrar las Tareas Programadas
# ----------------------------------------------------------------------------
# Se usan dos tareas separadas (en vez de una con dos triggers) para poder
# distinguir en el Programador de tareas cuál dispara por horario y cuál por
# inicio de sesión, y para pasarle -Reboot solo a esta última — igual que la
# separación entre field-house.timer y field-house-login.service en Linux.
#
# Ambas invocan powershell.exe con -ExecutionPolicy Bypass acotado a esa
# invocación puntual, en vez de tocar la política de ejecución global del
# usuario (Set-ExecutionPolicy), que sería un cambio más invasivo y
# persistente del que este instalador no debería ser responsable.

Write-Host ""
Write-Info "4/4 - Configurando ejecución automática (Tareas Programadas)..."

$scriptPath = Join-Path $DatosApp 'bin\Change-Wallpaper.ps1'

# Se usa el mismo intérprete que corrió este instalador (powershell.exe o
# pwsh.exe, según con cuál se haya invocado), para que la tarea programada
# quede consistente con el entorno en el que el usuario ya probó que
# funciona. Si por algún motivo no se puede resolver desde el proceso
# actual, se cae a powershell.exe (Windows PowerShell 5.1), que viene de
# fábrica en Windows 10 y 11.
try {
    $pwshExe = (Get-Process -Id $PID -ErrorAction Stop).Path
} catch {
    $pwshExe = 'powershell.exe'
}
if (-not $pwshExe) { $pwshExe = 'powershell.exe' }

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
# Nota: $env:USERNAME no incluye el dominio. En una máquina doméstica (el
# caso de uso principal de este proyecto) esto no es ambiguo. En una PC
# unida a un dominio corporativo, si el registro de la tarea falla por
# resolución de usuario, reemplazá $env:USERNAME acá por "$env:USERDOMAIN\$env:USERNAME".

# --- Tarea horaria ---
$actionHoraria = New-ScheduledTaskAction -Execute $pwshExe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
# RepetitionDuration: se usa un valor grande (100 años) en vez de
# [TimeSpan]::MaxValue, que puede exceder el límite real que admite el
# Programador de tareas de Windows y hacer fallar el registro de la tarea.
$duracionRepeticion = New-TimeSpan -Days (365 * 100)
$triggerHoraria = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration $duracionRepeticion
$settingsHoraria = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName `
    -Action $actionHoraria -Trigger $triggerHoraria -Principal $principal -Settings $settingsHoraria `
    -Description 'The Field House - actualiza el fondo de pantalla cada hora' -Force | Out-Null

# --- Tarea de inicio de sesión (con -Reboot) ---
$actionLogin = New-ScheduledTaskAction -Execute $pwshExe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Reboot"
$triggerLogin = New-ScheduledTaskTrigger -AtLogOn
$settingsLogin = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskNameLogin `
    -Action $actionLogin -Trigger $triggerLogin -Principal $principal -Settings $settingsLogin `
    -Description 'The Field House - corrige el fondo de pantalla al iniciar sesión' -Force | Out-Null

Write-Success "Tareas programadas creadas y habilitadas."

# Primera ejecución inmediata, para que el fondo quede aplicado ya mismo en
# vez de esperar a la próxima hora en punto.
Write-Info "Aplicando el primer fondo..."
try {
    & $scriptPath
    Write-Success "Fondo aplicado correctamente."
} catch {
    Write-Warn "La primera ejecución falló ($($_.Exception.Message)). Revisá el log en $(Join-Path $StateDir 'log.txt')"
}

# ----------------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------------

Write-Host ""
Write-Host "====================================================================="
Write-Host "         THE FIELD HOUSE — INSTALACIÓN COMPLETADA" -ForegroundColor Green
Write-Host "====================================================================="
Write-Host ""
Write-Host "  OK Programa      : $DatosApp"
Write-Host "  OK Configuración : $ConfigFile"
Write-Host "  OK Logs          : $(Join-Path $StateDir 'log.txt')"
Write-Host "  OK Ciudad        : $ciudadDetectada"
Write-Host "  OK Horarios      : $modoHorarios"
Write-Host ""
if ($hayInstalacionPrevia) {
    if ($NoBackup) {
        Write-Host "  i Se eliminó la instalación anterior sin resguardo (-NoBackup)."
    } else {
        Write-Host "  i Instalación anterior resguardada con el sufijo '$sufijoBak'"
        Write-Host "    junto a cada carpeta original (por ejemplo:"
        Write-Host "    $DatosApp$sufijoBak). Podés recuperar de ahí tus imágenes"
        Write-Host "    personalizadas si las tenías, o borrar esas copias cuando ya no"
        Write-Host "    las necesites."
    }
    Write-Host ""
}
Write-Host "El fondo se va a actualizar solo cada hora, y también al iniciar sesión."
Write-Host ""
Write-Host "Comandos útiles:"
Write-Host ""
Write-Host "  Ver el estado de las tareas:"
Write-Host "    Get-ScheduledTask -TaskName '$TaskName', '$TaskNameLogin'"
Write-Host ""
Write-Host "  Ejecutar manualmente ahora:"
Write-Host "    & `"$scriptPath`""
Write-Host ""
Write-Host "  Simular sin tocar nada (qué fondo se aplicaría):"
Write-Host "    & `"$scriptPath`" -DryRun"
Write-Host ""
Write-Host "  Ver la ayuda completa:"
Write-Host "    & `"$scriptPath`" -Help"
Write-Host ""
Write-Host "  Ver el log:"
Write-Host "    Get-Content `"$(Join-Path $StateDir 'log.txt')`" -Tail 20 -Wait"
Write-Host ""
Write-Host "  Editar configuración (ciudad, franjas horarias):"
Write-Host "    notepad `"$ConfigFile`""
Write-Host ""
Write-Host "  Desinstalar:"
Write-Host "    .\Uninstall.ps1"
Write-Host ""
Write-Host "====================================================================="
Write-Host ""
