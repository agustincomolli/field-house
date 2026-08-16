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
2. Si tocás `bin/cambiar_fondo.sh`, `install.sh` o `uninstall.sh`:
   - Corré `shellcheck` sobre el archivo antes de abrir el PR (`shellcheck bin/cambiar_fondo.sh`). El CI del repo lo corre automáticamente en cada push, pero adelantarlo evita idas y vueltas.
   - Probá el script a mano en una sesión XFCE real si el cambio toca `xfconf-query` o la lógica de franjas/clima — no hay tests automatizados para el comportamiento en vivo.
   - Mantené los comentarios y docstrings de las funciones existentes como referencia de estilo.
3. Si agregás una opción de configuración nueva, actualizá:
   - El bloque `: "${VARIABLE:=valor_default}"` en `bin/cambiar_fondo.sh` (para no romper instalaciones existentes con un `config.conf` viejo)
   - La plantilla que genera `install.sh`
   - `INSTALACION.md` **e** `INSTALLATION.en.md`, sección correspondiente en ambos
4. Abrí el pull request contra `main` con una descripción de qué cambia y por qué.

## Agregar tus propias imágenes al proyecto (no solo localmente)

Si querés proponer un set de imágenes alternativo (por ejemplo, otro estilo visual) como opción dentro del repo en vez de solo reemplazarlas localmente, abrí primero un issue para discutirlo — el repo intenta mantener un único set "por defecto" coherente en vez de acumular variantes.

## Sobre el idioma

El proyecto documenta en español como idioma principal, con `README.en.md` e `INSTALLATION.en.md` como espejo en inglés. Si contribuís documentación, intentá actualizar ambos idiomas; si no te sentís cómodo traduciendo, dejá una nota en el PR y alguien más lo completa.

## Código de conducta

Sé respetuoso. Es un proyecto hecho por y para gente que quiere un fondo de pantalla lindo, no hace falta más que eso.
