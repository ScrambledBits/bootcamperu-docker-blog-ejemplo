# =============================================================================
#  Imagen de la interfaz (versión didáctica)
# =============================================================================
#  La imagen más sencilla de las tres, y por un buen motivo: aquí no hay nada
#  que compilar. El HTML, el CSS y el JavaScript se sirven tal cual se escriben.
#
#  Compáralo con caddy/ y ejemplo_nuxt/, donde hay que ejecutar npm install y
#  npm run build antes de tener algo que servir. Cuando el proyecto no necesita
#  un paso de construcción, no se lo inventes.
#
#  Construir solo esta imagen, desde la carpeta ui/:
#      docker build -t blog-ui .
# =============================================================================

# Caddy sobre Alpine: unos 50 MB con el servidor web ya dentro.
# Versión fijada, igual que en los otros servicios.
FROM caddy:2.11.4-alpine

# La configuración del servidor: qué sirve y qué reenvía a la API.
COPY Caddyfile /etc/caddy/Caddyfile

# Los archivos que verá el navegador. En el Caddyfile hemos puesto
# "root * /srv", así que esta es la carpeta desde donde Caddy sirve.
COPY public/ /srv/

# Caddy escucha en el 80 por defecto, y así lo hemos configurado.
EXPOSE 80

# No hace falta CMD: la imagen oficial de Caddy ya trae el suyo, que arranca el
# servidor leyendo /etc/caddy/Caddyfile. Cuando la imagen base hace justo lo que
# necesitas, lo mejor es no repetirlo.
