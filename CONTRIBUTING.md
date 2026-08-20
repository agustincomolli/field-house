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
   - Probá la lógica de franjas/clima sin una sesión XFCE con `bin/change_wallpaper.sh --dry-run` (validar configuración es parte de eso). Si el cambio toca `xfconf-query` real, probalo también en una sesión XFCE — no hay tests automatizados para el comportamiento en vivo.
   - Mantené los comentarios y docstrings de las funciones existentes como referencia de estilo.
3. Si tocás `windows/Change-Wallpaper.ps1`, `Install.ps1` o `Uninstall.ps1` (Windows):
   - **El CI del repo solo corre `shellcheck` sobre los scripts bash — no hay verificación automática de la sintaxis o el comportamiento de PowerShell.** Probá el cambio a mano en Windows 10 y/o 11 antes de abrir el PR; es la única forma de detectar errores de sintaxis o de tipos en este momento del proyecto.
   - Si tenés `PSScriptAnalyzer` disponible (`Install-Module PSScriptAnalyzer`), corré `Invoke-ScriptAnalyzer -Path windows\ -Recurse` y adjuntá el resultado en el PR — ayuda mientras no haya CI dedicado.
   - Probá la lógica de franjas/clima con `-DryRun` (funciona igual que `--dry-run` en Linux: no toca el fondo real ni escribe logs). Si el cambio toca `SystemParametersInfo` o las Tareas Programadas, probalo también con una instalación real.
   - Si agregás algo a `Change-Wallpaper.ps1` que tenga equivalente en `bin/change_wallpaper.sh` (o viceversa), mantené los nombres de configuración alineados: `Ciudad`↔`CIUDAD`, `ModoHorarios`↔`MODO_HORARIOS`, etc. — es lo que permite que la documentación de "Cómo funciona" sea común a ambas plataformas.
   - Si te interesa ayudar a agregar CI para PowerShell (por ejemplo con un runner `windows-latest` en GitHub Actions corriendo `PSScriptAnalyzer` y un smoke test con `-DryRun`), es una contribución muy bienvenida — abrí un issue para coordinarlo.
4. Si agregás una opción de configuración nueva:
   - En Linux: el bloque `: "${VARIABLE:=valor_default}"` en `bin/change_wallpaper.sh` (para no romper instalaciones existentes con un `config.conf` viejo), y la plantilla que genera `install.sh`.
   - En Windows: `Get-DefaultConfig` en `windows/Change-Wallpaper.ps1` (mismo propósito), y el objeto `$configObj` que genera `windows/Install.ps1`.
   - `INSTALACION.md` **e** `INSTALLATION.en.md`, sección correspondiente en ambos (Linux y, si aplica, la tabla comparativa "Windows: diferencias respecto a Linux").
   - Si además es algo visible para el usuario, una entrada en `CHANGELOG.md`.
5. Abrí el pull request contra `main` con una descripción de qué cambia y por qué.

## Agregar tus propias imágenes al proyecto (no solo localmente)

Si querés proponer un set de imágenes alternativo (por ejemplo, otro estilo visual) como opción dentro del repo en vez de solo reemplazarlas localmente, abrí primero un issue para discutirlo — el repo intenta mantener un único set "por defecto" coherente en vez de acumular variantes.

## Sobre el idioma

El proyecto documenta en español como idioma principal, con `README.en.md` e `INSTALLATION.en.md` como espejo en inglés. Si contribuís documentación, intentá actualizar ambos idiomas; si no te sentís cómodo traduciendo, dejá una nota en el PR y alguien más lo completa.

## Código de conducta

Sé respetuoso. Es un proyecto hecho por y para gente que quiere un fondo de pantalla lindo, no hace falta más que eso.
