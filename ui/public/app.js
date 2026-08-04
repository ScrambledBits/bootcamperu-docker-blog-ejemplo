/* =============================================================================
   app.js — todo el JavaScript de la aplicación
   =============================================================================
   JavaScript del navegador, sin frameworks y sin compilar. Este mismo archivo
   es el que Caddy sirve tal cual.

   Lo único que hace es hablar con la API. Fíjate en que todas las direcciones
   empiezan por "/api/..." y ninguna lleva servidor ni puerto: son rutas
   relativas al propio sitio. Caddy ve el prefijo /api, le quita esa parte y
   reenvía la petición al contenedor de la API.

   Ventaja de hacerlo así: este código funciona igual en tu portátil, en el
   ordenador de tu compañero o en un servidor real, sin cambiar una sola línea.
   ============================================================================= */

"use strict";

// Cada cuánto preguntamos por el estado de los servicios.
const MILISEGUNDOS_ENTRE_COMPROBACIONES = 10000;

// Guardamos las referencias a los elementos una sola vez, al cargar la página,
// en lugar de buscarlos en el DOM cada vez que hacen falta.
const elementos = {
  formulario: document.getElementById("formulario"),
  title: document.getElementById("title"),
  content: document.getElementById("content"),
  botonPublicar: document.getElementById("boton-publicar"),
  botonRecargar: document.getElementById("boton-recargar"),
  estadoFormulario: document.getElementById("estado-formulario"),
  lista: document.getElementById("lista"),
  cuenta: document.getElementById("cuenta"),
  aviso: document.getElementById("aviso"),
  puntoApi: document.getElementById("punto-api"),
  puntoDb: document.getElementById("punto-db"),
  valorApi: document.getElementById("valor-api"),
  valorDb: document.getElementById("valor-db"),
  nodoApi: document.getElementById("nodo-api"),
  nodoDb: document.getElementById("nodo-db"),
};

/* -----------------------------------------------------------------------------
   Utilidades
   -------------------------------------------------------------------------- */

/**
 * Muestra u oculta el aviso rojo de la parte de arriba.
 * @param {string} mensaje Texto a mostrar. Cadena vacía para ocultarlo.
 */
function mostrarAviso(mensaje) {
  if (!mensaje) {
    elementos.aviso.hidden = true;
    elementos.aviso.textContent = "";
    return;
  }
  elementos.aviso.textContent = mensaje;
  elementos.aviso.hidden = false;
}

/**
 * Convierte la fecha que manda PostgreSQL a algo legible en español.
 * Llega en formato ISO con zona horaria ("2026-08-03T22:15:00+00:00") y el
 * navegador la traduce sola a la hora local de quien mira la página.
 */
function formatearFecha(textoIso) {
  const fecha = new Date(textoIso);
  if (Number.isNaN(fecha.getTime())) {
    return textoIso;
  }
  return fecha.toLocaleString("es-PE", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Envuelve fetch para dar errores entendibles.
 *
 * fetch tiene una trampa muy conocida: solo falla si no hay red. Si el servidor
 * responde 404 o 503, fetch lo considera un éxito y hay que mirar response.ok
 * a mano. Por eso este envoltorio: para no olvidarlo en cada llamada.
 */
async function pedirJson(ruta, opciones) {
  const respuesta = await fetch(ruta, opciones);

  let datos = null;
  try {
    datos = await respuesta.json();
  } catch {
    // Hay respuestas legítimas sin cuerpo JSON; no es motivo de error todavía.
  }

  if (!respuesta.ok) {
    const detalle =
      (datos && (datos.detalle || datos.detail)) ||
      `El servidor respondió ${respuesta.status}`;
    throw new Error(typeof detalle === "string" ? detalle : JSON.stringify(detalle));
  }

  return datos;
}

/* -----------------------------------------------------------------------------
   Pintar las entradas
   -------------------------------------------------------------------------- */

/**
 * Crea la tarjeta de una entrada.
 *
 * Importante: montamos los elementos con createElement y textContent, NO
 * pegando cadenas con innerHTML. Si alguien publica una entrada titulada
 * "<script>...</script>", con textContent se ve como texto; con innerHTML se
 * ejecutaría. Es la defensa básica contra XSS y sale gratis.
 */
function crearTarjetaEntrada(entrada, esNueva) {
  const articulo = document.createElement("article");
  articulo.className = esNueva ? "entrada entrada--nueva" : "entrada";

  const titulo = document.createElement("h3");
  titulo.className = "entrada__titulo";
  titulo.textContent = entrada.title;

  const fecha = document.createElement("p");
  fecha.className = "entrada__fecha";
  fecha.textContent = formatearFecha(entrada.created_at);

  const contenido = document.createElement("p");
  contenido.className = "entrada__contenido";
  contenido.textContent = entrada.content;

  articulo.append(titulo, fecha, contenido);
  return articulo;
}

/**
 * Vuelca la lista completa de entradas en la página.
 * @param {Array} entradas
 * @param {number|null} idDestacado id de la entrada recién creada, si la hay
 */
function pintarEntradas(entradas, idDestacado) {
  elementos.lista.replaceChildren();
  elementos.cuenta.textContent = `· ${entradas.length}`;

  if (entradas.length === 0) {
    const vacio = document.createElement("p");
    vacio.className = "lista__vacio";
    vacio.textContent = "Todavía no hay entradas. Publica la primera.";
    elementos.lista.append(vacio);
    return;
  }

  // Un fragmento acumula los nodos en memoria y los inserta de una sola vez,
  // en lugar de tocar el documento una vez por entrada.
  const fragmento = document.createDocumentFragment();
  for (const entrada of entradas) {
    fragmento.append(crearTarjetaEntrada(entrada, entrada.id === idDestacado));
  }
  elementos.lista.append(fragmento);
}

/**
 * Pide las entradas a la API y las pinta.
 */
async function cargarEntradas(idDestacado = null) {
  try {
    const entradas = await pedirJson("/api/posts");
    pintarEntradas(entradas, idDestacado);
    mostrarAviso("");
  } catch (error) {
    elementos.lista.replaceChildren();
    elementos.cuenta.textContent = "·";
    mostrarAviso(`No se pudieron cargar las entradas: ${error.message}`);
  }
}

/* -----------------------------------------------------------------------------
   Publicar una entrada
   -------------------------------------------------------------------------- */

function marcarEstadoFormulario(mensaje, tipo) {
  elementos.estadoFormulario.textContent = mensaje;
  elementos.estadoFormulario.className = tipo
    ? `formulario__estado formulario__estado--${tipo}`
    : "formulario__estado";
}

elementos.formulario.addEventListener("submit", async (evento) => {
  // Sin esto el navegador recargaría la página entera al enviar el formulario,
  // que es su comportamiento por defecto desde siempre.
  evento.preventDefault();

  const title = elementos.title.value.trim();
  const content = elementos.content.value.trim();

  // Validación en el navegador: es para dar una respuesta inmediata y cómoda.
  // NO sustituye a la de la API, que es la que de verdad protege los datos:
  // cualquiera puede saltarse esta página y llamar a la API con curl.
  elementos.title.classList.toggle("campo__control--error", !title);
  elementos.content.classList.toggle("campo__control--error", !content);

  if (!title || !content) {
    marcarEstadoFormulario("El título y el contenido son obligatorios.", "error");
    return;
  }

  // Desactivamos el botón mientras se envía para evitar el doble clic que
  // publicaría la misma entrada dos veces.
  elementos.botonPublicar.disabled = true;
  marcarEstadoFormulario("Publicando…", null);

  try {
    const creada = await pedirJson("/api/posts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, content }),
    });

    elementos.formulario.reset();
    marcarEstadoFormulario("Entrada publicada.", "ok");

    // Volvemos a pedir la lista al servidor en lugar de añadir la entrada a
    // mano en el DOM. Así lo que ves es siempre lo que hay en la base de datos.
    await cargarEntradas(creada.id);

    elementos.title.focus();
  } catch (error) {
    marcarEstadoFormulario(`No se pudo publicar: ${error.message}`, "error");
  } finally {
    // finally se ejecuta haya ido bien o mal: el botón nunca se queda colgado.
    elementos.botonPublicar.disabled = false;
  }
});

elementos.botonRecargar.addEventListener("click", () => cargarEntradas());

/* -----------------------------------------------------------------------------
   Estado de los servicios
   -------------------------------------------------------------------------- */

function pintarPunto(punto, valor, nodo, estaBien, textoValor) {
  punto.className = `punto punto--${estaBien ? "ok" : "error"}`;
  valor.textContent = textoValor;
  nodo.classList.toggle("cadena__nodo--activo", estaBien);
  nodo.classList.toggle("cadena__nodo--caido", !estaBien);
}

/**
 * Pregunta a /api/health/db y enciende los dos puntitos.
 *
 * Este endpoint devuelve 503 cuando la base de datos no responde, pero SIEMPRE
 * con un cuerpo JSON legible. Por eso aquí usamos fetch directamente en vez de
 * pedirJson: nos interesa leer el cuerpo tanto si el código es 200 como si es
 * 503.
 */
async function comprobarEstado() {
  try {
    const respuesta = await fetch("/api/health/db");
    const datos = await respuesta.json();

    pintarPunto(
      elementos.puntoApi,
      elementos.valorApi,
      elementos.nodoApi,
      datos.api === "ok",
      datos.api === "ok" ? "responde" : "sin respuesta",
    );
    pintarPunto(
      elementos.puntoDb,
      elementos.valorDb,
      elementos.nodoDb,
      datos.db === "ok",
      datos.db === "ok" ? "conectada" : "no conectada",
    );
  } catch {
    // Si ni siquiera hemos podido llegar a la API, damos las dos por caídas:
    // sin API no hay forma de saber cómo está la base de datos.
    pintarPunto(
      elementos.puntoApi,
      elementos.valorApi,
      elementos.nodoApi,
      false,
      "sin respuesta",
    );
    pintarPunto(
      elementos.puntoDb,
      elementos.valorDb,
      elementos.nodoDb,
      false,
      "desconocido",
    );
  }
}

/* -----------------------------------------------------------------------------
   Arranque
   -------------------------------------------------------------------------- */

cargarEntradas();
comprobarEstado();
setInterval(comprobarEstado, MILISEGUNDOS_ENTRE_COMPROBACIONES);
