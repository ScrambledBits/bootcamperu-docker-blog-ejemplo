# Blog en tres contenedores

Ejemplo del **Bootcamp DevOps de Bootcamperu** para aprender Docker y Docker
Compose con algo que se parece a una aplicación de verdad: un blog sencillo
donde puedes leer entradas y publicar las tuyas.

No es un "hola mundo". Son tres servicios separados que tienen que encontrarse,
esperarse y hablar entre ellos, que es justo donde están las dudas interesantes.

```
                        tu máquina
                            │
                     puerto 9988
                            │
   ┌────────────────────────▼──────────────────────────────────────┐
   │                  red privada de Compose                       │
   │                                                               │
   │   ┌──────────┐        ┌──────────┐        ┌──────────┐        │
   │   │    ui    │  /api  │   api    │  SQL   │    db    │        │
   │   │  Caddy   │───────▶│ FastAPI  │───────▶│ Postgres │        │
   │   │   :80    │        │  :8000   │        │  :5432   │        │
   │   └──────────┘        └──────────┘        └──────────┘        │
   │    estáticos           Python 3.14          volumen           │
   │    + proxy             + psycopg            db_data           │
   └───────────────────────────────────────────────────────────────┘
```

Solo `ui` está abierto al exterior. `api` y `db` viven puertas adentro y se
llaman por su nombre de servicio, sin IPs.

## Arrancar

```bash
docker compose up --build
```

Y abre <http://localhost:9988>.

La primera vez tarda un poco más porque tiene que descargar las imágenes y
construir. Verás en la salida cómo Compose espera: `db Healthy` → `api Healthy`
→ `ui Started`.

Para pararlo:

```bash
docker compose down      # para todo, conserva las entradas publicadas
docker compose down -v   # para todo y borra la base de datos
```

## Comprobar que todo funciona

```bash
./verificar.sh
```

Levanta la aplicación desde cero y pasa 13 comprobaciones: orden de arranque,
archivos servidos, proxy, esquema creado, creación de entradas, validación y
persistencia. Si algo se rompe al tocar el proyecto, este script lo dice.

## Qué hay en cada carpeta

| Ruta | Qué es |
|---|---|
| `docker-compose.yml` | La aplicación completa: los tres servicios y cómo se relacionan |
| `db/init/01-esquema.sql` | La tabla y las entradas de ejemplo. Se ejecuta solo la primera vez |
| `api/main.py` | La API: lee y escribe entradas en PostgreSQL |
| `api/Dockerfile` | Imagen de la API, versión para entender |
| `api/Dockerfile.optimizado` | La misma, con buenas prácticas de producción |
| `ui/Caddyfile` | Configuración del servidor web y del proxy hacia la API |
| `ui/public/` | El HTML, el CSS y el JavaScript que ve el navegador |
| `ui/Dockerfile` | Imagen de la interfaz, versión para entender |
| `ui/Dockerfile.optimizado` | La misma, con usuario sin privilegios |
| `verificar.sh` | Comprobación automática de que los tres servicios funcionan juntos |

## Las cuatro ideas que enseña este ejemplo

### 1. Arrancar no es lo mismo que estar listo

Es el error más común al montar varios servicios. `depends_on` a secas solo
espera a que el contenedor **arranque**, cosa que ocurre en milisegundos. Pero
PostgreSQL necesita unos segundos más antes de aceptar conexiones, así que la
API arranca, intenta conectarse y se estrella.

La solución son los *healthchecks*: `db` declara cómo se comprueba que está
lista, y `api` declara que espera a esa condición, no al arranque:

```yaml
depends_on:
  db:
    condition: service_healthy
```

**Y hay una trampa dentro de la trampa.** El healthcheck de la base de datos es
este:

```yaml
test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U bootcamperu -d bootcamperu"]
```

Ese `-h 127.0.0.1` parece que sobra, pero es lo que hace que funcione. Cuando
PostgreSQL crea la base por primera vez, levanta un servidor **temporal** para
ejecutar los scripts de inicialización, y ese servidor escucha únicamente en el
socket de Unix. Sin `-h`, `pg_isready` pregunta por el socket, el servidor
temporal contesta "acepto conexiones" y Docker da la base por lista **mientras
el esquema todavía se está creando**.

Medido en esta misma máquina, con un script de inicialización lento a propósito:

```
 4s | socket: accepting connections | tcp: no response | tabla: no existe  ← falso listo
13s | socket: accepting connections | tcp: no response | tabla: no existe
14s | socket: rejecting connections     (el servidor temporal se apaga)
15s | tcp: accepting connections | tabla: existe                          ← listo de verdad
```

Al forzar TCP solo hay respuesta cuando el servidor definitivo está en pie, es
decir, cuando el esquema ya está creado.

### 2. Los servicios se llaman por su nombre

Dentro de la red de Compose no hacen falta direcciones IP. El nombre del
servicio funciona como nombre de máquina:

- la API se conecta a `db:5432`
- Caddy reenvía a `api:8000`

Compruébalo desde dentro de un contenedor:

```bash
docker compose exec ui wget -qO- http://api:8000/health
```

### 3. Un proxy evita el problema de CORS

El JavaScript del navegador nunca llama a `http://localhost:8000`. Llama a
`/api/posts`, sin servidor ni puerto. Caddy reconoce el prefijo, lo quita y
reenvía la petición a la API:

```caddy
handle /api/* {
    uri strip_prefix /api
    reverse_proxy api:8000
}
```

Para el navegador solo existe un origen, así que CORS ni aparece. Es además
como se monta en producción.

### 4. Los volúmenes guardan lo que el contenedor no

Un contenedor es desechable. Su disco se va con él. Por eso la base de datos
escribe en un volumen con nombre que vive aparte:

```bash
# Publica una entrada desde la web, y luego:
docker compose down
docker compose up -d
# La entrada sigue ahí.

docker compose down -v
docker compose up -d
# Ahora sí: vuelta a las tres entradas de ejemplo.
```

Un detalle que cambió hace poco y despista mucho: **PostgreSQL 18 guarda los
datos en `/var/lib/postgresql/18/docker`**, no en `/var/lib/postgresql/data`
como las versiones anteriores. Aquí montamos la carpeta padre
(`/var/lib/postgresql`), que es la que la imagen declara como volumen. Si copias
la línea `db_data:/var/lib/postgresql/data` de un tutorial antiguo, con esta
versión ya no vale.

## Ejercicios propuestos

1. **Rompe el healthcheck a propósito.** Quita el `-h 127.0.0.1` del
   `docker-compose.yml`, haz `docker compose down -v` y vuelve a levantar.
   Añade `SELECT pg_sleep(10);` al principio de `db/init/01-esquema.sql` para
   que se note. ¿Qué error da ahora la API?

2. **Compara las imágenes.** Construye las dos versiones y mira el tamaño:

   ```bash
   docker build -t blog-api:simple ./api
   docker build -f api/Dockerfile.optimizado -t blog-api:opt ./api
   docker images blog-api
   ```

3. **Apaga la base de datos con la web abierta.** `docker compose stop db` y
   mira la página: el punto de `db` se pone naranja y aparece el aviso, pero la
   API sigue sana. ¿Por qué no la reinicia Docker? (Pista: mira los dos
   endpoints de salud en `api/main.py`.)

4. **Publica una entrada sin navegador**, para ver que la API es independiente
   de la interfaz:

   ```bash
   curl -X POST http://localhost:9988/api/posts \
     -H 'Content-Type: application/json' \
     -d '{"title":"Desde la terminal","content":"Sin abrir el navegador."}'
   ```

5. **Saca la contraseña del `docker-compose.yml`** a un archivo `.env` y añade
   `.env` al `.gitignore`. Es el primer paso hacia una gestión seria de
   secretos.

## Endpoints de la API

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/health` | ¿Está viva la API? No consulta la base de datos |
| `GET` | `/health/db` | ¿Puede la API hablar con la base? Devuelve 503 si no |
| `GET` | `/posts` | Lista las entradas, de la más nueva a la más vieja |
| `POST` | `/posts` | Crea una entrada. Devuelve 201, o 422 si los datos no valen |

Desde el navegador se llega a todos con el prefijo `/api`
(`http://localhost:9988/api/posts`).

## Herramientas

- **Python 3.14** con [FastAPI](https://fastapi.tiangolo.com) y
  [psycopg 3](https://www.psycopg.org/psycopg3/docs/)
- **[uv](https://docs.astral.sh/uv/)** para las dependencias de Python
  (`uv.lock`, nada de `pip install` suelto)
- **[Caddy](https://caddyserver.com/docs/)** como servidor web y proxy
- **PostgreSQL 18**

Trabajar en la API fuera de Docker:

```bash
cd api
uv sync
uv run uvicorn main:app --reload
```

Necesitarás una `DATABASE_URL` apuntando a una base accesible. Lo más cómodo es
levantar solo la base con `docker compose up -d db` y publicar su puerto.
