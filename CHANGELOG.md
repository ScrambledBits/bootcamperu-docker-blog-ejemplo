# Registro de cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [2.0.0] — 2026-08-03

El ejemplo pasa de ser una única API a una aplicación de tres servicios.

### Añadido

- **Servicio `ui`**: interfaz del blog servida por Caddy. HTML, CSS y
  JavaScript sin frameworks ni paso de compilación.
  - Diseño con los colores y el logo oficiales de Bootcamperu.
  - Panel de estado que consulta `/api/health/db` cada 10 segundos y muestra en
    vivo si la API y la base de datos responden.
  - Caddy hace de proxy: `/api/*` va al servicio `api`, así que no hay CORS.
- **Servicio `db`**: esquema inicial en `db/init/01-esquema.sql`, ejecutado
  automáticamente por la imagen de PostgreSQL en el primer arranque. Crea la
  tabla `posts` y tres entradas de ejemplo.
- **Endpoints nuevos** en la API: `GET /health`, `GET /health/db`,
  `GET /posts` y `POST /posts` con validación por Pydantic.
- **Cadena de arranque ordenada**: `db` sana → `api` sana → `ui`, con
  healthchecks en los tres servicios.
- `Dockerfile.optimizado` para `api` y para `ui`: multi-etapa, usuario sin
  privilegios y healthcheck incluido en la imagen.
- `verificar.sh`: 13 comprobaciones automáticas de la aplicación completa.
- `README.md` con diagrama de arquitectura y cinco ejercicios propuestos.
- `.dockerignore` en `api/` y en `ui/`. El de `api/` excluye `.venv`, que antes
  viajaba entero en cada construcción.

### Cambiado

- El `Dockerfile` de la raíz se ha movido a `api/Dockerfile`. Ahora cada
  servicio tiene su propio contexto de construcción.
- La instalación de dependencias ya no usa `pip`, sino `uv sync --locked` a
  partir de `uv.lock`.
- `api/main.py` reescrito: gestión de errores con un manejador de
  `psycopg.OperationalError` que devuelve 503, consultas parametrizadas y
  filas como diccionarios.
- Todos los archivos del proyecto llevan comentarios en español pensados para
  quien está aprendiendo.

### Corregido

- **`psycopg` no encontraba el driver.** El paquete base es Python puro y busca
  `libpq` en el sistema, que la imagen de Alpine no trae. La dependencia pasa a
  ser `psycopg[binary]`, que incluye la extensión compilada.
- **El healthcheck de la base daba "listo" antes de tiempo.** `pg_isready` a
  través del socket de Unix responde afirmativamente mientras se ejecutan los
  scripts de inicialización, porque el servidor temporal de Postgres sí escucha
  ahí. Ahora se fuerza TCP con `-h 127.0.0.1`, que solo responde cuando el
  servidor definitivo está en pie.
- `depends_on` pasa de la forma corta a `condition: service_healthy`. Antes la
  API arrancaba antes que la base y la primera petición fallaba con
  "Connection refused".

### Eliminado

- `api/requirements.txt`: la imagen instala desde `uv.lock` y mantener dos
  listas de dependencias solo genera dudas. Se puede regenerar con
  `uv export --format requirements.txt -o requirements.txt`.

### Nota sobre la versión de PostgreSQL

La imagen usada es PostgreSQL 18, que guarda los datos en
`/var/lib/postgresql/18/docker` en lugar de `/var/lib/postgresql/data`. El
montaje del volumen (`db_data:/var/lib/postgresql`) es el correcto para esta
versión y **no** debe cambiarse por la ruta antigua.

## [1.0.0] — 2026-07-27

- API mínima con FastAPI y un endpoint que comprobaba la conexión a PostgreSQL.
- `docker-compose.yml` con dos servicios: `api` y `db`.
