"""Pronóstico del domingo para Cali, hora por hora, con Open-Meteo (gratis y sin clave).

Se pide una sola vez por domingo y se guarda un rato en memoria: la app pregunta su estado cada
pocos segundos y no debe esperar a la red cada vez. Si Open-Meteo no responde, la app no muestra
el clima; nunca falla por esto.
"""

from __future__ import annotations

import logging
import time
from datetime import date

import httpx

from . import config

log = logging.getLogger("parches.clima")

# Centro de Cali: las estaciones quedan a pocos kilómetros y el pronóstico es el mismo.
LAT, LNG = 3.4372, -76.5225
_VIGENCIA = 60 * 60  # un pronóstico sirve una hora
_REINTENTO = 10 * 60  # si falló, no se vuelve a intentar antes de 10 minutos
_cache: dict[date, tuple[float, dict[int, dict] | None]] = {}

# Códigos WMO que usa Open-Meteo, agrupados en lo que le importa a alguien que va a rodar.
_CIELO = [
    ((0,), "Despejado", "sol"),
    ((1, 2), "Parcialmente nublado", "nubes_sol"),
    ((3,), "Nublado", "nubes"),
    ((45, 48), "Neblina", "nubes"),
    ((51, 53, 55, 56, 57), "Llovizna", "lluvia"),
    ((61, 63, 65, 66, 67, 80, 81, 82), "Lluvia", "lluvia"),
    ((95, 96, 99), "Tormenta", "tormenta"),
]


def _cielo(codigo: int) -> tuple[str, str]:
    for codigos, texto, icono in _CIELO:
        if codigo in codigos:
            return texto, icono
    return "Nublado", "nubes"


def _consejo(temp: float, lluvia: int, icono: str) -> str:
    if icono == "tormenta":
        return "Pronostican tormenta: revisa el cielo antes de salir y, si truena, se resguardan."
    if lluvia >= 60 or icono == "lluvia":
        return "Puede llover: lleva impermeable o una chaqueta que se seque rápido."
    if lluvia >= 30:
        return "Hay chance de lluvia: una chaqueta liviana no sobra."
    if temp >= 28:
        return "Va a hacer calor: lleva agua y bloqueador."
    return "Buen clima para rodar. Lleva agua."


def _pedir(fecha: date) -> dict[int, dict] | None:
    r = httpx.get("https://api.open-meteo.com/v1/forecast", timeout=4, params={
        "latitude": LAT, "longitude": LNG, "timezone": "America/Bogota",
        "hourly": "temperature_2m,precipitation_probability,weather_code",
        "start_date": fecha.isoformat(), "end_date": fecha.isoformat(),
    })
    r.raise_for_status()
    h = r.json()["hourly"]
    return {
        int(t[11:13]): {"temp": temp, "lluvia": lluvia or 0, "codigo": codigo or 0}
        for t, temp, lluvia, codigo in zip(h["time"], h["temperature_2m"], h["precipitation_probability"],
                                           h["weather_code"])
        if temp is not None
    }


def _horas(fecha: date) -> dict[int, dict] | None:
    ahora = time.time()
    guardado = _cache.get(fecha)
    if guardado and ahora - guardado[0] < (_VIGENCIA if guardado[1] else _REINTENTO):
        return guardado[1]
    try:
        horas = _pedir(fecha)
    except Exception as e:  # sin red o fecha fuera del rango del pronóstico
        log.info("Sin pronóstico para %s: %s", fecha, e)
        horas = None
    _cache[fecha] = (ahora, horas)
    return horas


def pronostico(fecha: date, hora: str) -> dict | None:
    """El clima del domingo a la hora del parche ("09:30" usa el pronóstico de las 9), o None."""
    if not config.CLIMA_ON:
        return None
    horas = _horas(fecha)
    dato = (horas or {}).get(int(hora[:2]))
    if dato is None:
        return None
    texto, icono = _cielo(dato["codigo"])
    temp = round(dato["temp"])
    return {
        "hora": hora,
        "temperatura": temp,
        "lluvia": dato["lluvia"],
        "cielo": texto,
        "icono": icono,  # sol | nubes_sol | nubes | lluvia | tormenta
        "consejo": _consejo(temp, dato["lluvia"], icono),
    }


def resumen(fecha: date, hora: str) -> str:
    """Una línea para el aviso del sábado y Telegram, o "" si no hay pronóstico."""
    p = pronostico(fecha, hora)
    if not p:
        return ""
    return f"Pronóstico: {p['cielo'].lower()}, {p['temperatura']} °C y {p['lluvia']} % de probabilidad de lluvia."
