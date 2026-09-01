# Contribuir a The Field House

¡Gracias por tu interés en mejorar el proyecto! Esta guía es breve a propósito, es un proyecto chico. *(Issues and PRs in English are also welcome — see the note at the bottom.)*

## Reportar un problema

Abrí un [issue](../../issues) con:

- Tu distro y versión de XFCE (`xfce4-panel --version`)
- Qué esperabas que pasara vs. qué pasó
- Las últimas líneas relevantes de `~/.local/state/field-house/log.txt`
- Si aplica, la salida de `systemctl --user status field-house.timer`

## Proponer un cambio

1. Forkeá el repositorio y creá una rama descriptiva (`fix-transicion-multimonitor`, `agregar-flag-verbose`, etc.)
2. Si tocás `bin/change_wallpaper.sh`, `install.sh` o `uninstall.sh` (Linux):
   - Corré `shellcheck` sobre el archivo antes de abrir el PR (`shellcheck bin/change_wallpaper.sh`). El CI del repo lo corre automáticamente en cada push, pero adelantarlo evita idas y vueltas.
   - Corré `bash -n <archivo>` para validar sintaxis (también lo hace el CI).
   - Si tocás una función pura de `bin/change_wallpaper.sh` (conversión de horas, `validar_configuracion`, la lógica de decisión de franja/clima), corré `bats tests/change_wallpaper.bats` — el CI también lo hace, pero adelantarlo evita idas y vueltas. Si agregás una función pura nueva, sumale sus tests en el mismo archivo. La lógica de decisión de franja+clima vive en el cuerpo principal del script (no en una función con nombre) y se testea contra una copia comentada dentro del propio archivo de tests — ver la nota al final de `tests/change_wallpaper.bats` si tocás esa parte.
   - Probá la lógica de franjas/clima sin una sesión XFCE con `bin/change_wallpaper.sh --dry-run` (validar configuración es parte de eso). Si el cambio toca `xfconf-query` real, probalo también en una sesión XFCE — eso sí sigue sin tests automatizados (comportamiento en vivo contra una sesión gráfica real).
   - Mantené los comentarios y docstrings de las funciones existentes como referencia de estilo.
3. Si tocás `windows/engine/FieldHouseEngine.cs`, `windows/engine/Build-Engine.ps1`, `Install.ps1` o `Uninstall.ps1` (Windows):
   - El CI del repo compila `FieldHouseEngine.cs` con `csc.exe` en un runner `windows-latest`, corre `PSScriptAnalyzer` sobre los `.ps1`, un parseo de sintaxis (AST) de esos mismos `.ps1`, y smoke tests con `--dry-run` contra el `.exe` compilado, todo en el job `powershell-checks`. Si tenés Windows disponible localmente, adelantalo con `.\windows\engine\Build-Engine.ps1 -RutaCsharp .\windows\engine\FieldHouseEngine.cs -RutaExeSalida .\FieldHouseEngine.exe` y después `Invoke-ScriptAnalyzer -Path windows\ -Recurse -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost` antes de abrir el PR.
   - Probá la lógica de franjas/clima con `FieldHouseEngine.exe --dry-run` (funciona igual que `--dry-run` en Linux: no toca el fondo real ni escribe logs). Si el cambio toca `SystemParametersInfo` o las Tareas Programadas, probalo también con una instalación real — eso sigue sin cobertura automatizada (el runner de CI no tiene una sesión de escritorio real donde verificar el cambio visual).
   - Si agregás algo a `FieldHouseEngine.cs` que tenga equivalente en `bin/change_wallpaper.sh` (o viceversa), mantené los nombres de configuración alineados: `TtlCacheClima`↔`TTL_CACHE_CLIMA`, `ModoHorarios`↔`MODO_HORARIOS`, etc. — es lo que permite que la documentación de "Cómo funciona" sea común a ambas plataformas.
   - `FieldHouseEngine.cs` se compila con `csc.exe` (C# 5, sin NuGet): evitá sintaxis de C# moderno (pattern matching de `switch`, `record`, target-typed `new`, etc.) y dependencias externas. El parseo de JSON usa la clase `MiniJson` del mismo archivo, no `System.Text.Json`.
4. Si agregás una opción de configuración nueva:
   - En Linux: el bloque `: "${VARIABLE:=valor_default}"` en `bin/change_wallpaper.sh` (para no romper instalaciones existentes con un `config.conf` viejo), y la plantilla que genera `install.sh`. Si la nueva variable participa de `validar_configuracion()`, sumale un caso válido y uno inválido en `tests/change_wallpaper.bats`.
   - En Windows: el método `FusionarConDefaults` en `windows/engine/FieldHouseEngine.cs` (mismo propósito: valores por defecto para config.json viejos sin la clave nueva), el modo interactivo `--config` si tiene sentido que sea preguntable, y el objeto `$configObj` que genera `windows/Install.ps1`.
   - `INSTALACION.md` **e** `INSTALLATION.en.md`, sección correspondiente en ambos (Linux y, si aplica, la tabla comparativa "Windows: diferencias respecto a Linux").
   - Si además es algo visible para el usuario, una entrada en `CHANGELOG.md`.
5. Abrí el pull request contra `main` con una descripción de qué cambia y por qué.

## Agregar tus propias imágenes al proyecto (no solo localmente)

Si querés proponer un set de imágenes alternativo (por ejemplo, otro estilo visual) como opción dentro del repo en vez de solo reemplazarlas localmente, abrí primero un issue para discutirlo — el repo intenta mantener un único set "por defecto" coherente en vez de acumular variantes.

## Sobre el idioma

El proyecto documenta en español como idioma principal, con `README.en.md` e `INSTALLATION.en.md` como espejo en inglés. Si contribuís documentación, intentá actualizar ambos idiomas; si no te sentís cómodo traduciendo, dejá una nota en el PR y alguien más lo completa.

## Código de conducta

Sé respetuoso. Es un proyecto hecho por y para gente que quiere un fondo de pantalla lindo, no hace falta más que eso.
