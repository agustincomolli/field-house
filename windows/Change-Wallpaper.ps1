<#
============================================================================
The Field House — Live Wallpaper
Change-Wallpaper.ps1 — motor de la app (Windows 10 / 11)
Versión: 1.2.0

Cambia el fondo de pantalla de Windows según franjas horarias FIJAS del
reloj (o, en MODO_HORARIOS "auto", según la salida/puesta real del sol), y
según el clima actual (nublado/lluvia) en amanecer, mediodía, atardecer o
noche.

Este script es el "motor" de la app: es el equivalente funcional exacto de
bin/change_wallpaper.sh (la versión Linux/XFCE del proyecto), reescrito con
las herramientas nativas de Windows en vez de bash + xfconf-query. La
configuración (ciudad, franjas horarias) vive en un archivo JSON aparte que
se carga acá abajo, para que el usuario no tenga que tocar este script.

Se ejecuta automáticamente vía una Tarea Programada (ver FieldHouseTask.xml,
instalada por Install.ps1) con dos disparadores: uno horario y otro al
iniciar sesión. También se puede correr a mano para probar o diagnosticar.

Uso:
  Change-Wallpaper.ps1                Ejecución normal (la usa la tarea
                                        horaria).
  Change-Wallpaper.ps1 -Reboot        Ejecución de inicio de sesión: espera
                                        EsperaInicialSegundos y, si la red no
                                        está lista, reintenta el clima hasta
                                        ReintentosClimaInicial veces cada
                                        EsperaReintentoClima segundos.
  Change-Wallpaper.ps1 -DryRun        Simula la ejecución: muestra qué fondo
                                        se aplicaría sin tocar el fondo real
                                        de Windows, sin escribir logs ni
                                        estado, y sin esperas. Se puede
                                        combinar con -Reboot.
  Change-Wallpaper.ps1 -Version       Muestra la versión del programa.
  Change-Wallpaper.ps1 -Help          Muestra esta ayuda.

Requiere: PowerShell 5.1 o superior (viene de fábrica en Windows 10 y 11).
No tiene dependencias externas: usa Invoke-RestMethod (nativo) para
consultar wttr.in y la API Win32 SystemParametersInfo (vía P/Invoke, nativo
también) para aplicar el fondo. No hay transición de fundido en esta
versión (a diferencia de la versión Linux con ImageMagick): Windows aplica
el cambio de forma directa.
============================================================================
#>

[CmdletBinding()]
param(
    [switch]$Reboot,
    [switch]$DryRun,
    [switch]$Version,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$VERSION = '1.2.0'

# ----------------------------------------------------------------------------
# RUTAS (convención estándar de Windows para datos de app de usuario)
# ----------------------------------------------------------------------------

# Datos de la app (imágenes, instaladas junto con el programa). No deberían
# editarse a mano; si el usuario quiere sus propias imágenes, las reemplaza
# acá o cambia CarpetaFondos en la configuración.
$script:DatosApp = Join-Path $env:LOCALAPPDATA 'FieldHouse'

# Configuración editable por el usuario (ciudad, franjas horarias, etc).
$script:ConfigDir = Join-Path $env:APPDATA 'FieldHouse'
$script:ConfigFile = Join-Path $script:ConfigDir 'config.json'

# Estado/logs de la app (junto a los datos, Windows no separa esto tan
# estrictamente como la convención XDG de Linux).
$script:StateDir = Join-Path $script:DatosApp 'state'
$script:LogFile = Join-Path $script:StateDir 'log.txt'
$script:CacheClima = Join-Path $script:StateDir 'clima.cache.json'
$script:CacheHorarios = Join-Path $script:StateDir 'horarios-sol.cache.json'

# ----------------------------------------------------------------------------
# AYUDA Y VERSIÓN
# ----------------------------------------------------------------------------

function Show-Ayuda {
    @"
The Field House — Live Wallpaper v$VERSION (Windows)

Cambia el fondo de pantalla de Windows según la franja horaria (amanecer,
mediodía, atardecer, noche) y el clima actual (nublado/lluvia) de tu ciudad.

Uso:
  Change-Wallpaper.ps1 [opciones]

Opciones:
  (sin opciones)  Ejecución normal. La usa la tarea programada horaria.
  -Reboot         Ejecución de inicio de sesión: espera EsperaInicialSegundos
                  y, si la red no está lista, reintenta el clima hasta
                  ReintentosClimaInicial veces cada EsperaReintentoClima s.
  -DryRun         Simula la ejecución: muestra qué fondo se aplicaría sin
                  tocar el fondo real, sin escribir logs ni estado, y sin
                  esperas. Se puede combinar con -Reboot.
  -Version        Muestra la versión del programa.
  -Help           Muestra esta ayuda.

La configuración (ciudad, horarios) se lee de:
  $script:ConfigFile

Los logs se escriben en:
  $script:LogFile
"@
}

if ($Version) {
    Write-Output "The Field House — Live Wallpaper v$VERSION (Windows)"
    exit 0
}

if ($Help) {
    Write-Output (Show-Ayuda)
    exit 0
}

# ----------------------------------------------------------------------------
# LOGGING
# ----------------------------------------------------------------------------

# Write-FieldHouseLog <mensaje>
# Agrega una línea con fecha/hora al archivo de log, rotándolo antes si hace
# falta. En -DryRun escribe a la salida estándar en vez del archivo (mismo
# comportamiento que log() en la versión bash).
function Write-FieldHouseLog {
    param([Parameter(Mandatory)][string]$Mensaje)

    if ($DryRun) {
        Write-Output "[dry-run] $Mensaje"
        return
    }

    Invoke-RotarLog

    $linea = "{0} - {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensaje
    Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8
}

# Invoke-RotarLog
# Si el log supera MaxLogBytes (1 MiB por defecto), lo rota a log.txt.1
# conservando solamente la copia más reciente. Equivalente a rotar_log() en
# la versión bash.
function Invoke-RotarLog {
    if ($DryRun) { return }
    if (-not (Test-Path $script:LogFile)) { return }

    # Con Set-StrictMode activo, referenciar $script:Config antes de que se
    # asigne (por ejemplo, en el primer log si config.json todavía no existe)
    # lanzaría una excepción en vez de evaluar a $null; se comprueba con
    # Test-Path variable: primero para evitar eso.
    $maxBytes = 1048576
    if ((Test-Path variable:script:Config) -and $script:Config -and $script:Config.MaxLogBytes) {
        $maxBytes = $script:Config.MaxLogBytes
    }

    $tamano = (Get-Item $script:LogFile).Length

    if ($tamano -ge $maxBytes) {
        $rotado = "$script:LogFile.1"
        Move-Item -Path $script:LogFile -Destination $rotado -Force -ErrorAction SilentlyContinue
        $linea = "{0} - Log superó {1} bytes; se rotó a {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $maxBytes, $rotado
        Add-Content -Path $script:LogFile -Value $linea -Encoding UTF8
    }
}

# ----------------------------------------------------------------------------
# UTILIDADES DE HORA
# ----------------------------------------------------------------------------

# ConvertTo-Minuto <"HH:MM">
# Convierte una hora en formato 24 horas a minutos desde medianoche.
function ConvertTo-Minuto {
    param([Parameter(Mandatory)][string]$Hora)
    $partes = $Hora -split ':'
    return ([int]$partes[0] * 60) + [int]$partes[1]
}

# ConvertTo-Minuto12h <"HH:MM AM|PM">
# Convierte una hora en formato 12 horas (como la manda wttr.in en su
# formato j1: "07:32 AM", "06:25 PM") a minutos desde medianoche.
function ConvertTo-Minuto12h {
    param([Parameter(Mandatory)][string]$Hora12)
    if ($Hora12 -notmatch '^(\d{1,2}):(\d{2}) (AM|PM)$') {
        throw "Formato de hora 12h inesperado: '$Hora12'"
    }
    $h = [int]$Matches[1]
    $m = [int]$Matches[2]
    $ampm = $Matches[3]
    if ($ampm -eq 'PM' -and $h -ne 12) { $h += 12 }
    if ($ampm -eq 'AM' -and $h -eq 12) { $h = 0 }
    return ($h * 60) + $m
}

# ConvertTo-HoraTexto <minutos>
# Convierte minutos desde medianoche a formato HH:MM (solo para mensajes).
# Normaliza el valor al rango [0, 1440) antes de formatear, igual que
# min_a_hora() en la versión bash: MinNoche puede superar 1440 cuando el
# atardecer real (en MODO_HORARIOS=auto) ocurre después de las 22:00 y se le
# suman 2 horas (por ejemplo sunset 22:50 -> 1490 min). Sin normalizar, el
# mensaje mostraría "24:50" en vez de la hora real del día siguiente
# ("00:50"). Esto es solo para que el log sea legible: las comparaciones de
# franja horaria usan los minutos crudos y ya son correctas en ese caso.
function ConvertTo-HoraTexto {
    param([Parameter(Mandatory)][int]$Minutos)
    $min = $Minutos % 1440
    if ($min -lt 0) { $min += 1440 }
    return '{0:d2}:{1:d2}' -f [math]::Floor($min / 60), ($min % 60)
}

# ----------------------------------------------------------------------------
# CONFIGURACIÓN
# ----------------------------------------------------------------------------

# Get-DefaultConfig
# Valores por defecto para cualquier clave ausente en config.json (evita que
# un update rompa una instalación existente con un config.json viejo).
function Get-DefaultConfig {
    [PSCustomObject]@{
        CarpetaFondos          = Join-Path $script:DatosApp 'fondos'
        Ciudad                 = ''
        ModoHorarios            = 'fijo'
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
}

# Merge-Config <base> <cargado>
# Combina el config cargado del disco sobre los valores por defecto,
# preservando cualquier clave nueva que el config.json viejo no tenga
# todavía (equivalente al bloque ": ${VAR:=default}" de la versión bash).
function Merge-Config {
    param($Base, $Cargado)

    # PSCustomObject no tiene un método Copy() nativo; se reconstruye a mano
    # copiando cada propiedad, para no mutar el objeto $Base original.
    $resultado = [PSCustomObject]@{}
    foreach ($prop in $Base.PSObject.Properties) {
        $resultado | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
    }

    if ($null -ne $Cargado) {
        foreach ($prop in $Cargado.PSObject.Properties) {
            if ($resultado.PSObject.Properties.Name -contains $prop.Name) {
                $resultado.$($prop.Name) = $prop.Value
            }
        }
    }
    return $resultado
}

# Test-Configuracion <config>
# Valida los valores de configuración. Un valor inválido detiene la
# ejecución con un mensaje claro en el log, porque aplicaría fondos erróneos
# o rompería las consultas de clima en silencio. Equivalente a
# validar_configuracion() en la versión bash.
function Test-Configuracion {
    param($Config)

    if ($Config.Ciudad -notmatch '^[A-Za-z0-9.,_-]+$') {
        Write-FieldHouseLog "ERROR: Ciudad inválida ('$($Config.Ciudad)'). Debe contener solo letras y números (sin espacios ni tildes), opcionalmente . , _ o -. Ej: CanuelasAR, LondonGB, ParisFR."
        exit 1
    }

    if ($Config.ModoHorarios -notin @('fijo', 'auto')) {
        Write-FieldHouseLog "ERROR: ModoHorarios inválido ('$($Config.ModoHorarios)'). Debe ser 'fijo' (horarios fijos en config.json) o 'auto' (según la salida/puesta del sol)."
        exit 1
    }

    foreach ($campo in 'HoraInicioAmanecer', 'HoraInicioMediodia', 'HoraInicioAtardecer', 'HoraInicioNoche') {
        $valor = $Config.$campo
        if ($valor -notmatch '^([01]?[0-9]|2[0-3]):[0-5][0-9]$') {
            Write-FieldHouseLog "ERROR: $campo inválido ('$valor'). Debe estar en formato HH:MM de 24 horas. Ej: 06:00"
            exit 1
        }
    }

    foreach ($campo in 'EsperaInicialSegundos', 'ReintentosClimaInicial', 'EsperaReintentoClima', 'TtlCacheClima', 'MaxLogBytes') {
        $valor = $Config.$campo
        # ConvertFrom-Json puede deserializar un entero como Int32 o Int64
        # según su magnitud; el regex cubre además el caso en que el usuario
        # lo haya escrito como string en config.json (JSON no lo prohíbe).
        $valorTexto = [string]$valor
        if ($valorTexto -notmatch '^[0-9]+$') {
            Write-FieldHouseLog "ERROR: $campo inválido ('$valorTexto'). Debe ser un entero >= 0."
            exit 1
        }
    }

    if (-not (Test-Path $Config.CarpetaFondos -PathType Container)) {
        Write-FieldHouseLog "ERROR: CarpetaFondos no es un directorio válido ('$($Config.CarpetaFondos)'). Revisá el valor en $script:ConfigFile."
        exit 1
    }
}

# ----------------------------------------------------------------------------
# HORARIOS SEGÚN EL SOL (MODO_HORARIOS = "auto")
# ----------------------------------------------------------------------------

# Get-HorariosSol
# Consulta la salida y puesta del sol en Ciudad usando wttr.in (formato j1,
# el mismo servicio que ya se usa para el clima; no hace falta otra API ni
# coordenadas). Devuelve un objeto con cuatro enteros (minutos desde
# medianoche): Amanecer, Mediodia, Atardecer, Noche — siendo: amanecer =
# salida real del sol, atardecer = puesta real, mediodía = punto medio entre
# ambas, y noche = puesta + 2 horas. El resultado se guarda en un caché
# diario y se reutiliza durante el día, para no consultar la API a cada
# ejecución horaria. Devuelve $null si no se pudo obtener (sin internet,
# ciudad inválida): el llamador usa entonces los horarios fijos.
function Get-HorariosSol {
    param([string]$Ciudad)

    $fechaHoy = Get-Date -Format 'yyyy-MM-dd'

    if (Test-Path $script:CacheHorarios) {
        try {
            $cache = Get-Content $script:CacheHorarios -Raw | ConvertFrom-Json
            if ($cache.Fecha -eq $fechaHoy) {
                return [PSCustomObject]@{
                    Amanecer  = $cache.Amanecer
                    Mediodia  = $cache.Mediodia
                    Atardecer = $cache.Atardecer
                    Noche     = $cache.Noche
                }
            }
        } catch {
            # Caché corrupto o ilegible: se ignora y se vuelve a consultar.
            Write-Verbose "No se pudo leer el caché de horarios del sol."
        }
    }

    try {
        $respuesta = Invoke-RestMethod -Uri "https://wttr.in/${Ciudad}?format=j1" -TimeoutSec 6 -ErrorAction Stop
        $risa = $respuesta.weather[0].astronomy[0].sunrise
        $puesta = $respuesta.weather[0].astronomy[0].sunset
    } catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($risa) -or [string]::IsNullOrWhiteSpace($puesta)) {
        return $null
    }

    $horaAm = ConvertTo-Minuto12h $risa
    $horaHa = ConvertTo-Minuto12h $puesta
    $pm = [math]::Floor(($horaAm + $horaHa) / 2)
    $mn = $horaHa + 120

    if (-not $DryRun) {
        try {
            [PSCustomObject]@{
                Fecha     = $fechaHoy
                Amanecer  = $horaAm
                Mediodia  = $pm
                Atardecer = $horaHa
                Noche     = $mn
            } | ConvertTo-Json | Set-Content -Path $script:CacheHorarios -Encoding UTF8
        } catch {
            Write-FieldHouseLog "AVISO: no se pudo guardar el caché de horarios del sol en $script:CacheHorarios."
        }
    }

    return [PSCustomObject]@{
        Amanecer  = $horaAm
        Mediodia  = $pm
        Atardecer = $horaHa
        Noche     = $mn
    }
}

# ----------------------------------------------------------------------------
# CLIMA
# ----------------------------------------------------------------------------

# Get-Clima <ciudad> <ttlCache>
# Consulta wttr.in UNA vez (con timeout corto) y devuelve la condición en
# minúscula. Devuelve $null si la consulta falla o si la respuesta no es una
# condición real (sin internet, ciudad inválida, etc). Para no molestar a la
# API con consultas redundantes (por ejemplo, cuando la tarea horaria y el
# login disparan casi en el mismo momento), guarda el resultado en un caché
# por TtlCacheClima segundos. Equivalente a consultar_clima() en bash.
function Get-Clima {
    param([string]$Ciudad, [int]$TtlCache)

    if ((Test-Path $script:CacheClima) -and -not $DryRun) {
        try {
            $cache = Get-Content $script:CacheClima -Raw | ConvertFrom-Json
            $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if (($ahora - $cache.Ts) -lt $TtlCache) {
                return $cache.Clima
            }
        } catch {
            # Caché corrupto: se ignora y se vuelve a consultar.
            Write-Verbose "No se pudo leer el caché de clima."
        }
    }

    try {
        # Se usa Invoke-WebRequest (no Invoke-RestMethod) a propósito: la
        # respuesta de format=%C es texto plano, no JSON/XML, y
        # Invoke-RestMethod intenta interpretar el cuerpo según el
        # Content-Type devuelto por el servidor, lo que puede fallar de
        # forma inesperada si wttr.in no manda "text/plain" exacto.
        # Invoke-WebRequest siempre expone el cuerpo crudo en .Content.
        $respuesta = Invoke-WebRequest -Uri "https://wttr.in/${Ciudad}?format=%C" -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
        $pared = $respuesta.Content.Trim().ToLowerInvariant()
    } catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($pared) -or $pared -match 'unknown|error|sorry|page not found') {
        return $null
    }

    if (-not $DryRun) {
        try {
            $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            [PSCustomObject]@{ Ts = $ahora; Clima = $pared } |
                ConvertTo-Json | Set-Content -Path $script:CacheClima -Encoding UTF8
        } catch {
            Write-FieldHouseLog "AVISO: no se pudo guardar el caché de clima en $script:CacheClima."
        }
    }

    return $pared
}

# ----------------------------------------------------------------------------
# APLICAR EL FONDO (Win32 SystemParametersInfo vía P/Invoke)
# ----------------------------------------------------------------------------

$script:Win32Signature = @'
using System;
using System.Runtime.InteropServices;

public static class FieldHouseWallpaper
{
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

    private const uint SPI_SETDESKWALLPAPER = 0x0014;
    private const uint SPIF_UPDATEINIFILE = 0x01;
    private const uint SPIF_SENDCHANGE = 0x02;

    public static bool SetWallpaper(string path)
    {
        return SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
'@

try {
    Add-Type -TypeDefinition $script:Win32Signature -ErrorAction Stop
} catch {
    # Ya estaba cargado en esta sesión (por ejemplo, si se dot-source el
    # script dos veces); no es un error real.
    Write-Verbose "El tipo Win32 del fondo ya estaba cargado en esta sesión."
}

# Set-FieldHouseWallpaper <imagen>
# Aplica <imagen> como fondo de pantalla usando SystemParametersInfo, que a
# diferencia de escribir el registro directamente, actualiza el escritorio
# al instante sin reiniciar explorer.exe y aplica a todos los monitores como
# una sola superficie (Windows no requiere iterar por monitor, a diferencia
# de las propiedades last-image por workspace/monitor de xfconf). Registra
# el resultado; nunca lanza si falla (para no cortar la ejecución del script
# por un solo intento fallido de SPI).
function Set-FieldHouseWallpaper {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Imagen)

    if ($DryRun) {
        Write-FieldHouseLog "DRY-RUN: se aplicaría '$Imagen' como fondo de pantalla."
        return $true
    }

    if (-not (Test-Path $Imagen)) {
        Write-FieldHouseLog "AVISO: la imagen '$Imagen' no existe; no se aplicó ningún fondo."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($Imagen, 'Aplicar como fondo de pantalla')) {
        return $false
    }

    $ok = [FieldHouseWallpaper]::SetWallpaper($Imagen)
    if (-not $ok) {
        Write-FieldHouseLog "AVISO: SystemParametersInfo devolvió error al aplicar '$Imagen'."
    }
    return $ok
}

# ----------------------------------------------------------------------------
# 0) Lock anti-concurrencia (solo en ejecución real)
# ----------------------------------------------------------------------------
# Cierra la puerta a que la tarea horaria y la de inicio de sesión corran el
# script a la vez y se pisen. Usa un Mutex con nombre a nivel de sesión de
# Windows, equivalente funcional del flock() de la versión bash. El mutex se
# libera solo cuando el script termina (incluido un cierre anormal: .NET
# libera mutexes abandonados automáticamente). En -DryRun no se toma el
# lock: la simulación no debe tocar estado ni bloquear otra ejecución real.
#
# Se usa un nombre SIN el prefijo "Global\" a propósito: ese prefijo crea el
# mutex en el namespace de todo el sistema y puede requerir privilegios
# elevados (o lanzar UnauthorizedAccessException) según el contexto de
# ejecución. Como este script corre como tarea programada del usuario (no
# como servicio de sistema), alcanza con un mutex de sesión, que solo
# necesita coordinar ejecuciones del mismo usuario.

$script:MutexHandle = $null

if (-not $DryRun) {
    New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    try {
        $script:MutexHandle = New-Object System.Threading.Mutex($false, 'FieldHouseWallpaperLock')
    } catch {
        Write-FieldHouseLog "ERROR: no se pudo crear el mutex de sincronización ($($_.Exception.Message)). Se aborta esta ejecución."
        exit 1
    }
    $tomado = $script:MutexHandle.WaitOne([TimeSpan]::FromSeconds(30))
    if (-not $tomado) {
        Write-FieldHouseLog "ERROR: no se pudo tomar el lock anti-concurrencia (otra ejecución sigue corriendo tras 30s). Se aborta esta ejecución."
        exit 1
    }
}

try {
    # ------------------------------------------------------------------------
    # 0.1) Cargar configuración
    # ------------------------------------------------------------------------

    if (-not (Test-Path $script:ConfigFile)) {
        Write-FieldHouseLog "ERROR: no se encontró el archivo de configuración en $script:ConfigFile. ¿Corriste Install.ps1?"
        exit 1
    }

    $cargado = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
    $script:Config = Merge-Config (Get-DefaultConfig) $cargado

    if ([string]::IsNullOrWhiteSpace($script:Config.Ciudad)) {
        Write-FieldHouseLog "ERROR: no hay ciudad configurada en $script:ConfigFile. Corré Install.ps1 de nuevo o editá Ciudad manualmente."
        exit 1
    }

    Test-Configuracion $script:Config

    $fondoAmanecer      = Join-Path $script:Config.CarpetaFondos 'amanecer.jpg'
    $fondoMediodia      = Join-Path $script:Config.CarpetaFondos 'mediodia.jpg'
    $fondoAtardecer     = Join-Path $script:Config.CarpetaFondos 'tarde.jpg'
    $fondoNoche         = Join-Path $script:Config.CarpetaFondos 'noche.jpg'
    $fondoNubladoDia    = Join-Path $script:Config.CarpetaFondos 'nublado-dia.jpg'
    $fondoNubladoNoche  = Join-Path $script:Config.CarpetaFondos 'nublado-noche.jpg'
    $fondoLluviaDia     = Join-Path $script:Config.CarpetaFondos 'lluvia-dia.jpg'
    $fondoLluviaAtard   = Join-Path $script:Config.CarpetaFondos 'lluvia-atardecer.jpg'
    $fondoLluviaNoche   = Join-Path $script:Config.CarpetaFondos 'lluvia-noche.jpg'

    # ------------------------------------------------------------------------
    # 0.2) Espera inicial (solo si se invoca con -Reboot)
    # ------------------------------------------------------------------------
    # Al iniciar sesión, el explorador y la red pueden tardar unos segundos en
    # estar listos. Solo se aplica con -Reboot para no demorar las
    # ejecuciones periódicas normales. En -DryRun se omite.

    if ($Reboot -and -not $DryRun) {
        Start-Sleep -Seconds $script:Config.EsperaInicialSegundos
    }

    # ------------------------------------------------------------------------
    # 1) Verificar que todas las imágenes de fondo existen
    # ------------------------------------------------------------------------

    $fondosRequeridos = @(
        $fondoAmanecer, $fondoMediodia, $fondoAtardecer, $fondoNoche,
        $fondoNubladoDia, $fondoNubladoNoche,
        $fondoLluviaDia, $fondoLluviaAtard, $fondoLluviaNoche
    )
    $faltantes = $fondosRequeridos | Where-Object { -not (Test-Path $_) }

    if ($faltantes.Count -gt 0) {
        Write-FieldHouseLog "ERROR: faltan $($faltantes.Count) imagen(es) de fondo: $($faltantes -join ', ')"
        exit 1
    }

    # ------------------------------------------------------------------------
    # 2) Determinar la franja horaria actual (horas fijas o "auto")
    # ------------------------------------------------------------------------

    $ahora = Get-Date
    $ahoraMin = ($ahora.Hour * 60) + $ahora.Minute

    $minAmanecer  = ConvertTo-Minuto $script:Config.HoraInicioAmanecer
    $minMediodia  = ConvertTo-Minuto $script:Config.HoraInicioMediodia
    $minAtardecer = ConvertTo-Minuto $script:Config.HoraInicioAtardecer
    $minNoche     = ConvertTo-Minuto $script:Config.HoraInicioNoche

    if ($script:Config.ModoHorarios -eq 'auto') {
        $horariosSol = Get-HorariosSol -Ciudad $script:Config.Ciudad
        if ($null -ne $horariosSol) {
            $minAmanecer  = $horariosSol.Amanecer
            $minMediodia  = $horariosSol.Mediodia
            $minAtardecer = $horariosSol.Atardecer
            $minNoche     = $horariosSol.Noche
            Write-FieldHouseLog "Horarios según el sol: amanecer $(ConvertTo-HoraTexto $minAmanecer), mediodía $(ConvertTo-HoraTexto $minMediodia), atardecer $(ConvertTo-HoraTexto $minAtardecer), noche $(ConvertTo-HoraTexto $minNoche)"
        } else {
            Write-FieldHouseLog "AVISO: no se pudo obtener la salida/puesta del sol; se usan los horarios fijos de config.json."
        }
    }

    # FranjaClima indica qué fondo de nublado/lluvia corresponde según la
    # franja: "dia" (amanecer o mediodía), "atardecer" o "noche".
    if ($ahoraMin -ge $minAmanecer -and $ahoraMin -lt $minMediodia) {
        $fondo = $fondoAmanecer; $momento = 'amanecer'; $franjaClima = 'dia'
    } elseif ($ahoraMin -ge $minMediodia -and $ahoraMin -lt $minAtardecer) {
        $fondo = $fondoMediodia; $momento = 'mediodia'; $franjaClima = 'dia'
    } elseif ($ahoraMin -ge $minAtardecer -and $ahoraMin -lt $minNoche) {
        $fondo = $fondoAtardecer; $momento = 'atardecer'; $franjaClima = 'atardecer'
    } else {
        $fondo = $fondoNoche; $momento = 'noche'; $franjaClima = 'noche'
    }

    # ------------------------------------------------------------------------
    # 3) Consultar el clima actual y, si está nublado o llueve, usar el fondo
    #    correspondiente a la franja (día, atardecer o noche). El "nublado" y
    #    la "lluvia" son condiciones distintas y usan imágenes distintas;
    #    durante el atardecer nublado se usa la imagen "nublado-dia" (aún hay
    #    luz de día).
    #
    #    Al iniciar sesión (-Reboot) la red puede estar todavía levantándose,
    #    así que si la consulta falla se aplica ya el fondo base de la franja
    #    y se reintenta cada EsperaReintentoClima segundos, hasta
    #    ReintentosClimaInicial veces.
    # ------------------------------------------------------------------------

    $clima = $null
    if ($Reboot -and -not $DryRun) {
        $intento = 1
        while ($intento -le $script:Config.ReintentosClimaInicial) {
            $clima = Get-Clima -Ciudad $script:Config.Ciudad -TtlCache $script:Config.TtlCacheClima
            if ($null -ne $clima) { break }
            if ($intento -lt $script:Config.ReintentosClimaInicial) {
                Write-FieldHouseLog "Sin internet todavía (intento $intento/$($script:Config.ReintentosClimaInicial)), se aplica el fondo base y se reintenta en $($script:Config.EsperaReintentoClima)s."
                Set-FieldHouseWallpaper $fondo | Out-Null
                Start-Sleep -Seconds $script:Config.EsperaReintentoClima
            }
            $intento++
        }
    } else {
        $clima = Get-Clima -Ciudad $script:Config.Ciudad -TtlCache $script:Config.TtlCacheClima
    }

    if ($null -eq $clima) {
        Write-FieldHouseLog "No se pudo consultar el clima, se usa el fondo base ($momento)"
    } elseif ($clima -match 'overcast|cloudy') {
        switch ($franjaClima) {
            { $_ -in @('dia', 'atardecer') } { $fondo = $fondoNubladoDia; $momento = "nublado de día ($clima)" }
            'noche' { $fondo = $fondoNubladoNoche; $momento = "nublado de noche ($clima)" }
        }
    } elseif ($clima -match 'rain|drizzle|shower|thunder|mist|fog') {
        switch ($franjaClima) {
            'dia' { $fondo = $fondoLluviaDia; $momento = "lluvia de día ($clima)" }
            'atardecer' { $fondo = $fondoLluviaAtard; $momento = "lluvia de atardecer ($clima)" }
            'noche' { $fondo = $fondoLluviaNoche; $momento = "lluvia de noche ($clima)" }
        }
    }

    # ------------------------------------------------------------------------
    # 4) Aplicar el fondo elegido
    # ------------------------------------------------------------------------

    Set-FieldHouseWallpaper $fondo | Out-Null

    Write-FieldHouseLog "Fondo aplicado: $momento -> $fondo"
}
finally {
    if ($null -ne $script:MutexHandle) {
        try {
            $script:MutexHandle.ReleaseMutex()
        } catch {
            # El mutex puede no estar tomado si se salió antes del WaitOne
            # (por ejemplo, error de configuración temprano); no es un error.
            Write-Verbose "No se pudo liberar el mutex; puede que no estuviera tomado."
        }
        $script:MutexHandle.Dispose()
    }
}
