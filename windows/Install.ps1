<#
============================================================================
The Field House — Live Wallpaper
Install.ps1 — instalador (Windows 10 / 11)
Versión: ver el archivo VERSION

Instala la app para el usuario actual (sin privilegios de administrador,
todo en las rutas estándar de %LOCALAPPDATA%/%APPDATA%) y registra la Tarea
Programada que ejecuta el cambio de fondo cada hora y al iniciar sesión. La
ubicación geográfica no se pregunta en la instalación: se detecta sola, por
IP, en cada ejecución del programa (ver ObtenerUbicacion en el motor).

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
    [switch]$Version,
    [switch]$DryRunInstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppVersion = (Get-Content (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim()

# ----------------------------------------------------------------------------
# Colores (mismo estilo que la versión Linux, para consistencia visual)
# ----------------------------------------------------------------------------

function Write-Info    { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "OK  $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "!   $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "X   $Msg" -ForegroundColor Red }

if ($Version) {
    Write-Output "The Field House — Live Wallpaper v$AppVersion — instalador (Windows)"
    exit 0
}

if ($Help) {
    @"
The Field House — Live Wallpaper v$AppVersion — instalador (Windows)

Uso:
  .\Install.ps1               Instalación normal. Si hay una instalación
                                previa, la resguarda con un sufijo
                                .bak.FECHAHORA antes de instalar la nueva.
  .\Install.ps1 -NoBackup     Si hay una instalación previa, la borra
                                directamente en vez de resguardarla. Perdés
                                cualquier imagen o configuración
                                personalizada que no hayas resguardado vos
                                mismo antes.
  .\Install.ps1 -DryRunInstall Ejecuta el instalador en modo simulación;
                                registra las tareas con `-WhatIf` sin
                                efectuar cambios.
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
Write-Host "       THE FIELD HOUSE — LIVE WALLPAPER — INSTALADOR (v$AppVersion)"
Write-Host "====================================================================="
Write-Host ""
Write-Host "Este programa cambia el fondo de pantalla de Windows automáticamente"
Write-Host "según la hora del día y el clima de tu ubicación (detectada automáticamente)."
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
# Modo de horarios (fijo por defecto; auto según la salida/puesta del sol)
# ----------------------------------------------------------------------------

Write-Host ""
Write-Info "Modo de horarios..."
Write-Host "  - 'fijo':  horarios fijos (amanecer 06:00, mediodía 10:00, atardecer 15:00, noche 20:00),"
Write-Host "             siempre iguales, sin importar la estación del año."
Write-Host "  - 'auto':  franjas según la salida y puesta real del sol en tu ubicación (mediodía ="
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
Write-Info "1/3 - Instalando archivos..."

New-Item -ItemType Directory -Path (Join-Path $DatosApp 'bin') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DatosApp 'fondos') -Force | Out-Null
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

# El motor completo (lectura de configuración, consulta de clima y de
# horarios del sol, y aplicación del fondo) está escrito en C# y se
# compila acá con csc.exe — el compilador de C# de .NET Framework,
# incluido de fábrica en todo Windows 10/11. Reemplaza a la versión
# anterior en PowerShell: arranca en milisegundos y, al ser un binario
# nativo, la Tarea Programada puede ejecutarlo directo sin que aparezca
# ninguna ventana de consola (a diferencia de invocar powershell.exe, que
# siempre crea una consola al arrancar, sin importar -WindowStyle Hidden).
$engineCs = Join-Path $Origen 'engine\FieldHouseEngine.cs'
$buildEngineScript = Join-Path $Origen 'engine\Build-Engine.ps1'
$exePath = Join-Path $DatosApp 'bin\FieldHouseEngine.exe'

try {
    & $buildEngineScript -RutaCsharp $engineCs -RutaExeSalida $exePath | Out-Null
} catch {
    Write-Err "No se pudo compilar el motor (FieldHouseEngine.exe): $($_.Exception.Message)"
    exit 1
}
Write-Success "Motor compilado: $exePath"

Copy-Item -Path (Join-Path $Origen '..\VERSION') -Destination (Join-Path $DatosApp 'bin\VERSION') -Force
Copy-Item -Path (Join-Path $Origen '..\fondos\*.jpg') -Destination (Join-Path $DatosApp 'fondos') -Force

# Verificación: si la copia falló parcialmente (por ejemplo un .jpg
# ilegible), el motor se quejaría de imágenes faltantes recién al correr.
# Mejor avisarlo acá, mientras la instalación está fresca.
$fondosCopiados = @(
    Get-ChildItem -Path (Join-Path $DatosApp 'fondos') -Filter '*.jpg' -File -ErrorAction SilentlyContinue
).Count
if ($fondosCopiados -ne 9) {
    Write-Err "La copia de imágenes no quedó completa: se encontraron $fondosCopiados de 9 archivos .jpg. Revisá la carpeta 'fondos\' del repositorio."
    exit 1
}

Write-Success "Programa instalado en $DatosApp"

# ----------------------------------------------------------------------------
# 3) Generar archivo de configuración
# ----------------------------------------------------------------------------

Write-Host ""
Write-Info "2/3 - Generando configuración..."

$configObj = [PSCustomObject]@{
    CarpetaFondos          = Join-Path $DatosApp 'fondos'
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
Write-Info "3/3 - Configurando ejecución automática (Tareas Programadas)..."

$exePath = Join-Path $DatosApp 'bin\FieldHouseEngine.exe'

# Usar la identidad completa de la sesión evita que Register-ScheduledTask
# intente registrar una tarea con el principal predeterminado (SYSTEM), algo
# que normalmente requiere elevación aunque la tarea solo sea del usuario.
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive

# --- Tarea horaria ---
# La Tarea Programada ejecuta FieldHouseEngine.exe directo (sin PowerShell
# de por medio): es un binario nativo, compilado como /target:winexe, así
# que nunca crea ninguna ventana de consola visible al arrancar.
$actionHoraria = New-ScheduledTaskAction -Execute $exePath
# RepetitionDuration: usar un valor grande pero dentro de límites razonables
# Evita valores excesivos que el Programador de tareas puede rechazar (p.ej. P36500D)
$duracionRepeticion = New-TimeSpan -Days 365
$triggerHoraria = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration $duracionRepeticion
$settingsHoraria = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Registrar tarea horaria con el usuario interactivo actual.
$regArgs = @{ TaskName = $TaskName; Action = $actionHoraria; Trigger = $triggerHoraria; Settings = $settingsHoraria; Description = 'The Field House - actualiza el fondo de pantalla cada hora'; Force = $true }
$regArgs.Principal = $principal
$tareaHorariaCreada = $false
try {
    if ($DryRunInstall) {
        Write-Info "Simulación: se llamaría a Register-ScheduledTask para '$TaskName' (modo WhatIf)."
        Register-ScheduledTask @regArgs -WhatIf -ErrorAction Stop
        $tareaHorariaCreada = $true
    } else {
        Register-ScheduledTask @regArgs -ErrorAction Stop | Out-Null
        $tareaHorariaCreada = $true
    }
} catch {
    Write-Warn "Register-ScheduledTask falló: $($_.Exception.Message)"
    # Intentar fallback con schtasks.exe (más compatible en entornos restringidos)
    $schtasksCmd = @('/Create', '/TN', $TaskName, '/TR', "`"$exePath`"", '/SC', 'HOURLY', '/MO', '1', '/F')
    if ($DryRunInstall) {
        Write-Info "Simulación fallback: schtasks.exe $($schtasksCmd -join ' ')"
    } else {
        try {
            & schtasks.exe @schtasksCmd | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Tarea horaria creada con schtasks.exe como fallback."
                $tareaHorariaCreada = $true
            } else {
                Write-Err "Fallback con schtasks.exe falló (código $LASTEXITCODE)."
            }
        } catch {
            Write-Err "Fallback con schtasks.exe falló: $($_.Exception.Message)"
        }
    }
}

# --- Tarea de inicio de sesión (con -Reboot) ---
$actionLogin = New-ScheduledTaskAction -Execute $exePath -Argument '--reboot'
$triggerLogin = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$settingsLogin = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Registrar tarea de inicio de sesión con el usuario interactivo actual.
$regArgsLogin = @{ TaskName = $TaskNameLogin; Action = $actionLogin; Trigger = $triggerLogin; Settings = $settingsLogin; Description = 'The Field House - corrige el fondo de pantalla al iniciar sesión'; Force = $true }
$regArgsLogin.Principal = $principal
$tareaLoginCreada = $false
try {
    if ($DryRunInstall) {
        Write-Info "Simulación: se llamaría a Register-ScheduledTask para '$TaskNameLogin' (modo WhatIf)."
        Register-ScheduledTask @regArgsLogin -WhatIf -ErrorAction Stop
        $tareaLoginCreada = $true
    } else {
        Register-ScheduledTask @regArgsLogin -ErrorAction Stop | Out-Null
        $tareaLoginCreada = $true
    }
} catch {
    Write-Warn "Register-ScheduledTask (login) falló: $($_.Exception.Message)"
    $schtasksCmdLogin = @('/Create', '/TN', $TaskNameLogin, '/TR', "`"$exePath`" --reboot", '/SC', 'ONLOGON', '/RU', $currentUser, '/RL', 'LIMITED', '/IT', '/F')
    if ($DryRunInstall) {
        Write-Info "Simulación fallback: schtasks.exe $($schtasksCmdLogin -join ' ')"
    } else {
        try {
            & schtasks.exe @schtasksCmdLogin | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Tarea de inicio creada con schtasks.exe como fallback."
                $tareaLoginCreada = $true
            } else {
                Write-Err "Fallback con schtasks.exe (login) falló (código $LASTEXITCODE)."
            }
        } catch {
            Write-Err "Fallback con schtasks.exe (login) falló: $($_.Exception.Message)"
        }
    }
}

if ($tareaHorariaCreada -and $tareaLoginCreada) {
    Write-Success "Tareas programadas creadas y habilitadas."
} else {
    Write-Err "No se pudieron crear todas las tareas programadas. La instalación no quedó completa."
    exit 1
}

# Primera ejecución inmediata, para que el fondo quede aplicado ya mismo en
# vez de esperar a la próxima hora en punto.
Write-Info "Aplicando el primer fondo..."
try {
    & $exePath
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
Write-Host "  OK Ubicación     : detección automática por IP en cada arranque"
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
Write-Host "    & `"$exePath`""
Write-Host ""
Write-Host "  Simular sin tocar nada (qué fondo se aplicaría):"
Write-Host "    & `"$exePath`" --dry-run"
Write-Host ""
Write-Host "  Ver la ayuda completa:"
Write-Host "    & `"$exePath`" --help"
Write-Host ""
Write-Host "  Reconfigurar (modo de horarios, franjas horarias):"
Write-Host "    & `"$exePath`" --config"
Write-Host ""
Write-Host "  Ver el log:"
Write-Host "    Get-Content `"$(Join-Path $StateDir 'log.txt')`" -Tail 20 -Wait"
Write-Host ""
Write-Host "  Editar configuración (franjas horarias, transición):"
Write-Host "    notepad `"$ConfigFile`""
Write-Host ""
Write-Host "  Desinstalar:"
Write-Host "    .\Uninstall.ps1"
Write-Host ""
Write-Host "====================================================================="
Write-Host ""
