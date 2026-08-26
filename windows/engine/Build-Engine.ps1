<#
============================================================================
The Field House — Live Wallpaper
Build-Engine.ps1 — compila FieldHouseEngine.cs a un .exe nativo

Se invoca desde Install.ps1. Usa csc.exe (el compilador de C# de
.NET Framework), que viene instalado de fábrica en todo Windows 10 y 11
como parte del sistema operativo — no se depende de que el usuario tenga
el SDK de .NET ni Visual Studio.

Devuelve por stdout la ruta del .exe compilado si todo salió bien, o
lanza una excepción si no se pudo compilar. Install.ps1 trata esto como
un error fatal de instalación: a diferencia de versiones anteriores de
este proyecto (que tenían un lanzador .vbs como red de seguridad),
FieldHouseEngine.exe ES el programa completo — no hay a qué caer de
vuelta si no se puede compilar.
============================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RutaCsharp,

    [Parameter(Mandatory)]
    [string]$RutaExeSalida
)

$ErrorActionPreference = 'Stop'

# csc.exe vive dentro de la carpeta de la versión de .NET Framework
# instalada. Se busca la variante de 64 bits primero (coincide con la
# arquitectura recomendada para Windows 10/11 modernos), y se cae a la de
# 32 bits si no está. Se prueban las rutas conocidas en vez de depender de
# que csc.exe esté en el PATH, porque normalmente no lo está.
$candidatos = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)

$cscExe = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $cscExe) {
    throw "No se encontró csc.exe (compilador de C#, parte de .NET Framework). Se esperaba en: $($candidatos -join ' o '). Este componente viene instalado de fábrica en Windows 10/11; si falta, puede haber sido removido por una política de la organización."
}

# /target:winexe evita que el propio compilador le pegue un manifiesto de
# consola al binario; junto con CreateNoWindow implícito de una app winexe,
# esto asegura que la Tarea Programada no dibuje ninguna ventana. El modo
# --config sigue funcionando igual: aunque el binario sea "winexe", cuando
# se lo ejecuta desde una consola ya abierta (cmd/PowerShell interactivo),
# Windows adjunta la salida de Console.WriteLine a esa consola existente
# igual que lo haría un ejecutable de consola normal.
$argumentosCompilacion = @(
    '/nologo'
    '/target:winexe'
    '/optimize+'
    '/warn:0'
    "/out:$RutaExeSalida"
    $RutaCsharp
)

& $cscExe @argumentosCompilacion
if ($LASTEXITCODE -ne 0) {
    throw "csc.exe terminó con código $LASTEXITCODE al compilar $RutaCsharp"
}

if (-not (Test-Path $RutaExeSalida)) {
    throw "csc.exe no reportó error pero no se generó el archivo esperado: $RutaExeSalida"
}

Write-Output $RutaExeSalida
