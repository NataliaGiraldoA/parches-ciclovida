#!/usr/bin/env bash
# Construye Flutter Web para Vercel. El backend sigue siendo un servicio persistente en Render.
set -euo pipefail

API_URL="${API_URL:-}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.38.9}"
SDK="${HOME}/.cache/flutter-${FLUTTER_VERSION}"

if [ ! -x "${SDK}/bin/flutter" ]; then
  mkdir -p "$(dirname "${SDK}")"
  echo "Descargando Flutter ${FLUTTER_VERSION}..."
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${SDK}"
fi

export PATH="${SDK}/bin:${PATH}"
cd "$(dirname "$0")/.."

flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
flutter pub get
echo "Compilando la app web contra ${API_URL}"
flutter build web --release --pwa-strategy=none --dart-define=API_URL="${API_URL}" --dart-define=VERCEL=true
