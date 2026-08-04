-- =============================================================================
--  Esquema inicial del blog
-- =============================================================================
--
--  ¿Quién ejecuta este archivo y cuándo?
--
--  La imagen oficial de PostgreSQL revisa la carpeta /docker-entrypoint-initdb.d
--  la PRIMERA vez que arranca con un directorio de datos vacío. Todos los .sql
--  y .sh que encuentre ahí dentro se ejecutan en orden alfabético (por eso el
--  prefijo "01-"). En el docker-compose.yml montamos ./db/init en esa ruta.
--
--  Ojo con esto, es la duda más común de la clase: el script NO se vuelve a
--  ejecutar en los siguientes arranques. Si el volumen ya tiene datos, Postgres
--  asume que la base ya está inicializada y se salta esta carpeta por completo.
--  ¿Quieres volver a partir de cero? Hay que borrar el volumen:
--
--      docker compose down -v
--
--  Gracias a esto no necesitamos ninguna herramienta de migraciones para un
--  ejemplo de este tamaño: la propia imagen de Postgres ya trae la función.
-- =============================================================================


-- -----------------------------------------------------------------------------
--  Tabla de entradas del blog
-- -----------------------------------------------------------------------------
--  Usamos IF NOT EXISTS por costumbre defensiva. En la práctica este script solo
--  corre una vez, pero así el archivo es seguro de re-ejecutar a mano si algún
--  día lo lanzas tú mismo con psql.
CREATE TABLE IF NOT EXISTS posts (
    -- SERIAL crea automáticamente un contador que se autoincrementa.
    id          SERIAL       PRIMARY KEY,

    -- NOT NULL es una restricción de la propia base de datos. La API también
    -- valida el título, pero dejamos la regla aquí abajo también: si mañana
    -- alguien escribe en la base desde otro programa, la regla se sigue
    -- cumpliendo. La validación más importante es la que está más cerca de los
    -- datos.
    title       VARCHAR(200) NOT NULL,
    content     TEXT         NOT NULL,

    -- TIMESTAMPTZ guarda la fecha junto con la zona horaria. Es lo que quieres
    -- casi siempre: el contenedor puede estar en UTC y tu laptop en Lima, y aun
    -- así el instante que se guarda es el mismo.
    -- DEFAULT NOW() significa que la API no tiene que mandar la fecha, la pone
    -- Postgres sola al insertar.
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- -----------------------------------------------------------------------------
--  Índice para ordenar por fecha
-- -----------------------------------------------------------------------------
--  La pantalla principal siempre pide las entradas de la más nueva a la más
--  vieja (ORDER BY created_at DESC). Sin índice, Postgres tendría que leer la
--  tabla entera y ordenarla en memoria cada vez.
--  Con tres entradas no se nota nada; con tres millones, se nota muchísimo.
CREATE INDEX IF NOT EXISTS posts_created_at_idx ON posts (created_at DESC);


-- -----------------------------------------------------------------------------
--  Datos de ejemplo
-- -----------------------------------------------------------------------------
--  Sembramos tres entradas para que la aplicación NO se vea vacía la primera
--  vez que la abres. Una pantalla en blanco al arrancar siempre genera la misma
--  pregunta: "¿está rota o simplemente no hay nada?".
INSERT INTO posts (title, content) VALUES
    (
        'Hola Docker',
        'Esta entrada vive en PostgreSQL, dentro de un contenedor. La estás leyendo gracias a otros dos contenedores: la API que la consulta y el servidor web que te muestra esta página. Tres piezas separadas trabajando juntas.'
    ),
    (
        'Los volúmenes guardan tus datos',
        'Un contenedor es desechable: si lo borras, todo lo que tenía dentro se va con él. Por eso la base de datos guarda sus archivos en un volumen con nombre, que vive fuera del contenedor. Prueba a hacer "docker compose down" y luego "docker compose up": esta entrada seguirá aquí.'
    ),
    (
        'Esperar no es lo mismo que estar listo',
        'Que un contenedor haya arrancado no significa que ya pueda atender peticiones. PostgreSQL necesita unos segundos para preparar la base antes de aceptar conexiones. Para eso existen los healthchecks: la API no arranca hasta que la base de datos responde de verdad.'
    );
