#!/usr/bin/env bash
# Construye la app web en Render. Los sitios estáticos de Render no traen Flutter: se descarga la
# versión fija del SDK y se compila con la dirección pública del backend.
#
# Variables (en el sitio estático de Render):
#   API_URL          URL pública del backend, p. ej. https://parches-backend.onrender.com
#   FLUTTER_VERSION  etiqueta de Flutter (por defecto la probada, 3.38.9; "stable" también sirve)
set -euo pipefail

API_URL="${API_URL:-https://parches-backend.onrender.com}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.9}"
SDK="${HOME}/flutter-${FLUTTER_VERSION}"

if [ ! -x "${SDK}/bin/flutter" ]; then
  echo "Descargando Flutter ${FLUTTER_VERSION}…"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${SDK}"
fi
export PATH="${SDK}/bin:${PATH}"

flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
flutter pub get

echo "Compilando la app web contra ${API_URL}"
flutter build web --release --dart-define=API_URL="${API_URL}"

# Las primeras versiones desplegadas registraron el service worker de Flutter, que sirve la app vieja
# desde la caché. Este reemplazo se instala solo en esos navegadores, borra la caché, se desregistra
# y recarga la pestaña: todos quedan con la versión nueva sin tener que borrar datos a mano.
cat > build/web/flutter_service_worker.js <<'SW'
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const clave of await caches.keys()) await caches.delete(clave);
    await self.registration.unregister();
    for (const pestana of await self.clients.matchAll({ type: 'window' })) pestana.navigate(pestana.url);
  })());
});
SW
