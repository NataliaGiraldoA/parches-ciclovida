"""Jóvenes SIMULADOS de la demo, en un JSON a la vista: backend/app/datos/sinteticos.json

    python -m app.sinteticos        # regenera el JSON (1.500 jóvenes, semilla 2026)

Cada joven sale de uno de cuatro perfiles coherentes: sus respuestas del quiz «Tu estilo de parche»,
su ritmo, su hora y su actividad van de la mano, con algo de ruido (cada respuesta coincide con la
típica de su perfil el 80 % de las veces, y el 30 % no responde el quiz). Así se puede comprobar
que k-means junta a gente parecida: ver app/reporte.py.

El perfil es solo para generar y evaluar estos datos. Las personas reales nunca tienen perfil ni
etiqueta: la app solo guarda lo que respondieron y lo usa por dentro.

No son datos de personas reales: no presentarlos como resultados de un piloto.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from .catalog import QUIZ_PREGUNTAS, TRAMOS

RUTA = Path(__file__).resolve().parent / "datos" / "sinteticos.json"
TOTAL = 1500
SEMILLA = 2026

PROB_QUIZ = 0.7  # parte de la gente que responde el quiz (es opcional)
PROB_TIPICA = 0.8  # probabilidad de que cada respuesta sea la típica de su perfil

PERFILES = {
    "parchadito": {
        "nombre": "Parchadito social",
        "descripcion": "Va por el plan con la gente: charla todo el camino, jugo al final y llega con el tiempo justo.",
        "peso": 30,
        "respuestas_tipicas": {"1": "a", "2": "a", "3": "b", "4": "a", "5": "b"},
        "ritmo": {"tranquilo": 45, "moderado": 45, "rapido": 10},
        "hora": {"08:00": 25, "09:30": 45, "11:00": 30},
        "actividad": {"bici": 40, "patines": 25, "caminar": 25, "trotar": 10},
    },
    "madrugador": {
        "nombre": "Madrugador cumplido",
        "descripcion": "Llega temprano, prefiere la ruta de siempre y no deja a nadie atrás.",
        "peso": 25,
        "respuestas_tipicas": {"1": "c", "2": "c", "3": "a", "4": "a", "5": "a"},
        "ritmo": {"tranquilo": 25, "moderado": 60, "rapido": 15},
        "hora": {"08:00": 65, "09:30": 30, "11:00": 5},
        "actividad": {"caminar": 35, "bici": 35, "trotar": 25, "patines": 5},
    },
    "deportista": {
        "nombre": "Deportista",
        "descripcion": "Va a entrenar: ruta nueva, puntual y cada quien a su paso.",
        "peso": 20,
        "respuestas_tipicas": {"1": "b", "2": "b", "3": "b", "4": "b", "5": "a"},
        "ritmo": {"tranquilo": 5, "moderado": 30, "rapido": 65},
        "hora": {"08:00": 70, "09:30": 25, "11:00": 5},
        "actividad": {"bici": 50, "trotar": 35, "patines": 15, "caminar": 0},
    },
    "contemplativo": {
        "nombre": "Contemplativo",
        "descripcion": "Sale sin afán a disfrutar el paisaje, en su mundo y a su hora.",
        "peso": 25,
        "respuestas_tipicas": {"1": "b", "2": "b", "3": "a", "4": "a", "5": "b"},
        "ritmo": {"tranquilo": 70, "moderado": 30, "rapido": 0},
        "hora": {"08:00": 20, "09:30": 40, "11:00": 40},
        "actividad": {"caminar": 50, "bici": 35, "patines": 10, "trotar": 5},
    },
}

PESO_TRAMO = {
    "panamericana": 16, "ingenio": 14, "dorada": 9, "la-luna": 9, "metropolitana": 9,
    "ciudad-de-cali": 7, "sol-de-oriente": 9, "san-carlos": 7, "americas": 8, "torres-comfandi": 9, "brisas": 10,
}
PESO_UNIVERSIDAD = {"univalle": 26, "uao": 14, "usb": 10, "javeriana": 12, "icesi": 10, "usc": 12,
                    "unilibre": 6, "unicatolica": 5, "uniajc": 5}
PESO_EDAD = {"18-22": 62, "23-28": 38}  # el piloto es de 18 a 28: no hay menores simulados
PESO_SEMANA = {"1": 35, "2": 25, "3": 20, "4": 20}  # la gente se va sumando semana a semana

NOMBRES = (
    "Valentina Santiago Mariana Sebastián Isabella Samuel Sofía Juan Daniela Nicolás Camila Andrés "
    "Laura Felipe Sara Mateo Gabriela Alejandro Paula David Manuela Miguel Luisa Kevin Natalia Jhon "
    "Yuliana Brayan Karen Esteban Ángela Cristian Tatiana Julián Melissa Óscar Vanessa Duván Yeimi Anderson"
).split()

_COMUNA_DE = {t["id"]: t["comuna"] for t in TRAMOS}


def _elegir(rng: random.Random, pesos: dict[str, float]) -> str:
    return rng.choices(list(pesos), weights=list(pesos.values()))[0]


def _respuesta(rng: random.Random, pregunta: dict, tipica: str) -> str:
    if rng.random() < PROB_TIPICA:
        return tipica
    return rng.choice([o["id"] for o in pregunta["opciones"] if o["id"] != tipica])


def generar(total: int = TOTAL, semilla: int = SEMILLA) -> dict:
    """El contenido del JSON. Determinista: con la misma semilla sale idéntico."""
    rng = random.Random(semilla)
    pesos_perfil = {p: d["peso"] for p, d in PERFILES.items()}
    jovenes = []
    for i in range(1, total + 1):
        pid = _elegir(rng, pesos_perfil)
        perfil = PERFILES[pid]
        estacion = _elegir(rng, PESO_TRAMO)
        quiz = None
        if rng.random() < PROB_QUIZ:
            quiz = {str(p["id"]): _respuesta(rng, p, perfil["respuestas_tipicas"][str(p["id"])]) for p in QUIZ_PREGUNTAS}
        jovenes.append({
            "id": f"sim-{i:04d}",
            "nombre": rng.choice(NOMBRES),
            "universidad": _elegir(rng, PESO_UNIVERSIDAD),
            "rango_edad": _elegir(rng, PESO_EDAD),
            "comuna": _COMUNA_DE[estacion] if rng.random() < 0.6 else rng.randint(1, 22),
            "estacion": estacion,
            "hora": _elegir(rng, perfil["hora"]),
            "actividad": _elegir(rng, perfil["actividad"]),
            "ritmo": _elegir(rng, perfil["ritmo"]),
            "semana_de_ingreso": int(_elegir(rng, PESO_SEMANA)),
            "perfil": pid,
            "quiz": quiz,
        })
    return {
        "descripcion": "Jóvenes SIMULADOS para la demo de Parches CicloVida. No son personas reales ni "
                       "resultados de un piloto. Se regenera con: python -m app.sinteticos",
        "version": 1,
        "semilla": semilla,
        "total": total,
        "perfiles": {
            p: {"nombre": d["nombre"], "descripcion": d["descripcion"], "respuestas_tipicas": d["respuestas_tipicas"]}
            for p, d in PERFILES.items()
        },
        "jovenes": jovenes,
    }


def escribir(datos: dict, ruta: Path = RUTA) -> None:
    """JSON legible: la cabecera con sangría y un joven por línea (fácil de revisar y de comparar)."""
    cabecera = {k: v for k, v in datos.items() if k != "jovenes"}
    texto = json.dumps(cabecera, ensure_ascii=False, indent=2)[:-2]  # sin el "\n}" final
    lineas = ",\n    ".join(json.dumps(j, ensure_ascii=False) for j in datos["jovenes"])
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(f'{texto},\n  "jovenes": [\n    {lineas}\n  ]\n}}\n', encoding="utf-8")


def cargar(total: int | None = None) -> list[dict]:
    """Los jóvenes del JSON; con `total`, solo los primeros (para demos o pruebas más rápidas)."""
    jovenes = json.loads(RUTA.read_text(encoding="utf-8"))["jovenes"]
    return jovenes[:total] if total else jovenes


def perfiles_por_id() -> dict[str, str]:
    """id del joven simulado -> su perfil. Solo para evaluar el emparejamiento (reporte)."""
    return {j["id"]: j["perfil"] for j in cargar()}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--total", type=int, default=TOTAL)
    ap.add_argument("--semilla", type=int, default=SEMILLA)
    args = ap.parse_args()
    datos = generar(args.total, args.semilla)
    escribir(datos)
    print(f"{len(datos['jovenes'])} jóvenes simulados en {RUTA}")
