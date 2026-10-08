#!/usr/bin/env python3
"""Deja listas las carpetas android/ e ios/ después de `flutter create .`

Uso (desde la carpeta app/):
    flutter create . --project-name parches_ciclovida --org co.dedsec --platforms android,ios,web
    python tool/configurar_plataformas.py

Qué hace, sin tocar nada que ya esté bien (se puede correr varias veces):
  Android
    * permisos: INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED y ubicación (para la ruta al parche)
    * usesCleartextTraffic="true" para hablar con el backend por http:// en la red local
    * receivers de flutter_local_notifications para los avisos programados
    * core library desugaring en app/build.gradle(.kts), que el plugin exige
  iOS
    * NSAppTransportSecurity para permitir http:// en la red local (solo para la demo)
    * NSLocationWhenInUseUsageDescription: el texto que ve la persona al pedirle la ubicación
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"

PERMISOS = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]

TEXTO_UBICACION = ("Usamos tu ubicación solo en el teléfono para trazar la ruta hasta la estación de tu parche. "
                   "No la guardamos.")

RECEIVERS = """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""


def manifest(ruta: Path) -> list[str]:
    s = ruta.read_text(encoding="utf-8")
    cambios = []
    for p in PERMISOS:
        if f'android:name="{p}"' not in s:
            s = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', s, count=1)
            cambios.append(f"permiso {p.rsplit('.', 1)[1]}")
    if "usesCleartextTraffic" not in s:
        s = re.sub(r"<application\b", '<application\n        android:usesCleartextTraffic="true"', s, count=1)
        cambios.append("usesCleartextTraffic")
    if "ScheduledNotificationReceiver" not in s:
        s = s.replace("    </application>", RECEIVERS + "    </application>", 1)
        cambios.append("receivers de notificaciones")
    ruta.write_text(s, encoding="utf-8")
    return cambios


def gradle(ruta: Path) -> list[str]:
    s = ruta.read_text(encoding="utf-8")
    kts = ruta.suffix == ".kts"
    cambios = []
    flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
    if "oreLibraryDesugaringEnabled" not in s:
        if re.search(r"compileOptions\s*\{", s):
            s = re.sub(r"(compileOptions\s*\{)", rf"\1\n        {flag}", s, count=1)
        else:
            s = re.sub(r"(android\s*\{)", rf"\1\n    compileOptions {{\n        {flag}\n    }}", s, count=1)
        cambios.append("desugaring activado")
    if DESUGAR not in s:
        dep = f'    coreLibraryDesugaring("{DESUGAR}")' if kts else f"    coreLibraryDesugaring '{DESUGAR}'"
        s = s.rstrip() + f"\n\ndependencies {{\n{dep}\n}}\n"
        cambios.append("dependencia desugar_jdk_libs")
    ruta.write_text(s, encoding="utf-8")
    return cambios


def info_plist(ruta: Path) -> list[str]:
    s = ruta.read_text(encoding="utf-8")
    cambios = []
    bloques = {
        "NSAppTransportSecurity": (
            "\t<key>NSAppTransportSecurity</key>\n"
            "\t<dict>\n"
            "\t\t<key>NSAllowsArbitraryLoads</key>\n"
            "\t\t<true/>\n"
            "\t</dict>\n",
            "NSAppTransportSecurity (http en red local)",
        ),
        "NSLocationWhenInUseUsageDescription": (
            "\t<key>NSLocationWhenInUseUsageDescription</key>\n"
            f"\t<string>{TEXTO_UBICACION}</string>\n",
            "NSLocationWhenInUseUsageDescription (ruta al parche)",
        ),
    }
    for clave, (bloque, nombre) in bloques.items():
        if clave not in s:
            i = s.rfind("</dict>")
            s = s[:i] + bloque + s[i:]
            cambios.append(nombre)
    ruta.write_text(s, encoding="utf-8")
    return cambios


def version_agp(android: Path) -> str | None:
    for nombre in ("settings.gradle.kts", "settings.gradle"):
        f = android / nombre
        if f.exists():
            m = re.search(r'com\.android\.application["\']?\)?\s+version\s+["\']([\d.]+)', f.read_text(encoding="utf-8"))
            if m:
                return m.group(1)
    return None


def main() -> int:
    android = RAIZ / "android"
    ios = RAIZ / "ios"
    if not android.exists() and not ios.exists():
        print("No encuentro android/ ni ios/. Primero corre, desde app/:")
        print("  flutter create . --project-name parches_ciclovida --org co.dedsec --platforms android,ios,web")
        return 1

    if android.exists():
        m = android / "app/src/main/AndroidManifest.xml"
        g = next((p for p in (android / "app/build.gradle.kts", android / "app/build.gradle") if p.exists()), None)
        print("Android:")
        for c in manifest(m):
            print("  +", c)
        if g:
            for c in gradle(g):
                print("  +", c)
        agp = version_agp(android)
        if agp and tuple(int(x) for x in agp.split(".")[:3]) < (8, 11, 1):
            print(f"  ! Tu Android Gradle Plugin es {agp}; flutter_local_notifications pide 8.11.1 o más.")
            print("    Actualiza Flutter (flutter upgrade) y vuelve a crear la carpeta android/.")
        print("  listo")

    if ios.exists():
        print("iOS:")
        for c in info_plist(ios / "Runner/Info.plist"):
            print("  +", c)
        print("  listo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
