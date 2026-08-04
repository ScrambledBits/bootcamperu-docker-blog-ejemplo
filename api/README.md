# api

Servicio de backend del blog: FastAPI + psycopg 3 sobre PostgreSQL.

La documentación del ejercicio completo está en el [README de la raíz](../README.md).

## Trabajar solo en la API

```bash
uv sync                                  # instalar dependencias
uv run uvicorn main:app --reload         # servidor de desarrollo
```

Necesita la variable `DATABASE_URL`. Lo más cómodo es levantar únicamente la
base de datos con Docker y publicar su puerto:

```bash
docker compose up -d db
export DATABASE_URL='postgres://bootcamperu:mipassword1234@localhost:5432/bootcamperu'
```

(Para que eso funcione hay que publicar el puerto de `db` en el
`docker-compose.yml`, que por defecto está cerrado al exterior.)

## Endpoints

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/health` | Vida del servicio. No consulta la base de datos |
| `GET` | `/health/db` | Comprueba la conexión. 503 si la base no responde |
| `GET` | `/posts` | Lista las entradas, más recientes primero |
| `POST` | `/posts` | Crea una entrada. 201, o 422 si los datos no son válidos |

Con el servidor en marcha, FastAPI genera la documentación interactiva en
`/docs`.

## Dos imágenes

- `Dockerfile` — una sola etapa, pensada para leerse y entenderse.
- `Dockerfile.optimizado` — multi-etapa, usuario sin privilegios, sin `uv` en la
  imagen final. Alrededor de un 40 % más ligera.
