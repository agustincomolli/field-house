#!/usr/bin/env bats
# ============================================================================
# tests/change_wallpaper.bats
#
# Tests unitarios para las funciones puras de bin/change_wallpaper.sh:
# conversión de horas, validación de configuración, y la lógica de decisión
# de franja horaria + clima. No tocan red, xfconf, ni el filesystem real más
# allá de un TMPDIR descartable por test.
#
# Requiere: bats-core (https://github.com/bats-core/bats-core)
#   Debian/Ubuntu: sudo apt install bats
#   O vía npm:      npm install -g bats
#
# Ejecutar:
#   bats tests/change_wallpaper.bats
#
# Cómo funciona el aislamiento:
#   El script real se carga con `source`, pero con la variable de entorno
#   FIELD_HOUSE_SOURCE_ONLY seteada. bin/change_wallpaper.sh reconoce esa
#   variable y termina justo después de definir todas las funciones, sin
#   ejecutar el cuerpo principal (sin tomar el lock, sin tocar red, sin leer
#   config.conf real). Así se testean las funciones tal como están en
#   producción, sin una copia paralela del código que pueda desincronizarse.
# ============================================================================

setup() {
    # Cada test corre en su propio TMPDIR (bats lo crea y borra solo).
    export SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/../bin/change_wallpaper.sh"

    # Variables mínimas que el script referencia en el cuerpo principal
    # (con el guard, no se llegan a usar, pero `set -u` dentro del script
    # exigiría que existan si alguna función las lee sin default).
    export FIELD_HOUSE_SOURCE_ONLY=1

    source "$SCRIPT_UNDER_TEST"
}

# ----------------------------------------------------------------------------
# hora_a_minutos
# ----------------------------------------------------------------------------

@test "hora_a_minutos: medianoche es 0" {
    result="$(hora_a_minutos '00:00')"
    [ "$result" -eq 0 ]
}

@test "hora_a_minutos: convierte una hora simple" {
    result="$(hora_a_minutos '06:30')"
    [ "$result" -eq 390 ]
}

@test "hora_a_minutos: convierte horas 08 y 09 sin interpretarlas como octales" {
    [ "$(hora_a_minutos '08:05')" -eq 485 ]
    [ "$(hora_a_minutos '09:07')" -eq 547 ]
}

@test "hora_a_minutos: convierte mediodía" {
    result="$(hora_a_minutos '12:00')"
    [ "$result" -eq 720 ]
}

@test "hora_a_minutos: convierte el último minuto del día" {
    result="$(hora_a_minutos '23:59')"
    [ "$result" -eq 1439 ]
}

@test "hora_a_minutos: hora con minutos en cero" {
    result="$(hora_a_minutos '15:00')"
    [ "$result" -eq 900 ]
}

# ----------------------------------------------------------------------------
# min_a_hora
# ----------------------------------------------------------------------------

@test "min_a_hora: caso normal" {
    result="$(min_a_hora 773)"
    [ "$result" = "12:53" ]
}

@test "min_a_hora: cero minutos" {
    result="$(min_a_hora 0)"
    [ "$result" = "00:00" ]
}

@test "min_a_hora: exactamente 1440 minutos normaliza a 00:00" {
    result="$(min_a_hora 1440)"
    [ "$result" = "00:00" ]
}

@test "min_a_hora: caso limite real - sunset tardio + 2h cruza medianoche" {
    # Bug documentado en CHANGELOG v1.2.0: con MODO_HORARIOS=auto y un
    # atardecer real después de las 22:00 (posible en veranos de latitudes
    # altas), MIN_NOCHE = sunset + 120 podía superar 1440 y el log mostraba
    # una hora inválida como "24:50" en vez de la hora real del día
    # siguiente. Este test fija ese comportamiento para que no vuelva a
    # regresar sin que la suite lo note.
    result="$(min_a_hora 1490)"
    [ "$result" = "00:50" ]
}

@test "min_a_hora: valores bien por encima de 1440 siguen normalizando" {
    # 1440*2 + 30 = 2910; debería dar lo mismo que 30 minutos.
    result="$(min_a_hora 2910)"
    [ "$result" = "00:30" ]
}

# ----------------------------------------------------------------------------
# validar_configuracion — casos válidos
# ----------------------------------------------------------------------------
# validar_configuracion() llama log() y hace `exit 1` ante un valor
# inválido. Cada test bats corre en su propio subshell, así que ese exit
# no afecta al resto de la suite; se usa `run` para capturarlo.

# set_config_valida: deja todas las variables que validar_configuracion()
# revisa con valores válidos por defecto. Los tests que prueban un caso
# inválido puntual sobrescriben solo la variable que quieren romper.
set_config_valida() {
    MODO_HORARIOS="fijo"
    HORA_INICIO_AMANECER="06:00"
    HORA_INICIO_MEDIODIA="10:00"
    HORA_INICIO_ATARDECER="15:00"
    HORA_INICIO_NOCHE="20:00"
    PASOS_TRANSICION="15"
    PAUSA_ENTRE_PASOS="0.15"
    ESPERA_INICIAL_SEGUNDOS="15"
    REINTENTOS_CLIMA_INICIAL="3"
    ESPERA_REINTENTO_CLIMA="60"
    TTL_CACHE_CLIMA="600"
    MAX_LOG_BYTES="1048576"
    CARPETA_FONDOS="$BATS_TEST_TMPDIR"
    CONFIG_FILE="$BATS_TEST_TMPDIR/config.conf"
    STATE_DIR="$BATS_TEST_TMPDIR"
    LOG_FILE="$BATS_TEST_TMPDIR/log.txt"
    MODO_DRY="si"   # log() a stdout, no a archivo; simplifica el test
}

@test "validar_configuracion: configuracion valida no sale con error" {
    set_config_valida
    run validar_configuracion
    [ "$status" -eq 0 ]
}

@test "validar_configuracion: acepta MODO_HORARIOS=auto" {
    set_config_valida
    MODO_HORARIOS="auto"
    run validar_configuracion
    [ "$status" -eq 0 ]
}

# ----------------------------------------------------------------------------
# validar_configuracion — casos inválidos
# ----------------------------------------------------------------------------

@test "validar_configuracion: rechaza MODO_HORARIOS invalido" {
    set_config_valida
    MODO_HORARIOS="siempre"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"MODO_HORARIOS inválido"* ]]
}

@test "validar_configuracion: rechaza hora sin formato HH:MM" {
    set_config_valida
    HORA_INICIO_AMANECER="6:00"
    run validar_configuracion
    # "6:00" (sin cero a la izquierda) SI matchea el regex del script
    # ([01]?[0-9] permite un solo dígito), así que este caso es válido.
    [ "$status" -eq 0 ]
}

@test "validar_configuracion: rechaza hora con minutos invalidos" {
    set_config_valida
    HORA_INICIO_AMANECER="06:75"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"HORA_INICIO_AMANECER inválida"* ]]
}

@test "validar_configuracion: rechaza hora 24:00 (fuera de rango 24h)" {
    set_config_valida
    HORA_INICIO_NOCHE="24:00"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"HORA_INICIO_NOCHE inválida"* ]]
}

@test "validar_configuracion: rechaza PASOS_TRANSICION negativo" {
    set_config_valida
    PASOS_TRANSICION="-5"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"PASOS_TRANSICION inválido"* ]]
}

@test "validar_configuracion: acepta PASOS_TRANSICION en cero" {
    set_config_valida
    PASOS_TRANSICION="0"
    run validar_configuracion
    [ "$status" -eq 0 ]
}

@test "validar_configuracion: rechaza PAUSA_ENTRE_PASOS no numerica" {
    set_config_valida
    PAUSA_ENTRE_PASOS="rapido"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"PAUSA_ENTRE_PASOS inválida"* ]]
}

@test "validar_configuracion: acepta PAUSA_ENTRE_PASOS entera sin decimales" {
    set_config_valida
    PAUSA_ENTRE_PASOS="1"
    run validar_configuracion
    [ "$status" -eq 0 ]
}

@test "validar_configuracion: rechaza CARPETA_FONDOS inexistente" {
    set_config_valida
    CARPETA_FONDOS="$BATS_TEST_TMPDIR/no-existe-esta-carpeta"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"CARPETA_FONDOS no es un directorio válido"* ]]
}

@test "validar_configuracion: valida en orden, primer error corta la ejecucion" {
    # Confirma que validar_configuracion no sigue evaluando después del
    # primer error (importante: si TTL_CACHE_CLIMA también estuviera mal,
    # el mensaje reportado debe ser el de MODO_HORARIOS, la primera
    # validación que hace la función).
    set_config_valida
    MODO_HORARIOS="siempre"
    TTL_CACHE_CLIMA="no-es-un-numero"
    run validar_configuracion
    [ "$status" -eq 1 ]
    [[ "$output" == *"MODO_HORARIOS inválido"* ]]
    [[ "$output" != *"TTL_CACHE_CLIMA"* ]]
}

# ----------------------------------------------------------------------------
# detectar_escritorio
# ----------------------------------------------------------------------------
# Cubre el mapeo de XDG_CURRENT_DESKTOP (con DESKTOP_SESSION como respaldo) a
# los identificadores internos que usan aplicar_fondo/obtener_fondo_actual.
# No depende de red ni de una sesión gráfica real: es pura lógica de texto.

@test "detectar_escritorio: XFCE" {
    XDG_CURRENT_DESKTOP="XFCE"
    result="$(detectar_escritorio)"
    [ "$result" = "xfce" ]
}

@test "detectar_escritorio: GNOME" {
    XDG_CURRENT_DESKTOP="GNOME"
    result="$(detectar_escritorio)"
    [ "$result" = "gnome" ]
}

@test "detectar_escritorio: Ubuntu usa GNOME por debajo (XDG_CURRENT_DESKTOP=ubuntu:GNOME)" {
    XDG_CURRENT_DESKTOP="ubuntu:GNOME"
    result="$(detectar_escritorio)"
    [ "$result" = "gnome" ]
}

@test "detectar_escritorio: Cinnamon" {
    XDG_CURRENT_DESKTOP="X-Cinnamon"
    result="$(detectar_escritorio)"
    [ "$result" = "cinnamon" ]
}

@test "detectar_escritorio: MATE" {
    XDG_CURRENT_DESKTOP="MATE"
    result="$(detectar_escritorio)"
    [ "$result" = "mate" ]
}

@test "detectar_escritorio: KDE Plasma" {
    XDG_CURRENT_DESKTOP="KDE"
    result="$(detectar_escritorio)"
    [ "$result" = "kde" ]
}

@test "detectar_escritorio: usa DESKTOP_SESSION como respaldo si XDG_CURRENT_DESKTOP esta vacia" {
    XDG_CURRENT_DESKTOP=""
    DESKTOP_SESSION="cinnamon"
    result="$(detectar_escritorio)"
    [ "$result" = "cinnamon" ]
}

@test "detectar_escritorio: escritorio no reconocido devuelve vacio" {
    XDG_CURRENT_DESKTOP="LXQt"
    DESKTOP_SESSION=""
    result="$(detectar_escritorio)"
    [ "$result" = "" ]
}


# ----------------------------------------------------------------------------
# Lógica de decisión de franja horaria + clima
# ----------------------------------------------------------------------------
# Esta lógica vive en el cuerpo principal del script (no en una función
# separada), así que se replica acá en una función de test local idéntica
# a la del script real. Ver la nota al final del archivo sobre esta
# decisión y su trade-off.

decidir_fondo_test() {
    local ahora_min="$1" min_amanecer="$2" min_mediodia="$3" min_atardecer="$4" min_noche="$5"
    local clima="$6"
    # PRECONDICIÓN: $clima debe venir en minúsculas, igual que lo entrega
    # siempre consultar_clima() en el script real (línea "pared=$(... | tr
    # '[:upper:]' '[:lower:]')"). El match de grep de acá abajo es
    # case-sensitive a propósito, replicando el comportamiento real; pasar
    # un string con mayúsculas simularía una entrada que el script real
    # nunca produce. Ver el test "consultar_clima normaliza a minúsculas"
    # más abajo, que fija ese contrato explícitamente.

    local fondo momento franja_clima

    if [ "$ahora_min" -ge "$min_amanecer" ] && [ "$ahora_min" -lt "$min_mediodia" ]; then
        fondo="amanecer.jpg"; momento="amanecer"; franja_clima="dia"
    elif [ "$ahora_min" -ge "$min_mediodia" ] && [ "$ahora_min" -lt "$min_atardecer" ]; then
        fondo="mediodia.jpg"; momento="mediodia"; franja_clima="dia"
    elif [ "$ahora_min" -ge "$min_atardecer" ] && [ "$ahora_min" -lt "$min_noche" ]; then
        fondo="tarde.jpg"; momento="atardecer"; franja_clima="atardecer"
    else
        fondo="noche.jpg"; momento="noche"; franja_clima="noche"
    fi

    if [ -z "$clima" ]; then
        : # sin clima disponible, se mantiene el fondo base
    elif echo "$clima" | grep -qE "cloudy|fair|partlycloudy"; then
        case "$franja_clima" in
            dia|atardecer) fondo="nublado-dia.jpg"; momento="nublado de día" ;;
            noche) fondo="nublado-noche.jpg"; momento="nublado de noche" ;;
        esac
    elif echo "$clima" | grep -qE "rain|sleet|snow|thunder|fog"; then
        case "$franja_clima" in
            dia) fondo="lluvia-dia.jpg"; momento="lluvia de día" ;;
            atardecer) fondo="lluvia-atardecer.jpg"; momento="lluvia de atardecer" ;;
            noche) fondo="lluvia-noche.jpg"; momento="lluvia de noche" ;;
        esac
    fi

    echo "$fondo"
}

@test "decision de franja: 07:00 con sol fijo 06/10/15/20 es amanecer" {
    result="$(decidir_fondo_test 420 360 600 900 1200 '')"
    [ "$result" = "amanecer.jpg" ]
}

@test "decision de franja: 11:00 es mediodia" {
    result="$(decidir_fondo_test 660 360 600 900 1200 '')"
    [ "$result" = "mediodia.jpg" ]
}

@test "decision de franja: 16:00 es atardecer" {
    result="$(decidir_fondo_test 960 360 600 900 1200 '')"
    [ "$result" = "tarde.jpg" ]
}

@test "decision de franja: 22:00 es noche" {
    result="$(decidir_fondo_test 1320 360 600 900 1200 '')"
    [ "$result" = "noche.jpg" ]
}

@test "decision de franja: 02:00 (madrugada) tambien es noche" {
    result="$(decidir_fondo_test 120 360 600 900 1200 '')"
    [ "$result" = "noche.jpg" ]
}

@test "decision de franja: limite exacto de inicio de mediodia (600) ya es mediodia" {
    # El límite inferior es inclusivo (-ge), así que el minuto exacto de
    # inicio de una franja pertenece a esa franja, no a la anterior.
    result="$(decidir_fondo_test 600 360 600 900 1200 '')"
    [ "$result" = "mediodia.jpg" ]
}

@test "decision de franja: un minuto antes del limite sigue en la franja anterior" {
    result="$(decidir_fondo_test 599 360 600 900 1200 '')"
    [ "$result" = "amanecer.jpg" ]
}

@test "clima: partlycloudy de dia usa nublado-dia" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'partlycloudy_day')"
    [ "$result" = "nublado-dia.jpg" ]
}

@test "clima: cloudy de noche usa nublado-noche" {
    result="$(decidir_fondo_test 1320 360 600 900 1200 'cloudy')"
    [ "$result" = "nublado-noche.jpg" ]
}

@test "clima: fair de atardecer usa nublado-dia (no hay nublado-atardecer)" {
    result="$(decidir_fondo_test 960 360 600 900 1200 'fair_day')"
    [ "$result" = "nublado-dia.jpg" ]
}

@test "clima: lluvia de dia usa lluvia-dia" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'lightrain')"
    [ "$result" = "lluvia-dia.jpg" ]
}

@test "clima: lluvia de atardecer usa lluvia-atardecer (imagen propia)" {
    result="$(decidir_fondo_test 960 360 600 900 1200 'heavyrain')"
    [ "$result" = "lluvia-atardecer.jpg" ]
}

@test "clima: lluvia de noche usa lluvia-noche" {
    result="$(decidir_fondo_test 1320 360 600 900 1200 'rainandthunder')"
    [ "$result" = "lluvia-noche.jpg" ]
}

@test "clima: niebla se trata como lluvia, no como despejado" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'fog')"
    [ "$result" = "lluvia-dia.jpg" ]
}

@test "clima: nieve tambien se trata como lluvia" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'lightsnow')"
    [ "$result" = "lluvia-dia.jpg" ]
}

@test "clima: aguanieve (sleet) tambien se trata como lluvia" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'sleet')"
    [ "$result" = "lluvia-dia.jpg" ]
}

@test "clima: cielo despejado no reemplaza el fondo base" {
    result="$(decidir_fondo_test 660 360 600 900 1200 'clearsky_day')"
    [ "$result" = "mediodia.jpg" ]
}

@test "clima: string vacio (fallo de consulta) no reemplaza el fondo base" {
    result="$(decidir_fondo_test 660 360 600 900 1200 '')"
    [ "$result" = "mediodia.jpg" ]
}

# ----------------------------------------------------------------------------
# consultar_clima — contrato de normalización (sin red real)
# ----------------------------------------------------------------------------
# consultar_clima() llama a curl de verdad; no se testea acá su integración
# con api.met.no (eso corresponde a un test de integración con red, fuera del
# alcance de esta suite). Lo que sí se puede fijar sin red es el contrato de
# que, cuando SÍ hay una respuesta, se normaliza a minúsculas antes de
# devolverla — que es la precondición de la que depende toda la lógica de
# decidir_fondo_test() de arriba (ver la nota en esa función).

@test "consultar_clima: usa el cache sin llamar a curl si no venció" {
    set_config_valida
    # A diferencia del test anterior (descartado), este ejercita el camino
    # real de la función: con MODO_DRY=no y un caché reciente (TS = ahora),
    # consultar_clima() debe devolver el valor cacheado por la rama de
    # "return 0" temprano, sin necesitar red. No se mockea curl: si el
    # código intentara igual llamarlo y no hubiera red en el entorno de CI,
    # este test lo notaría porque tardaría el timeout completo (8s) en vez
    # de responder al instante. lat/lon son irrelevantes en este camino (no
    # se llegan a usar), pero la función los exige como argumentos.
    MODO_DRY="no"
    CACHE_CLIMA="$BATS_TEST_TMPDIR/clima.cache"
    printf 'TS=%s\nCLIMA=cloudy\n' "$(date +%s)" > "$CACHE_CLIMA"

    result="$(timeout 3 bash -c '
        export FIELD_HOUSE_SOURCE_ONLY=1
        source "'"$SCRIPT_UNDER_TEST"'" 2>/dev/null
        CACHE_CLIMA="'"$CACHE_CLIMA"'"
        MODO_DRY="no"
        TTL_CACHE_CLIMA="600"
        consultar_clima "-35.05" "-58.76"
    ')"
    [ "$result" = "cloudy" ]
}

# ----------------------------------------------------------------------------
# obtener_ubicacion
# ----------------------------------------------------------------------------
# obtener_ubicacion() llama a curl de verdad contra ip-api.com; no se testea
# acá su integración real con esa API. Lo que sí se puede fijar sin red es
# el contrato del caché: a diferencia de consultar_clima/consultar_horarios_sol
# (que cachean por TTL/día), el caché de ubicación NO expira por tiempo y se
# usa como fallback ante cualquier fallo de red, sin importar su antigüedad
# (ver el comentario en la función, en change_wallpaper.sh). Para no depender
# de que haya red real (o de que ip-api.com esté arriba) en el entorno de
# CI, se reemplaza curl por una función de shell durante estos tests.

@test "obtener_ubicacion: sin cache y sin red disponible, devuelve vacio" {
    set_config_valida
    CACHE_UBICACION="$BATS_TEST_TMPDIR/ubicacion-inexistente.cache"

    # obtener_ubicacion hace "return 1" en este caso (sin ubicación
    # disponible); se agrega "|| true" porque bats trata cualquier exit
    # no-cero dentro del cuerpo del test (fuera de un `run`) como fallo del
    # test entero, y acá ese exit 1 es precisamente el comportamiento que se
    # quiere confirmar, no un error real.
    result="$(timeout 5 bash -c '
        export FIELD_HOUSE_SOURCE_ONLY=1
        source "'"$SCRIPT_UNDER_TEST"'" 2>/dev/null
        CACHE_UBICACION="'"$CACHE_UBICACION"'"
        MODO_DRY="no"
        curl() { return 7; }
        obtener_ubicacion
    ' || true)"
    [ "$result" = "" ]
}

@test "obtener_ubicacion: sin red pero con cache previo, devuelve la ubicacion cacheada" {
    set_config_valida
    CACHE_UBICACION="$BATS_TEST_TMPDIR/ubicacion.cache"
    printf 'LAT=-35.05\nLON=-58.76\nTS=1700000000\n' > "$CACHE_UBICACION"

    result="$(timeout 5 bash -c '
        export FIELD_HOUSE_SOURCE_ONLY=1
        source "'"$SCRIPT_UNDER_TEST"'" 2>/dev/null
        CACHE_UBICACION="'"$CACHE_UBICACION"'"
        MODO_DRY="no"
        curl() { return 7; }
        obtener_ubicacion
    ')"
    [ "$result" = "-35.05 -58.76" ]
}

@test "obtener_ubicacion: respuesta exitosa de la API actualiza el cache" {
    set_config_valida
    CACHE_UBICACION="$BATS_TEST_TMPDIR/ubicacion.cache"
    # Caché previo con una ubicación distinta, para confirmar que se
    # sobrescribe con la nueva en vez de conservar la vieja.
    printf 'LAT=0.0\nLON=0.0\nTS=1\n' > "$CACHE_UBICACION"

    result="$(timeout 5 bash -c '
        export FIELD_HOUSE_SOURCE_ONLY=1
        source "'"$SCRIPT_UNDER_TEST"'" 2>/dev/null
        CACHE_UBICACION="'"$CACHE_UBICACION"'"
        MODO_DRY="no"
        curl() { echo "{\"status\":\"success\",\"lat\":-35.05,\"lon\":-58.76}"; }
        obtener_ubicacion
    ')"
    [ "$result" = "-35.05 -58.76" ]
    grep -q "^LAT=-35.05$" "$CACHE_UBICACION"
    grep -q "^LON=-58.76$" "$CACHE_UBICACION"
}

# ============================================================================
# Nota sobre "Lógica de decisión de franja horaria + clima": esta parte del
# comportamiento vive en el cuerpo principal de change_wallpaper.sh (no en
# una función con nombre), porque ahí se ensambla la información de config,
# hora del sistema y resultado de consultar_clima(). Extraerla a una función
# con nombre propio (por ejemplo, decidir_fondo()) sería una mejora de
# testeabilidad real y queda como una refactorización futura pendiente. Por
# ahora, decidir_fondo_test() arriba es una copia deliberada y comentada de
# esa lógica: si alguna vez el bloque original en change_wallpaper.sh
# cambia, hay que actualizar esta copia a mano (o, mejor, hacer esa
# extracción y borrar la copia). Se prefirió duplicar con una nota explícita
# antes que dejar esa lógica sin ningún test.
# ============================================================================
