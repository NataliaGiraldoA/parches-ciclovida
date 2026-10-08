#!/bin/sh
# Construye Flutter Web para Vercel.
set -eu

API_URL="${API_URL:-}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.9}"
SDK="${HOME}/.cache/flutter-${FLUTTER_VERSION}"

if [ ! -x "${SDK}/bin/flutter" ]; then
  mkdir -p "$(dirname "${SDK}")"
  echo "Descargando Flutter ${FLUTTER_VERSION}..."
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${SDK}"
fi

export PATH="${SDK}/bin:${SDK}/bin/cache/dart-sdk/bin:${PATH}"

# Vercel ejecuta este script desde la raíz configurada del proyecto. En este
# repositorio la app puede estar en la raíz del monorepo o en parches-ciclovida/.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "${SCRIPT_DIR}/../pubspec.yaml" ]; then
  APP_DIR="${SCRIPT_DIR}/.."
elif [ -f "${SCRIPT_DIR}/../../parches-ciclovida/app/pubspec.yaml" ]; then
  APP_DIR="${SCRIPT_DIR}/../../parches-ciclovida/app"
else
  echo "No se encontró pubspec.yaml para Flutter." >&2
  exit 1
fi
cd "${APP_DIR}"

flutter config --no-analytics >/dev/null 2>&1 || :
flutter --version
flutter pub get
echo "Compilando la app web contra ${API_URL}"
flutter build web --release --pwa-strategy=none --dart-define=API_URL="${API_URL}" --dart-define=VERCEL=true
