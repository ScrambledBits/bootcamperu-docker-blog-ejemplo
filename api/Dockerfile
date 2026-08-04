# =============================================================================
#  Imagen de la API (versión didáctica)
# =============================================================================
#  Esta es la versión "para entender": una sola etapa, leída de arriba abajo.
#  Al lado tienes Dockerfile.optimizado, que hace lo mismo con las buenas
#  prácticas que usarías en producción. Compara las dos cuando termines.
#
#  Construir solo esta imagen, desde la carpeta api/:
#      docker build -t blog-api .
# =============================================================================

# Imagen base. Fijamos la versión exacta (3.14.6-alpine3.24) en lugar de usar
# "python:alpine" a secas: así la imagen que construyes hoy es la misma que
# construirá tu compañero la semana que viene. Una etiqueta móvil como "latest"
# es la receta clásica del "en mi máquina funcionaba".
FROM python:3.14.6-alpine3.24

# Traemos el binario de uv desde su imagen oficial. uv es el gestor de paquetes
# de Python que usa este proyecto: instala mucho más rápido que pip y respeta el
# uv.lock al pie de la letra.
# Fíjate en que también aquí fijamos la versión, por el mismo motivo de antes.
COPY --from=ghcr.io/astral-sh/uv:0.11.29 /uv /bin/uv

# Carpeta donde trabajaremos dentro del contenedor. Si no existe, Docker la crea.
WORKDIR /app

# Copiamos PRIMERO solo los archivos de dependencias, antes que el código.
# Esto no es manía, es la optimización más rentable de todo el archivo:
# Docker guarda en caché el resultado de cada instrucción, y solo repite una
# instrucción si algo de lo que depende ha cambiado. Como main.py cambia mucho
# más a menudo que la lista de dependencias, al separarlos conseguimos que
# editar el código NO obligue a reinstalar todo Python otra vez.
COPY pyproject.toml uv.lock ./

# --locked obliga a respetar el uv.lock exactamente: si el lock no cuadra con el
#   pyproject.toml, falla en vez de "arreglarlo" por su cuenta. Es lo que quieres
#   en una imagen, para que la instalación sea reproducible.
# --no-dev deja fuera las dependencias de desarrollo (como black): no pintan
#   nada en la imagen final y solo la harían más grande.
# --no-install-project instala las dependencias pero no el proyecto en sí, que
#   aquí es un único main.py que copiamos justo debajo.
RUN uv sync --locked --no-dev --no-install-project

# Ahora sí, el código de la aplicación. Al ser la última capa, cambiar main.py
# solo invalida esta línea y la reconstrucción tarda menos de un segundo.
COPY main.py .

# uv instala las dependencias en un entorno virtual dentro de /app/.venv.
# Añadiéndolo al PATH podemos escribir "uvicorn" en el CMD sin poner la ruta
# completa, y cualquier "python" que ejecutemos usará ese entorno.
ENV PATH="/app/.venv/bin:$PATH"

# EXPOSE es documentación: le dice a quien lea el archivo (y a Compose) que la
# aplicación escucha en el 8000. Por sí solo NO publica el puerto hacia tu
# máquina; eso se decide en el docker-compose.yml.
EXPOSE 8000

# --host 0.0.0.0 es imprescindible y es un fallo clásico olvidarlo.
# Por defecto uvicorn escucha solo en 127.0.0.1, que dentro de un contenedor
# significa "solo yo mismo": ni Caddy ni tu navegador podrían llegar. Con
# 0.0.0.0 escucha en todas las interfaces de red del contenedor.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
