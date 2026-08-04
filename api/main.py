"""API del blog: el servicio de en medio.

El navegador nunca habla directamente con PostgreSQL. Habla con esta API, y esta
API es la única que sabe la contraseña de la base de datos. Ese es el reparto de
responsabilidades habitual en cualquier aplicación web:

    navegador  ->  ui (Caddy)  ->  api (esto)  ->  db (PostgreSQL)

Fíjate en un detalle importante: en la cadena de arriba no aparece ninguna
dirección IP. Esta API se conecta a un servidor llamado "db" a secas, porque
Docker Compose crea una red privada donde cada servicio es alcanzable por su
nombre. Es el DNS interno de Compose y te ahorra tener que averiguar IPs que
además cambian en cada arranque.
"""

import os
from datetime import datetime

import psycopg
from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from psycopg.rows import dict_row
from pydantic import BaseModel, Field

# La cadena de conexión llega desde fuera, como variable de entorno definida en
# el docker-compose.yml. Nunca se escribe dentro del código: así la misma imagen
# sirve para desarrollo, para pruebas y para producción, cambiando solo el
# entorno. Es uno de los principios de las "12-factor apps".
DATABASE_URL = os.getenv("DATABASE_URL")

app = FastAPI(
    title="API del Blog · Bootcamperu",
    description="Servicio que lee y escribe las entradas del blog en PostgreSQL.",
    version="1.0.0",
)


# =============================================================================
#  Modelos
# =============================================================================
# Pydantic revisa los datos que entran ANTES de que lleguen a nuestra lógica.
# Aquí es donde se valida lo que manda el navegador, que es territorio hostil:
# cualquiera puede enviar un JSON a mano con curl y saltarse el formulario.


class PostNuevo(BaseModel):
    """Lo que el navegador envía para crear una entrada."""

    # min_length=1 rechaza cadenas vacías; max_length=200 coincide con el
    # VARCHAR(200) de la tabla. Si no lo pusiéramos, un título demasiado largo
    # llegaría hasta PostgreSQL y reventaría con un error feo de base de datos
    # en vez de con un mensaje claro.
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=5000)


class Post(BaseModel):
    """Lo que la API devuelve al navegador."""

    id: int
    title: str
    content: str
    created_at: datetime


# =============================================================================
#  Conexión a la base de datos
# =============================================================================


def conectar() -> psycopg.Connection:
    """Abre una conexión nueva a PostgreSQL.

    Abrimos y cerramos una conexión en cada petición. Para una clase es lo más
    fácil de seguir: se ve exactamente dónde empieza y dónde acaba. Una
    aplicación con tráfico real usaría un pool de conexiones (psycopg_pool) para
    no pagar el coste de reconectar una y otra vez.
    """
    if not DATABASE_URL:
        raise RuntimeError("La variable de entorno DATABASE_URL no está definida")

    # row_factory=dict_row hace que cada fila llegue como diccionario
    # ({"id": 1, "title": ...}) en lugar de como tupla ((1, "...")). Así se
    # convierte sola a JSON y el código se lee mucho mejor.
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


@app.exception_handler(psycopg.OperationalError)
async def base_de_datos_caida(_request, exc: psycopg.OperationalError) -> JSONResponse:
    """Traduce "no puedo hablar con la base de datos" a un 503 claro.

    Sin este manejador, cualquier problema de conexión saldría como un 500
    genérico con el volcado de error de psycopg. Un 503 ("servicio no
    disponible") le dice al cliente algo mucho más útil: la culpa no es de tu
    petición, es que ahora mismo no podemos atenderte, prueba más tarde.
    """
    return JSONResponse(
        status_code=503,
        content={
            "detalle": "No se pudo conectar a la base de datos",
            "error": str(exc).strip(),
        },
    )


# =============================================================================
#  Endpoints de salud
# =============================================================================
# Hay dos, y la diferencia importa.


@app.get("/health")
def salud() -> dict[str, str]:
    """¿Está viva la API? No toca la base de datos a propósito.

    Este es el que usa el healthcheck de Docker. Si aquí dentro consultáramos
    PostgreSQL, un problema pasajero de la base marcaría como "unhealthy" a una
    API que funciona perfectamente, y Docker la reiniciaría sin motivo.
    Una cosa es estar vivo y otra distinta es que tus dependencias lo estén.
    """
    return {"api": "ok"}


@app.get("/health/db")
def salud_base_de_datos(response: Response) -> dict[str, str]:
    """¿Puede la API hablar con la base de datos?

    Este sí consulta PostgreSQL, y es el que pinta los dos puntitos de estado
    de la interfaz. Devuelve 503 cuando la base no responde, pero siempre con un
    cuerpo JSON legible para que el navegador pueda mostrar qué falla.
    """
    try:
        with conectar() as conexion:
            # SELECT 1 es la consulta más barata que existe: no lee ninguna
            # tabla. Solo comprueba que hay alguien al otro lado del cable.
            conexion.execute("SELECT 1")
    except Exception:
        response.status_code = 503
        return {"api": "ok", "db": "error"}

    return {"api": "ok", "db": "ok"}


# =============================================================================
#  Endpoints del blog
# =============================================================================


@app.get("/")
def raiz() -> dict[str, object]:
    """Pequeña portada de la API, útil para comprobar que responde."""
    return {
        "nombre": "API del Blog · Bootcamperu",
        "documentacion": "/docs",
        "endpoints": ["/health", "/health/db", "/posts"],
    }


@app.get("/posts")
def listar_posts() -> list[Post]:
    """Devuelve todas las entradas, de la más reciente a la más antigua."""
    with conectar() as conexion:
        filas = conexion.execute(
            """
            SELECT id, title, content, created_at
            FROM posts
            ORDER BY created_at DESC
            """
        ).fetchall()

    return filas


@app.post("/posts", status_code=201)
def crear_post(nuevo: PostNuevo) -> Post:
    """Guarda una entrada nueva y la devuelve ya con su id y su fecha.

    El código 201 ("Created") es el correcto al crear un recurso, en vez del
    200 genérico.
    """
    with conectar() as conexion:
        # Los %s NO son formateo de texto de Python: son parámetros que viajan
        # aparte de la consulta. psycopg se los pasa a PostgreSQL por separado,
        # así que lo que escriba el usuario jamás se interpreta como SQL.
        # Escribir la consulta con un f-string sería la puerta de entrada
        # clásica a una inyección SQL.
        fila = conexion.execute(
            """
            INSERT INTO posts (title, content)
            VALUES (%s, %s)
            RETURNING id, title, content, created_at
            """,
            (nuevo.title, nuevo.content),
        ).fetchone()

    # Al salir del "with" psycopg hace COMMIT automáticamente. Si hubiera saltado
    # una excepción dentro del bloque, haría ROLLBACK y no se guardaría nada a
    # medias.
    return fila
