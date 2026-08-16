🇬🇧 [Read this in English](INSTALLATION.en.md)

# Documentación técnica — The Field House

Este documento explica en detalle cómo funciona cada parte del programa, y cómo instalarlo/configurarlo manualmente si preferís no usar `install.sh`.

## Estructura del repositorio

```
field-house/
├── bin/
│   └── cambiar_fondo.sh              # El script que hace el trabajo
├── fondos/                           # Las 7 imágenes de fondo
├── systemd/
│   ├── field-house.service           # Servicio que ejecuta el script
│   ├── field-house.timer             # Timer que lo dispara cada hora
│   └── field-house-login.service     # Servicio que corre al iniciar sesión
├── .github/workflows/
│   └── shellcheck.yml                # CI: valida los scripts en cada push
├── install.sh                        # Instalador interactivo
├── uninstall.sh                      # Desinstalador
├── README.md / README.en.md
├── INSTALACION.md / INSTALLATION.en.md
├── CONTRIBUTING.md
└── LICENSE
```

## Dónde queda instalado (convención XDG)

El instalador no mezcla programa, configuración y datos del usuario en una sola carpeta — sigue la [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html), la misma convención que usan la mayoría de las apps modernas de Linux instaladas por el usuario (sin sudo):

| Qué | Dónde | Por qué ahí |
|---|---|---|
| Programa + imágenes | `~/.local/share/field-house/` | `XDG_DATA_HOME`: datos de la app que no edita el usuario a mano |
| Configuración | `~/.config/field-house/config.conf` | `XDG_CONFIG_HOME`: lo único que el usuario edita |
| Logs | `~/.local/state/field-house/log.txt` | `XDG_STATE_HOME`: datos que cambian con el uso pero no son "documentos" |
| Servicios systemd | `~/.config/systemd/user/` | Ruta estándar para servicios de usuario (no de sistema) |

Ninguna de estas rutas necesita `sudo`: todo vive dentro del `$HOME` del usuario.

## Instalación manual (sin `install.sh`)

Si preferís no correr el instalador, podés armar todo a mano:

```bash
# 1. Programa e imágenes
mkdir -p ~/.local/share/field-house/bin
mkdir -p ~/.local/share/field-house/fondos
cp bin/cambiar_fondo.sh ~/.local/share/field-house/bin/
chmod +x ~/.local/share/field-house/bin/cambiar_fondo.sh
cp fondos/*.jpg ~/.local/share/field-house/fondos/

# 2. Configuración
mkdir -p ~/.config/field-house
cat << 'EOF' > ~/.config/field-house/config.conf
CARPETA_FONDOS="$HOME/.local/share/field-house/fondos"
CIUDAD="CanuelasAR"
HORA_INICIO_AMANECER="06:00"
HORA_INICIO_MEDIODIA="10:00"
HORA_INICIO_ATARDECER="15:00"
HORA_INICIO_NOCHE="20:00"
PASOS_TRANSICION=15
PAUSA_ENTRE_PASOS="0.15"
ESPERA_INICIAL_SEGUNDOS=15
EOF

# 3. Servicios de systemd
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now field-house.timer
systemctl --user enable field-house-login.service
```

Reemplazá `CIUDAD="CanuelasAR"` por la tuya (sin espacios ni tildes; podés probar qué reconoce wttr.in con `curl "https://wttr.in/TuCiudad?format=%C"`).

## Cómo funciona cada parte

### Franjas horarias fijas

El script usa bloques de horario del reloj, siempre iguales sin importar la época del año (a diferencia de una versión anterior de este proyecto que calculaba amanecer/atardecer reales — se simplificó a propósito, ver más abajo):

- Amanecer: `06:00` → `10:00`
- Medio día: `10:00` → `15:00`
- Atardecer: `15:00` → `20:00`
- Noche: `20:00` → `06:00` (día siguiente)

Se editan en `config.conf`, variables `HORA_INICIO_AMANECER`, `HORA_INICIO_MEDIODIA`, `HORA_INICIO_ATARDECER`, `HORA_INICIO_NOCHE`.

> **¿Por qué horas fijas y no el amanecer/atardecer real del día?** Porque simplifica bastante el script (no depende de una consulta extra a una API de horarios solares) y da un resultado más predecible: siempre sabés qué fondo vas a ver a determinada hora, sin que se corra con las estaciones.

### Clima

En cada ejecución se consulta `wttr.in/TU_CIUDAD?format=%C` (solo la condición climática, sin datos adicionales). Si el resultado contiene alguna de estas palabras (`rain`, `drizzle`, `shower`, `thunder`, `overcast`, `cloudy`, `mist`, `fog`), se reemplaza el fondo "base" de la franja actual por el de lluvia correspondiente:

- Amanecer o mediodía nublado/lluvioso → `lluvia-dia.jpg`
- Atardecer nublado/lluvioso → `lluvia-atardecer.jpg`
- Noche nublada/lluviosa → `lluvia-noche.jpg`

Si falla la consulta (sin internet, timeout de 8 segundos superado), se usa el fondo base de la franja sin intentar lluvia, y queda registrado en el log.

### Transición de fundido

Si `imagemagick` está instalado, el script no cambia el fondo de golpe: genera una serie de imágenes intermedias mezclando la imagen anterior con la nueva en proporciones crecientes (`PASOS_TRANSICION`, 15 por defecto) y las va aplicando con una pequeña pausa entre cada una (`PAUSA_ENTRE_PASOS`, 0.15s), dando un efecto de fundido de ~2 segundos en total. Sin ImageMagick, o con `PASOS_TRANSICION=0`, el cambio es directo.

### Ejecución automática con systemd

El proyecto usa **systemd user timers** en vez de `cron`, por varias razones prácticas:

- No hay que editar `crontab -e` a mano (el instalador hace `systemctl --user enable`).
- Se puede consultar el estado con `systemctl --user status field-house.timer` — cron no tiene esto.
- Los logs de ejecución (además del `log.txt` propio del script) quedan disponibles con `journalctl --user -u field-house.service`.
- `Persistent=true` en el timer significa que si la sesión estuvo apagada/suspendida en el momento en que debía dispararse, systemd lo ejecuta apenas puede — no hay que esperar a la próxima hora en punto. Este es el reemplazo directo de lo que en `cron` se resolvía con una entrada `@reboot`.

Hay tres archivos de systemd:

| Archivo | Qué hace |
|---|---|
| `field-house.service` | Define cómo correr el script (`ExecStart`) |
| `field-house.timer` | Dispara ese servicio cada hora (`OnCalendar=hourly`), con `Persistent=true` |
| `field-house-login.service` | Corre el script una vez al iniciar sesión gráfica, con el flag `--reboot` |

`field-house-login.service` existe además del `Persistent=true` del timer porque ese último corre "apenas es posible" tras el arranque, que puede ser antes de que XFCE termine de inicializar `xfconf`. El flag `--reboot` le agrega una espera (`ESPERA_INICIAL_SEGUNDOS`, 15s por defecto) para evitar ese problema.

### Verificación de imágenes

Al arrancar, el script valida que las 7 imágenes de fondo existan en `CARPETA_FONDOS`. Si falta alguna, no aplica ningún cambio y lo deja registrado en el log — así te enterás de un nombre de archivo mal escrito o un reemplazo incompleto apenas corre el script, en vez de descubrirlo recién cuando le toque el turno a esa franja o clima puntual.

### Multi-monitor

El script recorre todas las propiedades `last-image` de xfconf (una por monitor/workspace) y las actualiza a todas, así que si tenés más de un monitor o varios espacios de trabajo, todos quedan sincronizados.

## Solución de problemas

**El timer no corre / `systemctl --user status` da error:**
Confirmá que el bus de sesión de usuario esté activo: `systemctl --user status` sin argumentos no debería fallar. En algunas instalaciones mínimas puede hacer falta `loginctl enable-linger $USER` para que los servicios de usuario sigan corriendo aunque no haya sesión gráfica abierta (no debería ser necesario en un uso normal de escritorio).

**El fondo no cambia aunque el script corre bien a mano:**
Los servicios de systemd de usuario deberían heredar `DISPLAY` y `DBUS_SESSION_BUS_ADDRESS` de la sesión gráfica, pero por las dudas el script y los `.service` los fuerzan explícitamente. Si tu sesión no es la `:0`, ajustá la variable `Environment=DISPLAY=:0` en los archivos `.service` (en `~/.config/systemd/user/`) y corré `systemctl --user daemon-reload`.

**El clima no se detecta bien:**
Probá `curl "https://wttr.in/TuCiudad?format=%C"` directamente en la terminal para ver qué texto exacto devuelve, y ajustá la lista de palabras clave en `bin/cambiar_fondo.sh` (`rain|drizzle|shower|thunder|overcast|cloudy|mist|fog`) si tu clima devuelve una palabra distinta.

**El log dice que faltan imágenes:**
Revisá que los 7 archivos estén en `~/.local/share/field-house/fondos/` con los nombres exactos de la tabla del README (todos en minúscula, con guion medio, extensión `.jpg`).

**La transición no se ve, cambia de golpe:**
Confirmá que `imagemagick` esté instalado (`convert -version` no debería dar error). También revisá que `PASOS_TRANSICION` en `config.conf` no esté en `0`.

**Al prender la compu el fondo queda desactualizado un rato:**
Confirmá que `field-house-login.service` esté habilitado: `systemctl --user is-enabled field-house-login.service` debería decir `enabled`. Si el problema persiste, puede que 15 segundos de espera no alcancen en tu equipo; subí `ESPERA_INICIAL_SEGUNDOS` en `config.conf`.

**Quiero que revise más seguido (o menos):**
Editá `OnCalendar=hourly` en `~/.config/systemd/user/field-house.timer`, por ejemplo a `OnCalendar=*:0/30` para cada 30 minutos. Después corré `systemctl --user daemon-reload && systemctl --user restart field-house.timer`.

**La ubicación detectada automáticamente durante la instalación no era la correcta:**
El instalador usa geolocalización por IP, que puede desviarse varios kilómetros según tu proveedor de internet. Simplemente editá `CIUDAD` en `~/.config/field-house/config.conf` con el valor correcto.
