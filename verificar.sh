#!/usr/bin/env bash
#
# =============================================================================
#  verificar.sh — comprueba que los tres servicios funcionan juntos
# =============================================================================
#  Levanta la aplicación desde cero y va comprobando una a una las cosas que
#  tienen que cumplirse. Si algo falla, el script se detiene y te dice qué era.
#
#  Úsalo como red de seguridad después de tocar algo, o en clase para enseñar
#  la aplicación entera funcionando sin ir abriendo pestañas.
#
#      ./verificar.sh
#
#  Ojo: empieza borrando el volumen, así que las entradas que hayas publicado
#  se pierden. Es a propósito: queremos comprobar el arranque limpio.
# =============================================================================

# errexit  : corta el script en cuanto un comando falla
# nounset  : error si usamos una variable que no existe (una errata al escribir
#            el nombre deja de pasar desapercibida)
# pipefail : una tubería falla si falla cualquier parte, no solo la última
set -o errexit -o nounset -o pipefail

readonly BASE_URL="http://localhost:9988"
readonly ESPERA_MAXIMA=60

# Contadores de resultados
fallos=0
comprobaciones=0

# ---- Salida por pantalla ----------------------------------------------------
# printf en lugar de echo: echo se comporta distinto según el sistema y el shell
# cuando el texto lleva barras invertidas o empieza por guion.

info() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok() { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
error() { printf '  \033[0;31m✗\033[0m %s\n' "$*" >&2; }

# Comprueba que dos valores coinciden y lleva la cuenta.
comprobar() {
    local descripcion="$1"
    local esperado="$2"
    local obtenido="$3"

    comprobaciones=$((comprobaciones + 1))

    if [[ "${esperado}" == "${obtenido}" ]]; then
        ok "${descripcion}"
    else
        error "${descripcion} — esperaba '${esperado}', recibí '${obtenido}'"
        fallos=$((fallos + 1))
    fi
}

# Devuelve solo el código HTTP de una petición.
codigo_http() {
    curl -s -o /dev/null -w '%{http_code}' "$@"
}

# Espera a que la aplicación conteste, hasta un máximo de segundos.
esperar_a_que_arranque() {
    local segundos=0
    while [[ "${segundos}" -lt "${ESPERA_MAXIMA}" ]]; do
        if curl -sf "${BASE_URL}/api/health" >/dev/null 2>&1; then
            ok "la aplicación responde (${segundos}s)"
            return 0
        fi
        sleep 1
        segundos=$((segundos + 1))
    done

    error "la aplicación no respondió en ${ESPERA_MAXIMA}s"
    docker compose ps
    docker compose logs --tail 40
    return 1
}

# Nos aseguramos de trabajar en la carpeta del proyecto, aunque llamen al script
# desde otro sitio. BASH_SOURCE[0] es la ruta de este mismo archivo.
cd "$(dirname "${BASH_SOURCE[0]}")"

# =============================================================================
info "1/7 · Arrancando desde cero (se borra el volumen)"
# =============================================================================
docker compose down -v >/dev/null 2>&1 || true
docker compose up -d --build >/dev/null
esperar_a_que_arranque

# =============================================================================
info "2/7 · Orden de arranque"
# =============================================================================
# Si el orden falla, la API habría arrancado antes de que existiera la tabla y
# las comprobaciones de abajo lo delatarían. Aquí solo confirmamos el estado.
comprobar "la base de datos está sana" \
    "healthy" "$(docker inspect --format '{{.State.Health.Status}}' "$(docker compose ps -q db)")"
comprobar "la api está sana" \
    "healthy" "$(docker inspect --format '{{.State.Health.Status}}' "$(docker compose ps -q api)")"

# =============================================================================
info "3/7 · La interfaz se sirve correctamente"
# =============================================================================
comprobar "GET /" "200" "$(codigo_http "${BASE_URL}/")"
comprobar "GET /estilos.css" "200" "$(codigo_http "${BASE_URL}/estilos.css")"
comprobar "GET /app.js" "200" "$(codigo_http "${BASE_URL}/app.js")"
comprobar "GET /logo-full.svg" "200" "$(codigo_http "${BASE_URL}/logo-full.svg")"

# =============================================================================
info "4/7 · Caddy reenvía /api a la API"
# =============================================================================
comprobar "GET /api/health" \
    '{"api":"ok"}' "$(curl -s "${BASE_URL}/api/health")"
comprobar "GET /api/health/db" \
    '{"api":"ok","db":"ok"}' "$(curl -s "${BASE_URL}/api/health/db")"

# =============================================================================
info "5/7 · El esquema se creó solo, con sus entradas de ejemplo"
# =============================================================================
# Esta es la comprobación que demuestra que el healthcheck hizo su trabajo: si
# la API hubiera arrancado antes de tiempo, la tabla no existiría.
entradas_iniciales="$(curl -s "${BASE_URL}/api/posts" | grep -o '"id"' | wc -l | tr -d ' ')"
comprobar "hay 3 entradas de ejemplo" "3" "${entradas_iniciales}"

# =============================================================================
info "6/7 · Crear una entrada y volver a leerla"
# =============================================================================
titulo="Comprobación automática"

comprobar "POST /api/posts devuelve 201" "201" \
    "$(codigo_http -X POST "${BASE_URL}/api/posts" \
        -H 'Content-Type: application/json' \
        -d "{\"title\":\"${titulo}\",\"content\":\"Entrada creada por verificar.sh\"}")"

if curl -s "${BASE_URL}/api/posts" | grep -q "${titulo}"; then
    ok "la entrada aparece en el listado"
else
    error "la entrada no aparece en el listado"
    fallos=$((fallos + 1))
fi
comprobaciones=$((comprobaciones + 1))

# La validación tiene que rechazar lo que no vale.
comprobar "un título vacío se rechaza con 422" "422" \
    "$(codigo_http -X POST "${BASE_URL}/api/posts" \
        -H 'Content-Type: application/json' \
        -d '{"title":"","content":"x"}')"

# =============================================================================
info "7/7 · Los datos sobreviven a un reinicio"
# =============================================================================
docker compose down >/dev/null 2>&1
docker compose up -d >/dev/null
esperar_a_que_arranque

if curl -s "${BASE_URL}/api/posts" | grep -q "${titulo}"; then
    ok "la entrada sigue ahí después de down + up"
else
    error "los datos se perdieron: revisa el volumen db_data"
    fallos=$((fallos + 1))
fi
comprobaciones=$((comprobaciones + 1))

# =============================================================================
#  Resumen
# =============================================================================
printf '\n'
if [[ "${fallos}" -eq 0 ]]; then
    printf '\033[0;32m════ %s/%s comprobaciones correctas ════\033[0m\n' \
        "${comprobaciones}" "${comprobaciones}"
    printf 'La aplicación está en marcha: %s\n\n' "${BASE_URL}"
    exit 0
fi

printf '\033[0;31m════ %s de %s comprobaciones han fallado ════\033[0m\n\n' \
    "${fallos}" "${comprobaciones}"
exit 1
