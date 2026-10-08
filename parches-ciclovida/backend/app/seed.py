"""Carga los jóvenes SIMULADOS de app/datos/sinteticos.json y simula cuatro domingos para la demo.

    python -m app.seed --reset                  # los 1.500 del JSON
    python -m app.seed --reset --jovenes 400    # solo los primeros 400 (más rápido)

Los jóvenes se van sumando semana a semana (campo `semana_de_ingreso` del JSON) y eligen el
parche de su estación, hora y actividad: cuatro domingos pasados con grupos armados por k-means,
respuestas y encuestas, y el próximo domingo abierto con parte de la gente ya unida (para que la
lista de la demo no salga vacía). Traen sus respuestas del quiz «Tu estilo de parche» tal cual
están en el JSON. Quién va cada domingo y qué responde en la encuesta sale de una semilla fija:
la demo sale igual cada vez.

Con 1.500 nadie queda solo: cada actividad tiene gente de sobra en cada hora. Con muchos menos, los
parches quedan de a una o dos personas y hay que juntar gente de otras horas (ver el README).
El tablero muestra un aviso de "datos de demostración" mientras existan.
No son resultados de ningún piloto: no presentarlos como tales.
"""

from __future__ import annotations

import argparse
import math
import random
import zlib
from collections import Counter
from datetime import datetime, time, timedelta

from sqlmodel import Session, SQLModel, select

from . import config, services, sinteticos
from .catalog import SEGMENTO_EDAD, tramo_info, UNIVERSIDADES_POR_ID
from .db import engine, init_db
from .models import Asignacion, Encuesta, Grupo, Inscripcion, Jornada, Joven, Salida
from .verificacion import huella

# Cuenta pública para recorrer la app por dentro (el código de ingreso sale en pantalla en la demo).
DEMO_CORREO = "demo@usbcali.edu.co"
DEMO_ID = "demo"


def _joven(d: dict, creado: datetime) -> Joven:
    respuestas = d.get("quiz")
    dominio = UNIVERSIDADES_POR_ID[d["universidad"]]["dominios"][0]
    return Joven(
        id=d["id"],
        nombre=d["nombre"],
        correo_hash=huella(f"{d['id']}@{dominio}"),
        universidad=d["universidad"],
        rango_edad=d["rango_edad"],
        comuna=d["comuna"],
        tramo_id=d["estacion"],
        actividad=d["actividad"],
        ritmo=d["ritmo"],
        franja=d["hora"],
        acepta_datos=True,
        autorizacion_version="sintetico",
        declara_mayor=True,
        declara_mayor_en=creado,
        quiz_respuestas=respuestas,
        quiz=services.vector_quiz({int(k): v for k, v in respuestas.items()}) if respuestas else None,
        # 55 % llega por primera vez: dato simulado, estable entre cargas
        primera_vez=zlib.crc32(d["id"].encode()) % 100 < 55,
        sintetico=True,
        creado_en=creado,
    )


def _semana(d: dict, semanas: int) -> int:
    """La semana en que llega, del 1 al 4 en el JSON, repartida en las semanas que se simulan."""
    return min(semanas, max(1, math.ceil(d["semana_de_ingreso"] * semanas / 4)))


def _unir(s: Session, joven: Joven, fecha) -> None:
    """El joven simulado elige el parche de su estación, hora y actividad preferidas."""
    salida = s.exec(select(Salida).where(
        Salida.jornada_fecha == fecha, Salida.tramo_id == joven.tramo_id, Salida.franja == joven.franja,
        Salida.actividad == joven.actividad, Salida.segmento == SEGMENTO_EDAD[joven.rango_edad],
    )).first()
    if salida is not None:
        s.add(Inscripcion(salida_id=salida.id, joven_id=joven.id, jornada_fecha=fecha))


def _elegir(rng: random.Random, opciones: dict) -> object:
    return rng.choices(list(opciones), weights=list(opciones.values()))[0]


def asegurar_demo(s: Session) -> str | None:
    """La cuenta demo: entra con demo@usbcali.edu.co. Llega al parche con más gente de este domingo y
    trae hasta cuatro domingos pasados con su grupo y su encuesta, para que el historial y la racha
    tengan datos. No es simulada: nunca la toma Gemini como personaje del chat.

    La cuenta se crea de una vez, aunque todavía no estén los simulados, para que se pueda entrar
    desde el primer segundo; el parche y el historial llegan cuando ya hay simulados (se puede llamar
    varias veces). Si ya existe, se actualiza la huella del correo (la base puede venir de otro
    servidor, con otro SECRETO). Devuelve el correo, o None si ese correo ya es de otra cuenta.
    """
    h = huella(DEMO_CORREO)
    if s.exec(select(Joven.id).where(Joven.correo_hash == h, Joven.id != DEMO_ID)).first():
        return None
    demo = s.get(Joven, DEMO_ID)
    if demo is None:
        ahora = services.ahora()
        demo = Joven(
            id=DEMO_ID,
            nombre="Demo",
            correo_hash=h,
            universidad="usb",
            rango_edad="18-22",
            comuna=19,
            tramo_id="panamericana",
            actividad="bici",
            ritmo="moderado",
            acepta_datos=True,
            autorizacion_version=config.AVISO_VERSION,
            autorizacion_en=ahora,
            declara_mayor=True,
            declara_mayor_en=ahora,
            creado_en=ahora - timedelta(days=35),
        )
        s.add(demo)
        s.commit()
    elif demo.correo_hash != h:
        demo.correo_hash = h
        s.add(demo)
        s.commit()
    _completar_demo(s, demo)
    return DEMO_CORREO


def _completar_demo(s: Session, demo: Joven) -> None:
    """Parche con gente este domingo y domingos pasados con grupo. Una sola vez, y solo cuando ya
    están los simulados: sin ellos no hay parches con gente ni grupos a los cuales sumarla."""
    if s.exec(select(Asignacion.id).where(Asignacion.joven_id == DEMO_ID)).first():
        return
    if not s.exec(select(Joven.id).where(Joven.sintetico == True)).first():  # noqa: E712
        return
    abierta = services.jornada_abierta(s)
    # si alguien ya entró mientras cargaban los simulados y el match le dio parche, se respeta
    actual = s.exec(select(Inscripcion).where(
        Inscripcion.joven_id == DEMO_ID, Inscripcion.jornada_fecha == abierta.fecha,
    )).first()
    salida = s.get(Salida, actual.salida_id) if actual else _parche_con_mas_gente(s, abierta.fecha)
    if salida is None:
        return
    demo.tramo_id, demo.actividad, demo.franja = salida.tramo_id, salida.actividad, salida.franja
    demo.comuna = tramo_info(salida.tramo_id)["comuna"]
    s.add(demo)
    s.commit()

    pasadas = s.exec(
        select(Jornada.fecha).where(Jornada.estado == "finalizada").order_by(Jornada.fecha.desc()).limit(4)
    ).all()
    for fecha in sorted(pasadas):
        grupo = _grupo_para_demo(s, demo, fecha)
        if grupo is None:
            continue
        if grupo.salida_id is not None:
            s.add(Inscripcion(salida_id=grupo.salida_id, joven_id=DEMO_ID, jornada_fecha=fecha,
                              creado_en=datetime.combine(fecha - timedelta(days=3), time(18, 0))))
        s.add(Asignacion(grupo_id=grupo.id, joven_id=DEMO_ID, jornada_fecha=fecha, estado="confirmado",
                         respondido_en=datetime.combine(fecha - timedelta(days=1), time(19, 30))))
        s.add(Encuesta(joven_id=DEMO_ID, jornada_fecha=fecha, grupo_id=grupo.id, asistio=True, volveria=True,
                       bienestar=5, creado_en=datetime.combine(fecha, time(15, 0))))
    s.commit()

    if actual is None:
        services.unirse(s, demo, salida.id)


def _parche_con_mas_gente(s: Session, fecha) -> Salida | None:
    """El parche de 18 a 28 años con más inscritos ese domingo: la demo llega a un parche vivo."""
    salidas = s.exec(select(Salida).where(Salida.jornada_fecha == fecha, Salida.segmento == "mayor")).all()
    cuenta = Counter(i.salida_id for i in s.exec(select(Inscripcion).where(Inscripcion.jornada_fecha == fecha)).all())
    return max(salidas, key=lambda x: cuenta[x.id], default=None)


def _grupo_para_demo(s: Session, demo: Joven, fecha) -> Grupo | None:
    """Un grupo de ese domingo en su estación y actividad con cupo; primero los de su misma hora."""
    miembros = Counter(a.grupo_id for a in s.exec(select(Asignacion).where(Asignacion.jornada_fecha == fecha)).all())
    grupos = s.exec(select(Grupo).where(
        Grupo.jornada_fecha == fecha, Grupo.segmento == "mayor",
        Grupo.tramo_id == demo.tramo_id, Grupo.actividad == demo.actividad,
    )).all()
    libres = [g for g in grupos if miembros[g.id] < config.GRUPO_MAX]
    libres.sort(key=lambda g: (g.franja != demo.franja, -miembros[g.id]))
    return libres[0] if libres else None


def sembrar(total: int | None = None, semanas: int = 4, reset: bool = False, semilla: int = 2026) -> dict:
    rng = random.Random(semilla)
    datos = sinteticos.cargar(total)
    if reset:
        SQLModel.metadata.drop_all(engine)
    init_db()
    hoy = services.ahora().date()
    proximo = services.proximo_domingo(hoy)
    domingos = [proximo - timedelta(days=7 * k) for k in range(semanas, 0, -1)]

    with Session(engine) as s:
        if s.exec(select(Joven.id).where(Joven.sintetico == True)).first():  # noqa: E712
            raise SystemExit("Ya hay datos simulados en la base. Corre con --reset para empezar de cero.")
        creados = 0
        for semana, domingo in enumerate(domingos, start=1):
            lunes = domingo - timedelta(days=6)
            for d in datos:
                if _semana(d, semanas) == semana:
                    s.add(_joven(d, datetime.combine(lunes, time(rng.randint(7, 21), rng.randint(0, 59)))))
                    creados += 1
            s.commit()

            # puede existir ya (otra petición la abre sola, y finalizar_vencidas la cierra): se rehace limpia
            previa = s.get(Jornada, domingo) or Jornada(fecha=domingo)
            previa.estado, previa.emparejada_en, previa.finalizada_en = "inscripcion", None, None
            s.add(previa)
            s.commit()
            services.asegurar_parches(s, domingo)
            jovenes = s.exec(select(Joven).where(Joven.sintetico == True).order_by(Joven.id)).all()  # noqa: E712
            for j in jovenes:
                if rng.random() < 0.82:
                    _unir(s, j, domingo)
            s.commit()
            services.armar_grupos(s, domingo)

            for a in s.exec(select(Asignacion).where(Asignacion.jornada_fecha == domingo).order_by(Asignacion.id)).all():
                r = rng.random()
                a.estado = "confirmado" if r < 0.72 else "declinado" if r < 0.82 else "pendiente"
                s.add(a)
                responde = {"confirmado": 0.85, "pendiente": 0.4, "declinado": 0.15}[a.estado]
                if rng.random() > responde:
                    continue
                prob_fue = {"confirmado": 0.88, "pendiente": 0.3, "declinado": 0.05}[a.estado]
                fue = rng.random() < prob_fue
                s.add(Encuesta(
                    joven_id=a.joven_id, jornada_fecha=domingo, grupo_id=a.grupo_id, asistio=fue,
                    volveria=rng.random() < (0.8 if fue else 0.35),
                    bienestar=_elegir(rng, {1: 2, 2: 5, 3: 18, 4: 40, 5: 35}) if fue else None,
                    creado_en=datetime.combine(domingo, time(15, 0)),
                ))
            jornada = s.get(Jornada, domingo)
            jornada.estado = "finalizada"
            jornada.finalizada_en = datetime.combine(domingo, time(13, 0))
            s.add(jornada)
            s.commit()

        abierta = services.jornada_abierta(s)
        for j in s.exec(select(Joven).where(Joven.sintetico == True).order_by(Joven.id)).all():  # noqa: E712
            if rng.random() < 0.5:
                _unir(s, j, abierta.fecha)
        s.commit()
        return {"jovenes": creados, "domingos": [str(d) for d in domingos], "proxima": str(abierta.fecha)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--jovenes", type=int, default=None, help="cuántos del JSON cargar (por defecto, todos)")
    ap.add_argument("--semanas", type=int, default=4)
    ap.add_argument("--reset", action="store_true", help="borra la base antes de sembrar")
    args = ap.parse_args()
    print(sembrar(args.jovenes, args.semanas, args.reset))
    with Session(engine) as sesion:
        print("Cuenta demo:", asegurar_demo(sesion) or "no se pudo crear")
