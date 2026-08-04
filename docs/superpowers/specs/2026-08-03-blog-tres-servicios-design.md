# Blog en tres servicios — diseño

**Fecha:** 2026-08-03
**Contexto:** Ejercicio de Docker del Bootcamp DevOps de Bootcamperu
**Estado:** implementado y verificado

## Problema

El ejemplo era una única API de FastAPI con un endpoint que comprobaba la
conexión a PostgreSQL. Servía para enseñar `docker build` y poco más: con dos
servicios y una sola llamada, no aparecen las preguntas que de verdad surgen al
componer una aplicación (orden de arranque, descubrimiento de servicios, CORS,
persistencia).

Objetivo: convertirlo en una aplicación de tres servicios —interfaz, API y base
de datos— con un esquema que se cree solo y un arranque ordenado, manteniendo
el foco en Docker y no en un framework de frontend.

## Decisiones

| Decisión | Elegido | Descartado y por qué |
|---|---|---|
| Stack de la interfaz | HTML/CSS/JS estático servido por Caddy | Astro/Nuxt: el `npm install` y el paso de build compiten con la lección de Docker. Jinja en Python: los tres servicios dejan de ser un stack políglota realista. |
| Acceso a la API | Proxy inverso en Caddy (`/api/*`) | CORS con `CORSMiddleware`: funciona, pero publica dos puertos y es la disposición menos parecida a producción. |
| Creación del esquema | `/docker-entrypoint-initdb.d` | Alembic u otra herramienta de migraciones: desproporcionado para una tabla. La imagen de Postgres ya trae la función. |
| Credenciales | En el `docker-compose.yml` | Un `.env` era una opción; se deja como ejercicio 5 del README para no añadir un concepto más de golpe. |
| Identificadores | Inglés (`posts`, `title`, `created_at`) | Coherencia con el `main.py` que ya existía. Comentarios y textos de interfaz en español. |
| Dockerfiles | Uno didáctico y uno optimizado por servicio | Sigue el patrón que ya usa `ejemplo_nuxt/` en el mismo repositorio de clase. |

## Arquitectura

```
navegador → :9988 → ui (Caddy) ──/api/*──→ api (FastAPI) ──→ db (PostgreSQL 18)
                    estáticos              :8000              :5432
                    + proxy                                   volumen db_data
```

Solo `ui` publica puerto. `api` y `db` son alcanzables únicamente dentro de la
red de Compose, por nombre de servicio.

Cadena de arranque: `db` sana → `api` sana → `ui`.

## Hallazgos verificados durante el diseño

Dos suposiciones se comprobaron empíricamente antes de escribir código. Una
resultó falsa.

### 1. El healthcheck ingenuo da un falso positivo (confirmado)

`pg_isready` sin `-h` consulta el socket de Unix. Durante la inicialización,
PostgreSQL levanta un servidor temporal que escucha **solo** en ese socket
(`listen_addresses=''`), así que responde afirmativamente mientras los scripts
de `/docker-entrypoint-initdb.d` todavía se están ejecutando.

Medición con un script de inicialización con `pg_sleep(12)`:

```
 4s | socket: accepting connections | tcp: no response | tabla: ausente  ← falso listo
13s | socket: accepting connections | tcp: no response | tabla: ausente
14s | socket: rejecting connections     (el servidor temporal se apaga)
+1s | tcp: accepting connections | tabla: presente                      ← listo real
```

**Decisión:** el healthcheck fuerza TCP con `-h 127.0.0.1`.

### 2. El montaje del volumen NO estaba roto (suposición refutada)

La hipótesis inicial era que `db_data:/var/lib/postgresql` no persistía y había
que cambiarlo a `/var/lib/postgresql/data`. Es falso para esta imagen:

- La imagen es PostgreSQL **18.4**.
- Declara `VOLUME /var/lib/postgresql` (no `/data`).
- `PGDATA=/var/lib/postgresql/18/docker`.
- Prueba de persistencia con `down` (sin `-v`) + `up`: el dato sobrevive.

**Decisión:** el montaje se queda como estaba. Aplicar el consejo antiguo
habría *introducido* el fallo. Queda documentado en el README y en los
comentarios del `docker-compose.yml`.

## Componentes

### db

`db/init/01-esquema.sql` crea la tabla `posts` (`id`, `title`, `content`,
`created_at`), un índice sobre `created_at DESC` y tres entradas de ejemplo
para que la pantalla no aparezca vacía en el primer arranque.

Healthcheck: `pg_isready -h 127.0.0.1`, `interval: 2s`, `retries: 15`.

### api

| Endpoint | Propósito |
|---|---|
| `GET /health` | Vida. No consulta la base a propósito. |
| `GET /health/db` | Disponibilidad incluida la base. 503 si falla. |
| `GET /posts` | Listado, más recientes primero. |
| `POST /posts` | Creación. 201, o 422 si Pydantic rechaza los datos. |

Los dos endpoints de salud están separados para que un problema puntual de la
base no marque como `unhealthy` a una API sana y provoque reinicios inútiles.

Un manejador de `psycopg.OperationalError` traduce los fallos de conexión a un
503 con cuerpo legible en vez de un 500 con volcado de psycopg.

Conexión por petición mediante `with psycopg.connect(...)`, que hace COMMIT al
salir y ROLLBACK si hay excepción. Un pool sería lo correcto con tráfico real;
para la clase, una conexión por petición se lee mejor.

### ui

Caddy sirve `public/` y reenvía `/api/*` a `api:8000` quitando el prefijo.

JavaScript sin dependencias (~250 líneas con comentarios): carga las entradas,
envía el formulario y consulta el estado cada 10 segundos. El DOM se construye
con `createElement` y `textContent`, nunca con `innerHTML`, de modo que el
contenido publicado no puede ejecutarse.

Identidad visual tomada de los tokens oficiales de la marca
(`bootcamperu-skill/references/brand-tokens.md`): teal `#0f766e` para lo
conceptual, naranja `#c2410c` para lo accionable, azul `#1647fb` reservado al
logo. El `viewBox` de `logo-full.svg` se recortó al área real del trazo
(el original desperdiciaba el 87 % del lienzo en vertical); no se alteró ni el
color ni la proporción del dibujo.

## Verificación

`verificar.sh` levanta la aplicación desde cero y ejecuta 13 comprobaciones:
orden de arranque, archivos estáticos, proxy, esquema sembrado, creación de
entradas, validación y persistencia tras `down`/`up`.

Comprobado además a mano:

- Cadena de arranque: `db Healthy → api Healthy → ui Started`.
- Intento de inyección SQL almacenado como texto literal; la tabla sobrevive.
- Con `db` parada: `/health` sigue dando 200, `/health/db` da 503, `/posts` da
  503 con mensaje en español, y el contenedor `api` permanece `healthy`.
- Interfaz revisada en navegador, sin errores de consola, incluido el estado
  degradado.

## Fuera de alcance

Editar y borrar entradas, paginación, autenticación, pool de conexiones,
`.env` para credenciales y despliegue real. Cada uno añadiría un concepto que
compite con la lección de Docker.
