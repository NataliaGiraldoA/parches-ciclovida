/* Dirección del backend. Vacía cuando el tablero lo sirve el mismo backend (/tablero/).
   En Render, el sitio estático reescribe este archivo con API_URL al construirse (ver render.yaml). */
window.PARCHES_API = window.PARCHES_API || '';
/* Dirección de la app web (opcional): muestra el botón "Abrir la app". En Render la escribe el build. */
window.PARCHES_APP = window.PARCHES_APP || '';
