"""Reporte del emparejamiento: cada grupo, sus integrantes y por qué quedaron juntos.

    python -m app.reporte                                  # resumen del último domingo con grupos
    python -m app.reporte --json reporte.json --md reporte.md
    python -m app.reporte --fecha 2026-09-20

También en GET /api/admin/emparejamiento, con la clave de administración.

Además de los grupos, mide si el quiz «Tu estilo de parche» aporta: en los parches que k-means
dividió (7 personas o más), arma los grupos otra vez sin el quiz y al azar, y compara qué tanto
comparte perfil la gente de cada grupo. El perfil solo existe en los jóvenes SIMULADOS
(app/datos/sinteticos.json), que salen de perfiles conocidos justo para poder hacer esta prueba.

Privacidad: el estilo de parche (quiz) y el perfil solo se muestran para los simulados. De las
personas reales solo sale lo que usa k-means y no las identifica (ritmo, rango de edad y cuántos
domingos ha ido): ni su nombre ni sus respuestas. Este reporte no llega al tablero de la Secretaría.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import Counter, defaultdict
from dataclasses import replace
from datetime import date
from pathlib import Path

from sqlmodel import Session, select

from . import config, services, sinteticos
from .catalog import ACTIVIDADES_POR_ID, FRANJA_NOMBRE, QUIZ_PREGUNTAS, RITMOS, tramo_info
from .matching import PESOS, Participante, agrupar, centroide, distancia2, tamanos_balanceados, vector
from .models import Asignacion, Grupo, Joven

RITMO_NOMBRE = {r["id"]: r["nombre"].lower() for r in RITMOS}
OPCION_TEXTO = {(p["id"], o["id"]): o["texto"] for p in QUIZ_PREGUNTAS for o in p["opciones"]}
_AZAR_REPETICIONES = 30


def ultima_fecha_con_grupos(session: Session) -> date | None:
    return session.exec(select(Grupo.jornada_fecha).order_by(Grupo.jornada_fecha.desc())).first()


def _participante(session: Session, joven: Joven, g: Grupo) -> Participante:
    return Participante(
        id=joven.id, tramo=g.tramo_id, franja=g.franja, actividad=g.actividad, ritmo=joven.ritmo,
        rango_edad=joven.rango_edad, experiencia=services._experiencia(session, joven.id, g.jornada_fecha),
        quiz=services.quiz_de(joven),
    )


# ---------------------------------------------------------------- por qué quedaron juntos

def _mayoria(valores: list, total: int) -> tuple[object, int] | None:
    if not valores:
        return None
    valor, n = Counter(valores).most_common(1)[0]
    return valor, n


def _cuantos(n: int, total: int) -> str:
    return "Todos" if n == total else f"{n} de {total}"


def por_que(g: Grupo, filas: list[tuple[Joven, Asignacion, Participante]]) -> list[str]:
    """Frases cortas, sacadas de los datos, que explican por qué este grupo quedó junto."""
    total = len(filas)
    razones = [f"Mismo parche: estación {tramo_info(g.tramo_id)['nombre']}, "
               f"{FRANJA_NOMBRE[g.franja]}, {ACTIVIDADES_POR_ID[g.actividad]['nombre'].lower()}."]
    movidos = [a for _, a, _ in filas if a.ajustes]
    if movidos:
        cambios = sorted({c for a in movidos for c in a.ajustes.split(",") if c})
        que = " y ".join({"franja": "de hora", "actividad": "de actividad"}[c] for c in cambios)
        razones.append(f"{len(movidos)} {'llegó' if len(movidos) == 1 else 'llegaron'} de otro parche de la misma "
                       f"estación para que nadie quedara solo (cambio {que}).")
    ritmo, n = _mayoria([j.ritmo for j, _, _ in filas], total)
    razones.append(f"Ritmo: {_cuantos(n, total).lower() if n != total else 'todos'} "
                   f"{'van' if n != 1 else 'va'} a ritmo {RITMO_NOMBRE[ritmo]}.")
    edad, n = _mayoria([j.rango_edad for j, _, _ in filas], total)
    desde, hasta = edad.split("-")
    razones.append(f"Edad: {_cuantos(n, total).lower()} entre {desde} y {hasta} años.")
    exp = [p.experiencia for _, _, p in filas]
    razones.append("Experiencia: todos estrenan parche." if max(exp) == 0
                   else f"Experiencia: de {min(exp)} a {max(exp)} domingos con parche.")
    # estilo: solo con las respuestas de los simulados (las de personas reales no se exportan)
    respuestas = [services.respuestas_quiz(j) for j, _, _ in filas if j.sintetico]
    respuestas = [r for r in respuestas if r]
    if len(respuestas) >= 2:
        coincidencias = []
        for p in QUIZ_PREGUNTAS:
            mayoria = _mayoria([r[p["id"]] for r in respuestas if p["id"] in r], len(respuestas))
            if mayoria is None:
                continue
            opcion, n = mayoria
            if n / len(respuestas) >= 0.6:
                coincidencias.append((n / len(respuestas), f"«{OPCION_TEXTO[(p['id'], opcion)]}» ({n} de {len(respuestas)})"))
        coincidencias.sort(key=lambda x: -x[0])
        if coincidencias:
            razones.append("Estilo, entre quienes respondieron el quiz: "
                           + "; ".join(texto for _, texto in coincidencias[:3]) + ".")
        else:
            razones.append("Estilo: variado entre quienes respondieron el quiz.")
    return razones


# ---------------------------------------------------------------- ¿sirve el quiz?

def coincidencia(grupos: list[list[Participante]], clave) -> tuple[int, int]:
    """Cuántos comparten el valor más común de su grupo, contando solo a quienes `clave` no da None
    y en grupos con al menos dos de ellos. Devuelve (coinciden, contados)."""
    coinciden = contados = 0
    for g in grupos:
        valores = [v for v in (clave(p) for p in g) if v is not None]
        if len(valores) >= 2:
            coinciden += Counter(valores).most_common(1)[0][1]
            contados += len(valores)
    return coinciden, contados


def _companeros(grupos: list[list[Participante]]) -> dict[str, frozenset]:
    return {p.id: frozenset(q.id for q in g if q.id != p.id) for g in grupos for p in g}


def efecto_del_quiz(por_parche: dict[int, list[Participante]], perfiles: dict[str, str], con_quiz: set[str]) -> dict:
    """Rearma los parches que k-means divide con el quiz, sin el quiz y al azar, y compara."""
    rng = random.Random(7)
    divididos = personas = cambian = 0
    medidas = {
        "afinidad_de_estilo_pct": lambda p: perfiles.get(p.id) if p.id in con_quiz else None,
        "mismo_ritmo_pct": lambda p: p.ritmo,
    }
    suma = {m: {"con_quiz": [0.0, 0.0], "sin_quiz": [0.0, 0.0], "al_azar": [0.0, 0.0]} for m in medidas}

    def sumar(forma: str, grupos: list[list[Participante]], peso: float = 1.0) -> None:
        for m, clave in medidas.items():
            a, t = coincidencia(grupos, clave)
            suma[m][forma][0] += a * peso
            suma[m][forma][1] += t * peso

    for gente in por_parche.values():
        tamanos = tamanos_balanceados(len(gente), config.GRUPO_MIN, config.GRUPO_OBJETIVO, config.GRUPO_MAX)
        if len(tamanos) < 2:
            continue  # con 3 a 6 personas queda un solo grupo: no hay nada que decidir
        divididos += 1
        personas += len(gente)
        con = agrupar(gente, config.GRUPO_MIN, config.GRUPO_OBJETIVO, config.GRUPO_MAX)
        sin = agrupar([replace(p, quiz=None) for p in gente], config.GRUPO_MIN, config.GRUPO_OBJETIVO, config.GRUPO_MAX)
        c_con, c_sin = _companeros(con), _companeros(sin)
        cambian += sum(1 for i in c_con if c_con[i] != c_sin.get(i))
        sumar("con_quiz", con)
        sumar("sin_quiz", sin)
        for _ in range(_AZAR_REPETICIONES):
            barajados = rng.sample(gente, len(gente))
            grupos, i = [], 0
            for n in tamanos:
                grupos.append(barajados[i:i + n])
                i += n
            sumar("al_azar", grupos, 1 / _AZAR_REPETICIONES)
    return {
        "pesos": dict(PESOS),
        "parches_divididos_por_kmeans": divididos,
        "personas_en_esos_parches": personas,
        "personas_cuyo_grupo_cambia_por_el_quiz": cambian,
        **{m: {forma: round(100 * a / t, 1) if t else None for forma, (a, t) in formas.items()}
           for m, formas in suma.items()},
        "como_leerlo": "Solo cuenta los parches que k-means dividió (7 personas o más; con 3 a 6 queda un solo "
                       "grupo). Afinidad de estilo: entre los simulados que respondieron el quiz, qué parte de cada "
                       "grupo comparte el perfil más común del grupo. Mismo ritmo: qué parte de cada grupo va al "
                       "ritmo más común del grupo. Se compara con armar los mismos grupos sin el quiz y al azar "
                       "(promedio de 30 sorteos).",
    }


# ---------------------------------------------------------------- reporte

def generar(session: Session, fecha: date | None = None) -> dict | None:
    fecha = fecha or ultima_fecha_con_grupos(session)
    if fecha is None:
        return None
    grupos = session.exec(select(Grupo).where(Grupo.jornada_fecha == fecha).order_by(Grupo.id)).all()
    if not grupos:
        return None
    perfiles = sinteticos.perfiles_por_id()

    salida_grupos, claves, por_parche = [], [], defaultdict(list)
    tam, act = Counter(), defaultdict(lambda: [0, 0])
    movidos = tarde = 0
    con_quiz: set[str] = set()
    for g in grupos:
        filas = []
        for a in session.exec(select(Asignacion).where(Asignacion.grupo_id == g.id).order_by(Asignacion.id)).all():
            joven = session.get(Joven, a.joven_id)
            if joven is not None:
                filas.append((joven, a, _participante(session, joven, g)))
        if not filas:
            continue
        for j, a, p in filas:
            por_parche[g.salida_id or -g.id].append(p)
            movidos += bool(a.ajustes)
            tarde += a.tarde
            if j.sintetico and p.quiz is not None:
                con_quiz.add(j.id)
        n = len(filas)
        tam[n] += 1
        act[g.actividad][0] += n
        act[g.actividad][1] += n if n >= config.GRUPO_MIN else 0

        vecs = [vector(p) for _, _, p in filas]
        centro = centroide(vecs)
        integrantes = []
        for (j, a, p), v in zip(filas, vecs):
            fila = {
                "sintetico": j.sintetico,
                "ritmo": j.ritmo,
                "rango_edad": j.rango_edad,
                "experiencia": p.experiencia,
                "distancia_al_centro": round(math.sqrt(distancia2(v, centro)), 3),
                "cambio": [c for c in a.ajustes.split(",") if c],
                "llego_tarde": a.tarde,
            }
            if j.sintetico:  # de las personas reales no sale ni el nombre ni el quiz
                fila = {"id": j.id, "nombre": j.nombre, "perfil": perfiles.get(j.id),
                        "quiz": services.respuestas_quiz(j), **fila}
                if fila["quiz"]:
                    fila["quiz"] = {str(k): v for k, v in fila["quiz"].items()}
            integrantes.append(fila)
        salida_grupos.append({
            "id": g.id,
            "nombre": g.nombre,
            "estacion": tramo_info(g.tramo_id)["nombre"],
            "hora": FRANJA_NOMBRE[g.franja],
            "actividad": ACTIVIDADES_POR_ID[g.actividad]["nombre"],
            "nivel": g.nivel,
            "tamano": n,
            "dividido_por_kmeans": False,  # se completa abajo
            "cohesion": round(sum(i["distancia_al_centro"] for i in integrantes) / n, 3),
            "por_que": por_que(g, filas),
            "integrantes": integrantes,
        })
        claves.append(g.salida_id or -g.id)

    grupos_por_parche = Counter(claves)
    for gj, clave in zip(salida_grupos, claves):
        gj["dividido_por_kmeans"] = grupos_por_parche[clave] >= 2

    personas = sum(n * c for n, c in tam.items())
    en_3_a_6 = sum(n * c for n, c in tam.items() if config.GRUPO_MIN <= n <= config.GRUPO_MAX)
    return {
        "fecha": str(fecha),
        "nota": "Solo se muestran el estilo de parche y el perfil de los jóvenes simulados. De las personas "
                "reales no se exporta ni el nombre ni las respuestas del quiz. No es para el tablero.",
        "resumen": {
            "personas_con_grupo": personas,
            "grupos": sum(tam.values()),
            "tamanos": {str(n): c for n, c in sorted(tam.items())},
            "en_grupos_de_3_a_6_pct": round(100 * en_3_a_6 / personas, 1) if personas else 0,
            "solos": tam.get(1, 0),
            "grupos_de_2": tam.get(2, 0),
            "cambiaron_de_hora_o_actividad": movidos,
            "llegaron_despues_del_sabado": tarde,
            "respondieron_el_quiz": sum(1 for g in salida_grupos for i in g["integrantes"] if i.get("quiz")),
            "por_actividad": {
                ACTIVIDADES_POR_ID[a]["nombre"]: {
                    "personas": n, "en_grupos_de_3_o_mas_pct": round(100 * ok / n, 1) if n else 0,
                } for a, (n, ok) in sorted(act.items())
            },
        },
        "efecto_del_quiz": efecto_del_quiz(por_parche, perfiles, con_quiz),
        "grupos": salida_grupos,
    }


# ---------------------------------------------------------------- Markdown

_MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
          "noviembre", "diciembre"]


def _num(n) -> str:
    """1217 -> "1.217"; 65.9 -> "65,9" (como se escribe en Colombia)."""
    if isinstance(n, int):
        return f"{n:,}".replace(",", ".")
    return f"{n:.1f}".replace(".", ",") if isinstance(n, float) else str(n)


def _pct(v) -> str:
    return "—" if v is None else f"{_num(float(v))} %"


def _fecha(iso: str) -> str:
    d = date.fromisoformat(iso)
    return f"{d.day} de {_MESES[d.month - 1]} de {d.year}"


def markdown(r: dict, max_parches: int = 6) -> str:
    res, ef = r["resumen"], r["efecto_del_quiz"]
    af, ri, pesos = ef["afinidad_de_estilo_pct"], ef["mismo_ritmo_pct"], ef["pesos"]
    lineas = [
        f"# Reporte del emparejamiento · domingo {_fecha(r['fecha'])}",
        "",
        f"> {r['nota']} Generado con `python -m app.reporte`.",
        "",
        "## Resumen",
        "",
        "| | |",
        "|---|---|",
        f"| Personas con grupo | {_num(res['personas_con_grupo'])} |",
        f"| Grupos | {_num(res['grupos'])} |",
        f"| En grupos de 3 a 6 | {_pct(res['en_grupos_de_3_a_6_pct'])} |",
        f"| Solos / grupos de 2 | {res['solos']} / {res['grupos_de_2']} |",
        f"| Cambiaron de hora o actividad para completar grupo | {_num(res['cambiaron_de_hora_o_actividad'])} |",
        f"| Respondieron el quiz (simulados) | {_num(res['respondieron_el_quiz'])} |",
        "",
        "| Actividad | Personas | En grupos de 3 o más |",
        "|---|---|---|",
        *[f"| {a} | {_num(v['personas'])} | {_pct(v['en_grupos_de_3_o_mas_pct'])} |" for a, v in res["por_actividad"].items()],
        "",
        "## ¿Sirve el quiz?",
        "",
        f"k-means dividió **{ef['parches_divididos_por_kmeans']} parches** ({_num(ef['personas_en_esos_parches'])} "
        f"personas). Al quitar el quiz, a **{_num(ef['personas_cuyo_grupo_cambia_por_el_quiz'])}** de ellas les cambia "
        "el grupo.",
        "",
        "| Grupos armados… | Afinidad de estilo | Mismo ritmo |",
        "|---|---|---|",
        f"| con el quiz (como funciona la app) | **{_pct(af['con_quiz'])}** | **{_pct(ri['con_quiz'])}** |",
        f"| sin el quiz | {_pct(af['sin_quiz'])} | {_pct(ri['sin_quiz'])} |",
        f"| al azar | {_pct(af['al_azar'])} | {_pct(ri['al_azar'])} |",
        "",
        f"Pesos de k-means: ritmo {_num(float(pesos['ritmo']))}, edad {_num(float(pesos['edad']))}, experiencia "
        f"{_num(float(pesos['experiencia']))} y quiz {_num(float(pesos['quiz']))} por pregunta (se cambia con `PESO_QUIZ`).",
        "",
        f"_{ef['como_leerlo']}_",
        "",
        f"## Ejemplos: grupos de parches que k-means dividió (primeros {max_parches})",
        "",
    ]
    vistos = []
    for g in r["grupos"]:
        if not g["dividido_por_kmeans"]:
            continue
        clave = (g["estacion"], g["hora"], g["actividad"])
        if clave not in vistos:
            if len(vistos) == max_parches:
                break
            vistos.append(clave)
        lineas += [f"### {g['nombre']} · {g['estacion']} · {g['hora']} · {g['actividad']} ({g['tamano']} personas)", ""]
        lineas += [f"- {razon}" for razon in g["por_que"]]
        lineas += ["", "| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |",
                   "|---|---|---|---|---|---|---|"]
        for i in g["integrantes"]:
            quiz = "·".join(i["quiz"][str(k)] for k in range(1, 6)) if i.get("quiz") else "—"
            nombre = i.get("nombre", "Persona real (datos ocultos)")
            perfil = sinteticos.PERFILES.get(i.get("perfil") or "", {}).get("nombre", "—")
            distancia = f"{i['distancia_al_centro']:.2f}".replace(".", ",")
            lineas.append(f"| {nombre} | {perfil} | {RITMO_NOMBRE[i['ritmo']]} | {i['rango_edad'].replace('-', ' a ')} | "
                          f"{i['experiencia']} | {quiz} | {distancia} |")
        lineas.append("")
    return "\n".join(lineas) + "\n"


def texto_resumen(r: dict) -> str:
    res, ef = r["resumen"], r["efecto_del_quiz"]
    af, ri = ef["afinidad_de_estilo_pct"], ef["mismo_ritmo_pct"]
    return (
        f"Domingo {r['fecha']}: {res['personas_con_grupo']} personas en {res['grupos']} grupos; "
        f"{res['en_grupos_de_3_a_6_pct']} % en grupos de 3 a 6, {res['solos']} solos, {res['grupos_de_2']} grupos de 2, "
        f"{res['cambiaron_de_hora_o_actividad']} cambiaron de hora o actividad.\n"
        f"k-means dividió {ef['parches_divididos_por_kmeans']} parches; sin el quiz cambiaría el grupo de "
        f"{ef['personas_cuyo_grupo_cambia_por_el_quiz']} de {ef['personas_en_esos_parches']} personas "
        f"(peso del quiz: {ef['pesos']['quiz']}).\n"
        f"Afinidad de estilo: con quiz {af['con_quiz']} %, sin quiz {af['sin_quiz']} %, al azar {af['al_azar']} %.\n"
        f"Mismo ritmo:        con quiz {ri['con_quiz']} %, sin quiz {ri['sin_quiz']} %, al azar {ri['al_azar']} %."
    )


def main() -> int:
    from .db import engine, init_db

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fecha", type=date.fromisoformat, help="domingo a revisar (por defecto, el último con grupos)")
    ap.add_argument("--json", type=Path, help="guardar el reporte completo en JSON")
    ap.add_argument("--md", type=Path, help="guardar el reporte en Markdown")
    args = ap.parse_args()
    init_db()
    with Session(engine) as s:
        r = generar(s, args.fecha)
    if r is None:
        print("Todavía no hay grupos armados. Corre python -m app.seed --reset o arma los del sábado.")
        return 1
    if args.json:
        args.json.write_text(json.dumps(r, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.md:
        args.md.write_text(markdown(r), encoding="utf-8")
    print(texto_resumen(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
