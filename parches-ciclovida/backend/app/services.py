"""Reglas del domingo: jornadas, parches que genera el sistema, grupos por k-means, estado de cada joven."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta
from statistics import median

from sqlalchemy import func
from sqlmodel import Session, delete, select

from . import config
from .catalog import (
    ACTIVIDADES, ACTIVIDADES_POR_ID, FRANJA_NOMBRE, FRANJA_ORDEN, FRANJAS, JORNADA_FIN, JORNADA_INICIO,
    NOMBRES_PARCHE, RITMO_ORDEN, RITMOS, SEGMENTO_EDAD, TRAMOS, tramo_info, UNIVERSIDADES_POR_ID, puntuar_quiz,
)
from .matching import EXPERIENCIA_MAX, GrupoPropuesto, Participante, agrupar, grupo_mas_cercano, mejor_grupo_para
from .models import (
    Asignacion, ChatMensaje, ChatMiembro, Encuesta, Espera, Grupo, Inscripcion, Jornada, Joven, MensajeForo,
    Notificacion, Reporte, Salida,
)

RITMO_NOMBRE = {r["id"]: r["nombre"] for r in RITMOS}
RITMO_POR_ORDEN = {r["orden"]: r["id"] for r in RITMOS}
ORDEN_ACTIVIDAD = {a["id"]: i for i, a in enumerate(ACTIVIDADES)}
LETRAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def ahora() -> datetime:
    return datetime.now(config.TZ).replace(tzinfo=None)


def _hhmm(s: str) -> time:
    h, m = s.split(":")
    return time(int(h), int(m))


def proximo_domingo(hoy: date) -> date:
    return hoy + timedelta(days=(6 - hoy.weekday()) % 7)


def segmentos_abiertos() -> list[str]:
    return ["mayor", "menor"] if config.PERMITIR_MENORES else ["mayor"]


def _ritmo_mediano(jovenes: list[Joven]) -> str | None:
    if not jovenes:
        return None
    return RITMO_POR_ORDEN[round(median(RITMO_ORDEN[j.ritmo] for j in jovenes))]


# ---------------------------------------------------------------- jornadas

def finalizar_vencidas(session: Session, momento: datetime) -> list[date]:
    """Cierra toda jornada cuyo domingo ya terminó (por si el servidor estuvo apagado)."""
    abiertas = session.exec(select(Jornada).where(Jornada.estado != "finalizada")).all()
    cerradas = []
    for j in abiertas:
        if datetime.combine(j.fecha, _hhmm(config.FINALIZAR_DOMINGO)) <= momento:
            j.estado = "finalizada"
            j.finalizada_en = momento
            session.add(j)
            cerradas.append(j.fecha)
    if cerradas:
        session.commit()
    return cerradas


def jornada_abierta(session: Session, momento: datetime | None = None) -> Jornada:
    """El próximo domingo que todavía no termina, con sus parches ya generados."""
    momento = momento or ahora()
    finalizar_vencidas(session, momento)
    j = session.exec(
        select(Jornada).where(Jornada.estado != "finalizada", Jornada.fecha >= momento.date()).order_by(Jornada.fecha)
    ).first()
    if not j:
        fecha = proximo_domingo(momento.date())
        while (existente := session.get(Jornada, fecha)) is not None and existente.estado == "finalizada":
            fecha += timedelta(days=7)
        j = Jornada(fecha=fecha)
        session.add(j)
        session.commit()
        session.refresh(j)
    asegurar_parches(session, j.fecha)
    return j


def debe_armar(j: Jornada, momento: datetime) -> bool:
    sabado = j.fecha - timedelta(days=1)
    return j.estado == "inscripcion" and momento >= datetime.combine(sabado, _hhmm(config.EMPAREJAR_SABADO))


def tick(session: Session, momento: datetime | None = None) -> dict:
    """Lo corre el scheduler cada pocos minutos. Idempotente."""
    momento = momento or ahora()
    cerradas = finalizar_vencidas(session, momento)
    j = jornada_abierta(session, momento)
    resumen = {"finalizadas": [str(d) for d in cerradas], "jornada": str(j.fecha)}
    if debe_armar(j, momento):
        resumen["grupos"] = armar_grupos(session, j.fecha)
    from . import telegram

    telegram.procesar_updates(session)
    from . import clima

    clima.pronostico(j.fecha, JORNADA_INICIO)  # deja el pronóstico listo antes de que lo pida la app
    unidos = revisar_esperas(session, momento)
    if unidos:
        resumen["esperas_unidas"] = unidos
    return resumen


# ---------------------------------------------------------------- parches generados

def _nombre_libre(session: Session, fecha: date, tramo_id: str) -> str:
    usados = set(session.exec(select(Salida.nombre).where(Salida.jornada_fecha == fecha, Salida.tramo_id == tramo_id)).all())
    # cada estación arranca en un árbol distinto: a la misma hora y actividad no se repiten nombres
    giro = next(i for i, t in enumerate(TRAMOS) if t["id"] == tramo_id) % len(NOMBRES_PARCHE)
    nombres = NOMBRES_PARCHE[giro:] + NOMBRES_PARCHE[:giro]
    for vuelta in range(1, 100):
        for base in nombres:
            nombre = f"Parche {base}" if vuelta == 1 else f"Parche {base} {vuelta}"
            if nombre not in usados:
                return nombre
    raise RuntimeError("sin nombres")


def asegurar_parches(session: Session, fecha: date) -> None:
    """Un parche por estación, hora y actividad para cada grupo de edad abierto. Idempotente.

    Si el catálogo de estaciones cambió (la base viene de antes), completa los parches de las
    estaciones nuevas y quita los de las retiradas que nadie usa todavía.
    """
    activos = {t["id"] for t in TRAMOS}
    esperados = len(TRAMOS) * len(FRANJAS) * len(ACTIVIDADES)
    cambios = False
    for seg in segmentos_abiertos():
        salidas = session.exec(select(Salida).where(Salida.jornada_fecha == fecha, Salida.segmento == seg)).all()
        vigentes = {(s.tramo_id, s.franja, s.actividad) for s in salidas if s.tramo_id in activos}
        if len(salidas) == len(vigentes) == esperados:
            continue
        for t in TRAMOS:
            for f in FRANJAS:
                for a in ACTIVIDADES:
                    if (t["id"], f["id"], a["id"]) in vigentes:
                        continue
                    session.add(Salida(jornada_fecha=fecha, nombre=_nombre_libre(session, fecha, t["id"]),
                                       tramo_id=t["id"], segmento=seg, franja=f["id"], actividad=a["id"]))
                    session.flush()
                    cambios = True
        for s in salidas:
            if s.tramo_id not in activos and not _salida_en_uso(session, s.id):
                session.delete(s)
                cambios = True
    if cambios:
        session.commit()


def _salida_en_uso(session: Session, salida_id: int) -> bool:
    return any(
        session.exec(select(m.id).where(m.salida_id == salida_id)).first() is not None
        for m in (Inscripcion, Grupo, ChatMiembro, ChatMensaje)
    )


def _base_parche(s: Salida | Grupo) -> dict:
    t = tramo_info(s.tramo_id)
    return {
        "id": s.id,
        "nombre": s.nombre,
        "tramo": {"id": t["id"], "nombre": t["nombre"], "comuna": t["comuna"]},
        "punto_encuentro": t["punto"],
        "referencia": t["referencia"],
        "hora_encuentro": s.franja,
        "hora_nombre": FRANJA_NOMBRE[s.franja],
        "actividad": s.actividad,
        "actividad_nombre": ACTIVIDADES_POR_ID[s.actividad]["nombre"],
    }


def _inscritos_por_salida(session: Session, fecha: date, salida_id: int | None = None) -> dict[int, list[Joven]]:
    """La gente de cada parche del domingo (o de uno solo), en una sola consulta.

    En Neon cada consulta es un viaje por la red: pedir a cada joven por separado eran ~750 consultas y
    "Mi parche" tardaba más de 10 s.
    """
    q = (select(Inscripcion.salida_id, Joven).join(Joven, Joven.id == Inscripcion.joven_id)
         .where(Inscripcion.jornada_fecha == fecha).order_by(Inscripcion.id))
    if salida_id is not None:
        q = q.where(Inscripcion.salida_id == salida_id)
    por_salida: dict[int, list[Joven]] = defaultdict(list)
    for sid, j in session.exec(q).all():
        por_salida[sid].append(j)
    return por_salida


def salida_json(session: Session, s: Salida, joven: Joven | None = None, inscritos: list[Joven] | None = None) -> dict:
    if inscritos is None:
        inscritos = _inscritos_por_salida(session, s.jornada_fecha, s.id).get(s.id, [])
    ritmo = _ritmo_mediano(inscritos)
    return {
        **_base_parche(s),
        "inscritos": len(inscritos),
        "universidades": len({j.universidad for j in inscritos}),
        "ritmo_nombre": RITMO_NOMBRE[ritmo] if ritmo else None,
        "es_mio": bool(joven and any(j.id == joven.id for j in inscritos)),
        "para_ti": bool(joven and s.tramo_id == joven.tramo_id and s.actividad == joven.actividad),
    }


def listar_parches(
    session: Session, joven: Joven, tramo: str | None = None, franja: str | None = None, actividad: str | None = None,
) -> dict:
    """Los parches del próximo domingo para el grupo de edad del joven. Solo cifras, nunca nombres."""
    j = jornada_abierta(session)
    q = select(Salida).where(Salida.jornada_fecha == j.fecha, Salida.segmento == SEGMENTO_EDAD[joven.rango_edad])
    if tramo:
        q = q.where(Salida.tramo_id == tramo)
    if franja:
        q = q.where(Salida.franja == franja)
    if actividad:
        q = q.where(Salida.actividad == actividad)
    por_salida = _inscritos_por_salida(session, j.fecha)
    parches = [salida_json(session, s, joven, por_salida.get(s.id, [])) for s in session.exec(q).all()]
    parches.sort(key=lambda p: (
        not p["es_mio"], FRANJA_ORDEN[p["hora_encuentro"]], not p["para_ti"], -p["inscritos"],
        ORDEN_ACTIVIDAD[p["actividad"]], p["tramo"]["nombre"], p["id"],
    ))
    return {
        "jornada": {"fecha": str(j.fecha), "estado": j.estado, "inicio": JORNADA_INICIO, "fin": JORNADA_FIN},
        "parches": parches,
    }


def _inscripcion(session: Session, joven_id: str, fecha: date) -> Inscripcion | None:
    return session.exec(
        select(Inscripcion).where(Inscripcion.joven_id == joven_id, Inscripcion.jornada_fecha == fecha)
    ).first()


def quitar_de_la_jornada(session: Session, joven_id: str, fecha: date) -> None:
    from .chat import salir_de_la_jornada

    session.exec(delete(Asignacion).where(Asignacion.joven_id == joven_id, Asignacion.jornada_fecha == fecha))
    session.exec(delete(Inscripcion).where(Inscripcion.joven_id == joven_id, Inscripcion.jornada_fecha == fecha))
    session.exec(delete(Espera).where(Espera.joven_id == joven_id, Espera.jornada_fecha == fecha))
    salir_de_la_jornada(session, joven_id, fecha)  # sin parche, tampoco queda en su chat


def unirse(session: Session, joven: Joven, salida_id: int) -> None:
    j = jornada_abierta(session)
    if joven.suspendido:
        raise LookupError("Tu cuenta está en revisión: por ahora no puedes unirte a parches")
    s = session.get(Salida, salida_id)
    if not s or s.jornada_fecha != j.fecha:
        raise LookupError("Ese parche no es de este domingo")
    if s.segmento != SEGMENTO_EDAD[joven.rango_edad]:
        raise LookupError("Ese parche no es para tu grupo de edad")
    actual = _inscripcion(session, joven.id, j.fecha)
    if actual and actual.salida_id == s.id:
        return
    quitar_de_la_jornada(session, joven.id, j.fecha)
    if joven.pausa_fecha == j.fecha:
        joven.pausa_fecha = None
        session.add(joven)
    session.add(Inscripcion(salida_id=s.id, joven_id=joven.id, jornada_fecha=j.fecha))
    session.flush()
    if j.estado == "emparejada":
        _ubicar_tarde(session, joven, s)
    session.commit()


def salir(session: Session, joven: Joven) -> None:
    quitar_de_la_jornada(session, joven.id, jornada_abierta(session).fecha)
    session.commit()


# ---------------------------------------------------------------- emparejamiento automático

def _candidatas(session: Session, joven: Joven, fecha: date, estricto: bool = True) -> list[tuple[Salida, list[Joven]]]:
    """Parches del domingo que le sirven al joven, con la gente ya inscrita en cada uno.

    Estricto: misma actividad y, si los declaró, misma estación y misma hora.
    Relajado (para sugerencias): basta la misma familia de actividad (a pie / sobre ruedas).
    """
    salidas = session.exec(select(Salida).where(
        Salida.jornada_fecha == fecha, Salida.segmento == SEGMENTO_EDAD[joven.rango_edad],
    )).all()
    por_salida = _inscritos_por_salida(session, fecha)
    pares = []
    for s in salidas:
        if estricto:
            if s.actividad != joven.actividad:
                continue
            if joven.tramo_id and s.tramo_id != joven.tramo_id:
                continue
            if joven.franja and s.franja != joven.franja:
                continue
        elif ACTIVIDADES_POR_ID[s.actividad]["familia"] != ACTIVIDADES_POR_ID[joven.actividad]["familia"]:
            continue
        gente = [x for x in por_salida.get(s.id, []) if not x.suspendido and x.id != joven.id]
        pares.append((s, gente))
    return pares


def _distancia_quiz(joven: Joven, gente: list[Joven]) -> float:
    """Qué tan lejos está el estilo del joven del promedio del parche. 0 si falta información."""
    mio = quiz_de(joven)
    otros = [q for q in (quiz_de(x) for x in gente) if q]
    if not mio or not otros:
        return 0.0
    promedio = [sum(c) / len(otros) for c in zip(*otros)]
    return round(sum(abs(a - b) for a, b in zip(mio, promedio)) / len(mio), 3)


def _afinidad(joven: Joven, s: Salida, gente: list[Joven]) -> tuple:
    """Menor es mejor: la misma idea de distancia del k-means, aplicada a elegir parche.

    Primero lo estructural (actividad, hora, ritmo, cercanía); el quiz solo desempata al final.
    """
    ritmo = _ritmo_mediano(gente)
    return (
        s.actividad != joven.actividad,
        abs(FRANJA_ORDEN[s.franja] - FRANJA_ORDEN[joven.franja]) if joven.franja else 0,
        abs(RITMO_ORDEN[ritmo] - RITMO_ORDEN[joven.ritmo]) if ritmo else 0,
        0 if joven.tramo_id == s.tramo_id else abs(tramo_info(s.tramo_id)["comuna"] - joven.comuna),
        _distancia_quiz(joven, gente),
        -len(gente),
        s.id or 0,
    )


def _traer_simulados(session: Session, joven: Joven, fecha: date) -> int:
    """El parche que pidió una persona real está vacío, así que se le suman jóvenes simulados.

    Los 1.500 simulados se reparten en cientos de combinaciones de estación, hora y actividad; con
    solo elegir una, la probabilidad de que ya tenga gente es baja y el match nunca llegaba. Se
    mueven desde otros parches (los más llenos), con su misma actividad y las más parecidas en
    estación, hora y ritmo, hasta dejar GRUPO_OBJETIVO personas contando a quien llega. Devuelve
    cuántos se sumaron; 0 si no hay parche exacto o no quedan simulados.
    """
    objetivo = [s for s, _ in _candidatas(session, joven, fecha)]
    if not objetivo:
        return 0
    destino = min(objetivo, key=lambda s: s.id or 0)
    simulados = session.exec(select(Joven).where(
        Joven.sintetico == True, Joven.suspendido == False,  # noqa: E712
        Joven.actividad == destino.actividad,
    )).all()
    simulados = [x for x in simulados if SEGMENTO_EDAD[x.rango_edad] == destino.segmento and x.pausa_fecha != fecha]
    if not simulados:
        return 0
    inscritas = Counter(i.joven_id for i in session.exec(select(Inscripcion).where(Inscripcion.jornada_fecha == fecha)).all())
    enparche = {i.joven_id: i.salida_id for i in session.exec(select(Inscripcion).where(Inscripcion.jornada_fecha == fecha)).all()}
    tamano = Counter(enparche.values())
    elegibles = [x for x in simulados if enparche.get(x.id) != destino.id]
    elegibles.sort(key=lambda x: (
        x.tramo_id != destino.tramo_id,
        abs(FRANJA_ORDEN[x.franja] - FRANJA_ORDEN[destino.franja]) if x.franja else 0,
        abs(RITMO_ORDEN[x.ritmo] - RITMO_ORDEN[joven.ritmo]),
        x.id not in inscritas,  # primero los que ya tienen parche: quien no, no se movería de nada
        -tamano.get(enparche.get(x.id), 0),
        x.id,
    ))
    sumados = 0
    for x in elegibles[: max(config.GRUPO_OBJETIVO - 1, config.GRUPO_MIN)]:
        unirse(session, x, destino.id)
        sumados += 1
    return sumados


def emparejar_automatico(
    session: Session, joven: Joven, momento: datetime | None = None, avisar_telegram: bool = True,
) -> dict:
    """Une al joven al parche que ya tiene gente con sus mismas características.

    Si no existe ninguno, lo deja en lista de espera: el tick lo reintenta cada pocos
    minutos y le avisa (app y Telegram) apenas aparezca uno. Al entrar en espera, si
    vinculó Telegram, le llega por el chat la propuesta del parche que más se ajusta.
    """
    momento = momento or ahora()
    j = jornada_abierta(session, momento)
    if joven.suspendido or joven.pausa_fecha == j.fecha:
        return {"resultado": "no_aplica"}
    if _inscripcion(session, joven.id, j.fecha):
        return {"resultado": "ya_inscrito"}
    con_gente = [(s, gente) for s, gente in _candidatas(session, joven, j.fecha) if gente]
    if not con_gente and config.RELLENAR_CON_SIMULADOS and not joven.sintetico and _traer_simulados(session, joven, j.fecha):
        con_gente = [(s, gente) for s, gente in _candidatas(session, joven, j.fecha) if gente]
    if con_gente:
        s, gente = min(con_gente, key=lambda par: _afinidad(joven, par[0], par[1]))
        unirse(session, joven, s.id)  # también borra la espera si la había
        return {"resultado": "asignado", "salida_id": s.id}
    if not session.exec(select(Espera).where(Espera.joven_id == joven.id, Espera.jornada_fecha == j.fecha)).first():
        session.add(Espera(joven_id=joven.id, jornada_fecha=j.fecha))
        session.commit()
        if avisar_telegram and joven.telegram_chat_id:
            from . import telegram

            propuesta = telegram.propuesta_para(session, joven)
            if propuesta:
                telegram.enviar(joven.telegram_chat_id, *propuesta)
    return {"resultado": "en_espera"}


def cancelar_espera(session: Session, joven: Joven) -> None:
    session.exec(delete(Espera).where(Espera.joven_id == joven.id))
    session.commit()


def sugerencias_para(session: Session, joven: Joven, limite: int = 5) -> list[dict]:
    """Parches parecidos para quien lleva rato en espera: primero los que ya tienen gente."""
    j = jornada_abierta(session)
    pares = _candidatas(session, joven, j.fecha, estricto=False)
    pares.sort(key=lambda par: (not par[1], _afinidad(joven, par[0], par[1])))
    return [salida_json(session, s, joven, gente) for s, gente in pares[:limite]]


def notificar(session: Session, joven: Joven, titulo: str, cuerpo: str, botones: list | None = None) -> None:
    """Aviso dentro de la app y, si el joven vinculó su cuenta, también por Telegram (con botones)."""
    session.add(Notificacion(joven_id=joven.id, titulo=titulo, cuerpo=cuerpo))
    session.commit()
    if joven.telegram_chat_id:
        from html import escape

        from . import telegram

        telegram.enviar(joven.telegram_chat_id, f"<b>{escape(titulo)}</b>\n{escape(cuerpo)}", botones)


def revisar_esperas(session: Session, momento: datetime | None = None) -> int:
    """En cada tick: si a alguien en espera ya le sirve un parche con gente, lo une y le avisa."""
    momento = momento or ahora()
    j = jornada_abierta(session, momento)
    # las esperas de domingos que ya pasaron no sirven: se limpian para no crecer sin fin
    session.exec(delete(Espera).where(Espera.jornada_fecha < j.fecha))
    session.commit()
    unidos = 0
    for e in session.exec(select(Espera).where(Espera.jornada_fecha == j.fecha)).all():
        joven = session.get(Joven, e.joven_id)
        if joven is None or joven.suspendido:
            session.delete(e)
            session.commit()
            continue
        r = emparejar_automatico(session, joven, momento)
        if r["resultado"] == "asignado":
            s = session.get(Salida, r["salida_id"])
            notificar(
                session, joven, "¡Encontramos parche para ti!",
                f"Te unimos al {s.nombre} en {tramo_info(s.tramo_id)['nombre']} a las {FRANJA_NOMBRE[s.franja]}: "
                "hay gente con tus mismos planes. Abre la app para conocer a tu grupo.",
                botones=[[("Ver mi parche", "parche")]],
            )
            unidos += 1
    return unidos


# ---------------------------------------------------------------- foro comunal

def foro_lista(session: Session, joven: Joven, categoria: str | None = None, limite: int = 50) -> list[dict]:
    q = select(MensajeForo).order_by(MensajeForo.creado_en.desc(), MensajeForo.id.desc()).limit(limite)
    if categoria:
        q = q.where(MensajeForo.categoria == categoria)
    return [{
        "id": m.id, "nombre": m.nombre, "universidad": m.universidad, "categoria": m.categoria,
        "texto": m.texto, "creado_en": m.creado_en.isoformat(), "es_mio": m.joven_id == joven.id,
    } for m in session.exec(q).all()]


def foro_publicar(session: Session, joven: Joven, categoria: str, texto: str) -> MensajeForo:
    if joven.suspendido:
        raise LookupError("Tu cuenta está en revisión: por ahora no puedes publicar en el foro")
    m = MensajeForo(joven_id=joven.id, nombre=joven.nombre,
                    universidad=UNIVERSIDADES_POR_ID[joven.universidad]["corto"],
                    categoria=categoria, texto=texto.strip()[:config.FORO_MAX])
    session.add(m)
    session.commit()
    session.refresh(m)
    return m


def foro_borrar(session: Session, joven: Joven, mensaje_id: int) -> None:
    m = session.get(MensajeForo, mensaje_id)
    if not m or m.joven_id != joven.id:
        raise LookupError("Solo puedes borrar tus propios mensajes")
    session.delete(m)
    session.commit()


# ---------------------------------------------------------------- grupos del sábado (k-means)

def _experiencia(session: Session, joven_id: str, antes_de: date) -> int:
    idas = session.exec(select(Encuesta.id).where(
        Encuesta.joven_id == joven_id, Encuesta.asistio == True, Encuesta.jornada_fecha < antes_de,  # noqa: E712
    ).limit(EXPERIENCIA_MAX)).all()
    return len(idas)


def _experiencias(session: Session, antes_de: date, ids: list[str] | None = None) -> dict[str, int]:
    """Lo mismo que _experiencia para muchos jóvenes a la vez (todos, o solo `ids`), en una consulta."""
    q = select(Encuesta.joven_id, func.count()).where(
        Encuesta.asistio == True, Encuesta.jornada_fecha < antes_de,  # noqa: E712
    ).group_by(Encuesta.joven_id)
    if ids is not None:
        q = q.where(Encuesta.joven_id.in_(ids))
    return {joven_id: min(n, EXPERIENCIA_MAX) for joven_id, n in session.exec(q).all()}


def respuestas_quiz(joven: Joven) -> dict[int, str] | None:
    """Lo que respondió en el quiz, {pregunta: opción}, o None si no lo respondió."""
    if not joven.quiz_respuestas:
        return None
    try:
        return {int(k): str(v) for k, v in joven.quiz_respuestas.items()}
    except (AttributeError, TypeError, ValueError):
        return None


def vector_quiz(respuestas: dict[int, str]) -> str:
    """Las respuestas como el vector de texto que se guarda en Joven.quiz: "1,0.5,1,1,0"."""
    return ",".join(f"{v:g}" for v in puntuar_quiz(respuestas))


def quiz_de(joven: Joven) -> tuple[float, ...] | None:
    """El vector del quiz para k-means (5 valores de 0 a 1), o None si no lo respondió.

    Sale de las respuestas originales, así que si se ajusta el valor de una opción en el catálogo,
    todos quedan recalculados. Las cuentas que respondieron antes de guardarlas usan el vector guardado.
    """
    respuestas = respuestas_quiz(joven)
    if respuestas:
        try:
            return puntuar_quiz(respuestas)
        except (KeyError, StopIteration):
            pass  # respuestas de una versión vieja del quiz: se usa el vector guardado
    if not joven.quiz:
        return None
    try:
        valores = tuple(float(x) for x in joven.quiz.split(","))
        return valores if len(valores) == 5 else None
    except ValueError:
        return None


def guardar_quiz(session: Session, joven: Joven, respuestas: dict[int, str]) -> None:
    """Guarda lo que respondió (JSON) y su vector. No se devuelve ni se muestra a nadie."""
    joven.quiz_respuestas = {str(k): v for k, v in sorted(respuestas.items())}
    joven.quiz = vector_quiz(respuestas)
    session.add(joven)
    session.commit()


def _participante(session: Session, joven: Joven, s: Salida, experiencia: int | None = None) -> Participante:
    if experiencia is None:
        experiencia = _experiencia(session, joven.id, s.jornada_fecha)
    return Participante(id=joven.id, tramo=s.tramo_id, franja=s.franja, actividad=s.actividad, ritmo=joven.ritmo,
                        rango_edad=joven.rango_edad, experiencia=experiencia, quiz=quiz_de(joven))


def _nuevo_grupo(session: Session, s: Salida, nombre: str, nivel: str = "armado") -> Grupo:
    g = Grupo(jornada_fecha=s.jornada_fecha, salida_id=s.id, nombre=nombre, tramo_id=s.tramo_id,
              segmento=s.segmento, franja=s.franja, actividad=s.actividad, nivel=nivel)
    session.add(g)
    session.flush()
    return g


def armar_grupos(session: Session, fecha: date) -> dict:
    """Sábado 5:00 p. m. Idempotente: si ya se armaron, solo devuelve el resumen.

    1. Quien quedó en un parche de menos de 3 se suma al parche compatible más parecido.
    2. Cada parche se parte en grupos de 3 a 6 con k-means (ver matching.py).
    """
    jornada = session.get(Jornada, fecha) or Jornada(fecha=fecha)
    if jornada.estado == "finalizada":
        raise ValueError("La jornada ya terminó")
    if jornada.estado == "emparejada":
        return {**resumen_jornada(session, fecha), "movidos": 0}

    salidas = {s.id: s for s in session.exec(select(Salida).where(Salida.jornada_fecha == fecha)).all()}
    # Inscripciones con su joven y la experiencia de todos, en tres consultas (no tres por persona: en Neon,
    # "Armar los grupos" tardaba más de un minuto)
    inscripciones: dict[str, Inscripcion] = {}
    jovenes: dict[str, Joven] = {}
    for ins, joven in session.exec(select(Inscripcion, Joven).join(Joven, Joven.id == Inscripcion.joven_id)
                                   .where(Inscripcion.jornada_fecha == fecha).order_by(Inscripcion.id)).all():
        inscripciones[joven.id], jovenes[joven.id] = ins, joven
    experiencias = _experiencias(session, fecha)
    propuestas: dict[int, GrupoPropuesto] = {}
    for joven_id, ins in inscripciones.items():
        joven, s = jovenes[joven_id], salidas[ins.salida_id]
        if joven.suspendido:
            continue
        gp = propuestas.setdefault(s.id, GrupoPropuesto(s.tramo_id, s.segmento, s.franja, s.actividad, "moderado"))
        gp.miembros.append(_participante(session, joven, s, experiencias.get(joven.id, 0)))
    for gp in propuestas.values():
        gp.ritmo = RITMO_POR_ORDEN[round(median(p.ritmo_orden for p in gp.miembros))]

    # 1. parches que no llegaron al mínimo
    ajustes: dict[str, list[str]] = {}
    for sid in sorted(propuestas, key=lambda k: (len(propuestas[k].miembros), k)):
        propio = propuestas[sid]
        if not 0 < len(propio.miembros) < config.GRUPO_MIN:
            continue
        for p in list(propio.miembros):
            otros = {k: v for k, v in propuestas.items() if k != sid and v.miembros}
            destino = mejor_grupo_para(p, list(otros.values()), maximo=10**6)
            if destino is None:
                continue
            nuevo_sid = next(k for k, v in otros.items() if v is destino)
            propio.miembros.remove(p)
            destino.miembros.append(p)
            ajustes[p.id] = destino.ajustes(p)
            inscripciones[p.id].salida_id = nuevo_sid
            session.add(inscripciones[p.id])

    # 2. k-means dentro de cada parche. Primero todos los grupos y después sus integrantes: dos INSERT por
    # lotes en vez de uno por grupo (en Neon cada uno es un viaje por la red)
    armados: list[tuple[Grupo, list[Participante]]] = []
    for sid, gp in propuestas.items():
        if not gp.miembros:
            continue
        s = salidas[sid]
        grupos = agrupar(gp.miembros, config.GRUPO_MIN, config.GRUPO_OBJETIVO, config.GRUPO_MAX)
        for idx, miembros in enumerate(grupos):
            nombre = s.nombre if len(grupos) == 1 else f"{s.nombre} {LETRAS[idx]}"
            nivel = "juntado" if any(p.id in ajustes for p in miembros) else "armado"
            armados.append((Grupo(jornada_fecha=s.jornada_fecha, salida_id=s.id, nombre=nombre, tramo_id=s.tramo_id,
                                  segmento=s.segmento, franja=s.franja, actividad=s.actividad, nivel=nivel), miembros))
    session.add_all([g for g, _ in armados])
    session.flush()  # los grupos ya tienen id
    for g, miembros in armados:
        for p in miembros:
            session.add(Asignacion(grupo_id=g.id, joven_id=p.id, jornada_fecha=fecha,
                                   ajustes=",".join(ajustes.get(p.id, []))))

    jornada.estado = "emparejada"
    jornada.emparejada_en = ahora()
    session.add(jornada)
    session.commit()

    # El aviso del sábado, empatado con Telegram: a cada cuenta real le llega su grupo
    # dentro de la app y, si vinculó el bot, también al chat.
    from . import clima

    reales = session.exec(
        select(Joven, Grupo).join(Asignacion, Asignacion.joven_id == Joven.id).join(Grupo, Grupo.id == Asignacion.grupo_id)
        .where(Asignacion.jornada_fecha == fecha, Joven.sintetico == False).order_by(Asignacion.id)  # noqa: E712
    ).all()
    for joven, grupo in reales:
        tiempo = clima.resumen(fecha, grupo.franja)
        notificar(
            session, joven, "¡Tu grupo del domingo está listo!",
            f"Quedaste en el {grupo.nombre} en {tramo_info(grupo.tramo_id)['nombre']} a las "
            f"{FRANJA_NOMBRE[grupo.franja]}. ¿Vas?" + (f"\n{tiempo}" if tiempo else ""),
            botones=[[("✅ Confirmo, voy", "confirmo"), ("❌ No voy", "novoy")], [("Ver mi grupo", "parche")]],
        )
    return {**resumen_jornada(session, fecha), "movidos": len(ajustes)}


def _ubicar_tarde(session: Session, joven: Joven, s: Salida) -> None:
    """Quien se une después del sábado entra al grupo con cupo más parecido, o abre uno nuevo."""
    grupos = session.exec(select(Grupo).where(Grupo.salida_id == s.id).order_by(Grupo.id)).all()
    por_grupo: dict[int, list[Joven]] = defaultdict(list)
    for grupo_id, j in session.exec(
        select(Asignacion.grupo_id, Joven).join(Joven, Joven.id == Asignacion.joven_id)
        .where(Asignacion.grupo_id.in_([g.id for g in grupos])).order_by(Asignacion.id)
    ).all():
        por_grupo[grupo_id].append(j)
    experiencias = _experiencias(session, s.jornada_fecha, [j.id for js in por_grupo.values() for j in js])
    miembros = [[_participante(session, j, s, experiencias.get(j.id, 0)) for j in por_grupo[g.id]] for g in grupos]
    idx = grupo_mas_cercano(_participante(session, joven, s), miembros, config.GRUPO_MAX)
    if idx is None:
        nombre = s.nombre if not grupos else f"{s.nombre} {LETRAS[len(grupos)]}"
        if len(grupos) == 1 and grupos[0].nombre == s.nombre:
            grupos[0].nombre = f"{s.nombre} A"
            session.add(grupos[0])
            nombre = f"{s.nombre} B"
        destino = _nuevo_grupo(session, s, nombre)
    else:
        destino = grupos[idx]
    session.add(Asignacion(grupo_id=destino.id, joven_id=joven.id, jornada_fecha=s.jornada_fecha, tarde=True))


def resumen_jornada(session: Session, fecha: date) -> dict:
    asign = session.exec(select(Asignacion).where(Asignacion.jornada_fecha == fecha)).all()
    tamanos = Counter(a.grupo_id for a in asign)
    return {
        "fecha": str(fecha),
        "inscritos": len(session.exec(select(Inscripcion.id).where(Inscripcion.jornada_fecha == fecha)).all()),
        "grupos": len(tamanos),
        "emparejados": len(asign),
        "solos": sum(1 for n in tamanos.values() if n == 1),
    }


# ---------------------------------------------------------------- estado para la app

def _asignacion(session: Session, joven_id: str, fecha: date) -> Asignacion | None:
    return session.exec(
        select(Asignacion).where(Asignacion.joven_id == joven_id, Asignacion.jornada_fecha == fecha)
    ).first()


def grupo_json(session: Session, grupo: Grupo, yo: str | None = None) -> dict:
    """Lo que ve quien está dentro del grupo: primeros nombres, universidad y si confirmaron."""
    asign = session.exec(select(Asignacion).where(Asignacion.grupo_id == grupo.id)).all()
    miembros, jovenes = [], []
    for a in sorted(asign, key=lambda a: (a.joven_id != yo, a.id or 0)):
        joven = session.get(Joven, a.joven_id)
        if joven:
            jovenes.append(joven)
            miembros.append({
                "ref": a.id,  # referencia opaca para reportar, no identifica a la persona
                "nombre": joven.nombre,
                "universidad": UNIVERSIDADES_POR_ID[joven.universidad]["corto"],
                "actividad": joven.actividad,
                "estado": a.estado,
                "soy_yo": a.joven_id == yo,
            })
    ritmo = _ritmo_mediano(jovenes) or "moderado"
    return {
        **_base_parche(grupo),
        "ritmo": ritmo,
        "ritmo_nombre": RITMO_NOMBRE[ritmo],
        "miembros": miembros,
        "confirmados": sum(1 for a in asign if a.estado == "confirmado"),
    }


def encuesta_abierta(session: Session, joven: Joven, momento: datetime) -> dict | None:
    """La última jornada terminada en la que la persona tuvo grupo, si aún está en plazo."""
    finalizadas = session.exec(
        select(Jornada).where(Jornada.estado == "finalizada").order_by(Jornada.fecha.desc())
    ).all()
    for j in finalizadas:
        if momento.date() > j.fecha + timedelta(days=config.DIAS_ENCUESTA):
            return None
        a = _asignacion(session, joven.id, j.fecha)
        if not a:
            continue
        grupo = session.get(Grupo, a.grupo_id)
        ya = session.exec(
            select(Encuesta).where(Encuesta.joven_id == joven.id, Encuesta.jornada_fecha == j.fecha)
        ).first()
        return {
            "jornada_fecha": str(j.fecha),
            "grupo_nombre": grupo.nombre if grupo else None,
            "respondida": ya is not None,
        }
    return None


def estado_para(session: Session, joven: Joven, momento: datetime | None = None) -> dict:
    """sin_parche | en_espera | inscrito (el grupo se arma el sábado) | asignado | pausado | suspendido"""
    momento = momento or ahora()
    j = jornada_abierta(session, momento)
    info = {
        "jornada": {"fecha": str(j.fecha), "estado": j.estado, "inicio": JORNADA_INICIO, "fin": JORNADA_FIN},
        "estado": "sin_parche",
        "mi_respuesta": None,
        "ajustes": [],
        "tarde": False,
        "salida": None,
        "grupo": None,
        "espera": None,
        "encuesta": encuesta_abierta(session, joven, momento),
        "clima": None,
        "racha": racha_para(session, joven),
    }
    if joven.suspendido:
        info["estado"] = "suspendido"
        return info
    if joven.pausa_fecha == j.fecha:
        info["estado"] = "pausado"
        return info
    ins = _inscripcion(session, joven.id, j.fecha)
    esp = session.exec(select(Espera).where(Espera.joven_id == joven.id, Espera.jornada_fecha == j.fecha)).first()
    if esp and not ins:
        minutos = max(0, int((momento - esp.creado_en).total_seconds() // 60))
        # El parche más parecido aunque esté vacío: siempre hace falta alguien con la iniciativa.
        candidatas = _candidatas(session, joven, j.fecha) or _candidatas(session, joven, j.fecha, estricto=False)
        mas = min(candidatas, key=lambda par: _afinidad(joven, par[0], par[1])) if candidatas else None
        info["estado"] = "en_espera"
        info["espera"] = {
            "desde": esp.creado_en.isoformat(),
            "minutos": minutos,
            "minutos_para_sugerencias": config.ESPERA_MINUTOS,
            "mas_parecido": salida_json(session, mas[0], joven, mas[1]) if mas else None,
            # pasado el lapso de espera, la app muestra parches parecidos o disponibles
            "sugerencias": sugerencias_para(session, joven) if minutos >= config.ESPERA_MINUTOS else [],
        }
    if ins:
        info["estado"] = "inscrito"
        info["salida"] = salida_json(session, session.get(Salida, ins.salida_id), joven)
    a = _asignacion(session, joven.id, j.fecha)
    if a:
        info.update({
            "estado": "asignado",
            "mi_respuesta": a.estado,
            "ajustes": [x for x in a.ajustes.split(",") if x],
            "tarde": a.tarde,
            "grupo": grupo_json(session, session.get(Grupo, a.grupo_id), yo=joven.id),
        })
    from . import clima

    hora = (info["grupo"] or info["salida"] or {}).get("hora_encuentro") or JORNADA_INICIO
    info["clima"] = clima.pronostico(j.fecha, hora)
    return info


def _fue(asignacion: Asignacion, encuesta: Encuesta | None) -> bool:
    """Si fue ese domingo: lo que dijo en la encuesta y, si no la respondió, si había confirmado."""
    return encuesta.asistio if encuesta else asignacion.estado == "confirmado"


def racha_para(session: Session, joven: Joven) -> dict:
    """Domingos seguidos que ha ido, contando hacia atrás desde el último que ya terminó.

    actual: la racha viva (se rompe si faltó el último domingo). mejor: la más larga. total: todos.
    """
    finalizadas = set(session.exec(select(Jornada.fecha).where(Jornada.estado == "finalizada")).all())
    encuestas = {e.jornada_fecha: e for e in session.exec(select(Encuesta).where(Encuesta.joven_id == joven.id)).all()}
    fue = sorted(
        a.jornada_fecha
        for a in session.exec(select(Asignacion).where(Asignacion.joven_id == joven.id)).all()
        if a.jornada_fecha in finalizadas and _fue(a, encuestas.get(a.jornada_fecha))
    )
    mejor = seguidas = 0
    for i, fecha in enumerate(fue):
        seguidas = seguidas + 1 if i and fecha - fue[i - 1] == timedelta(days=7) else 1
        mejor = max(mejor, seguidas)
    ultimo = max(finalizadas) if finalizadas else None
    actual = seguidas if fue and fue[-1] == ultimo else 0
    return {"actual": actual, "mejor": mejor, "total": len(fue)}


def historial_para(session: Session, joven: Joven, limite: int = 20) -> list[dict]:
    """Los domingos pasados del joven: su grupo, la gente que lo acompañó y si fue.

    Solo jornadas ya finalizadas; los nombres son los mismos que ya vio en su grupo esa semana.
    """
    asigns = session.exec(
        select(Asignacion).where(Asignacion.joven_id == joven.id).order_by(Asignacion.jornada_fecha.desc())
    ).all()
    filas: list[dict] = []
    for a in asigns:
        jornada = session.get(Jornada, a.jornada_fecha)
        grupo = session.get(Grupo, a.grupo_id) if a.grupo_id else None
        if jornada is None or jornada.estado != "finalizada" or grupo is None:
            continue
        enc = session.exec(
            select(Encuesta).where(Encuesta.joven_id == joven.id, Encuesta.jornada_fecha == a.jornada_fecha)
        ).first()
        filas.append({
            "fecha": str(a.jornada_fecha),
            "mi_respuesta": a.estado,
            "asistio": enc.asistio if enc else None,
            "volveria": enc.volveria if enc else None,
            "grupo": grupo_json(session, grupo, yo=joven.id),
        })
        if len(filas) >= limite:
            break
    return filas


def responder(session: Session, joven: Joven, va: bool) -> Asignacion:
    j = jornada_abierta(session)
    a = _asignacion(session, joven.id, j.fecha)
    if not a:
        raise LookupError("Tu grupo se arma el sábado a las 5:00 p. m. Ahí podrás confirmar")
    a.estado = "confirmado" if va else "declinado"
    a.respondido_en = ahora()
    session.add(a)
    session.commit()
    return a


def guardar_encuesta(session: Session, joven: Joven, asistio: bool, volveria: bool, bienestar: int | None) -> Encuesta:
    momento = ahora()
    abierta = encuesta_abierta(session, joven, momento)
    if not abierta:
        raise LookupError("No hay encuesta abierta")
    fecha = date.fromisoformat(abierta["jornada_fecha"])
    a = _asignacion(session, joven.id, fecha)
    enc = session.exec(select(Encuesta).where(Encuesta.joven_id == joven.id, Encuesta.jornada_fecha == fecha)).first()
    enc = enc or Encuesta(joven_id=joven.id, jornada_fecha=fecha, asistio=asistio, volveria=volveria)
    enc.grupo_id = a.grupo_id if a else None
    enc.asistio = asistio
    enc.volveria = volveria
    enc.bienestar = bienestar if asistio else None
    session.add(enc)
    session.commit()
    session.refresh(enc)
    return enc


def reportar(session: Session, joven: Joven, grupo_id: int, motivo: str, detalle: str = "", ref: int | None = None) -> Reporte:
    """Botón "Reportar un problema". Con suficientes reportes de personas distintas, la persona
    reportada sale de los parches hasta que moderación lo revise."""
    grupo = session.get(Grupo, grupo_id)
    mia = session.exec(
        select(Asignacion).where(Asignacion.grupo_id == grupo_id, Asignacion.joven_id == joven.id)
    ).first()
    if not grupo or not mia:
        raise LookupError("Solo puedes reportar algo de un grupo en el que estás")
    reportado_id = None
    if ref is not None:
        otra = session.get(Asignacion, ref)
        if not otra or otra.grupo_id != grupo_id or otra.joven_id == joven.id:
            raise LookupError("Esa persona no está en tu grupo")
        reportado_id = otra.joven_id
    rep = Reporte(reporta_id=joven.id, reportado_id=reportado_id, grupo_id=grupo_id,
                  jornada_fecha=grupo.jornada_fecha, motivo=motivo, detalle=detalle.strip()[:500])
    session.add(rep)
    session.commit()
    if reportado_id:
        quienes = set(session.exec(
            select(Reporte.reporta_id).where(Reporte.reportado_id == reportado_id, Reporte.revisado == False)  # noqa: E712
        ).all())
        if len(quienes) >= config.REPORTES_PARA_SUSPENDER:
            suspender(session, reportado_id)
    session.refresh(rep)
    return rep


def suspender(session: Session, joven_id: str) -> None:
    joven = session.get(Joven, joven_id)
    if not joven or joven.suspendido:
        return
    joven.suspendido = True
    session.add(joven)
    for fecha in session.exec(select(Jornada.fecha).where(Jornada.estado != "finalizada")).all():
        quitar_de_la_jornada(session, joven_id, fecha)
    session.commit()


def borrar_joven(session: Session, joven: Joven) -> None:
    """Derecho de supresión (Ley 1581 de 2012).

    Los reportes de seguridad se conservan para moderación, pero sin vínculo a la persona.
    """
    for r in session.exec(select(Reporte).where((Reporte.reporta_id == joven.id) | (Reporte.reportado_id == joven.id))).all():
        if r.reporta_id == joven.id:
            r.reporta_id = None
        if r.reportado_id == joven.id:
            r.reportado_id = None
        session.add(r)
    session.exec(delete(Encuesta).where(Encuesta.joven_id == joven.id))
    session.exec(delete(Asignacion).where(Asignacion.joven_id == joven.id))
    session.exec(delete(Inscripcion).where(Inscripcion.joven_id == joven.id))
    session.exec(delete(Espera).where(Espera.joven_id == joven.id))
    session.exec(delete(Notificacion).where(Notificacion.joven_id == joven.id))
    session.exec(delete(MensajeForo).where(MensajeForo.joven_id == joven.id))
    session.exec(delete(ChatMensaje).where(ChatMensaje.joven_id == joven.id))
    session.exec(delete(ChatMiembro).where(ChatMiembro.joven_id == joven.id))
    session.delete(joven)
    session.commit()
