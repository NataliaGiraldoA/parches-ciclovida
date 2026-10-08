"""Chat del parche: opcional, solo entre quienes deciden unirse.

- Cada parche (estación + hora + actividad de un domingo) tiene su chat.
- Unirse es opcional. Quien entra ve el chat y es visto en él con su primer nombre y su universidad,
  lo mismo que ve su grupo. Quien no entra no ve nombres ni mensajes: solo cuántos hay en el chat.
- Al cambiarse o salirse del parche, sale también de su chat.
- En la demo, algunos jóvenes simulados del parche entran al chat y conversan con Gemini según su
  personalidad del JSON (ver chat_simulado.py). En la app van marcados como simulados con IA.
"""

from __future__ import annotations

import hashlib

from sqlmodel import Session, delete, select

from . import config, services
from .catalog import ACTIVIDADES_POR_ID, FRANJA_NOMBRE, tramo_info, UNIVERSIDADES_POR_ID
from .models import Asignacion, ChatMensaje, ChatMiembro, Inscripcion, Joven, Salida

MAX_MENSAJES = 80  # los últimos que se devuelven al abrir el chat


def sala_de(session: Session, joven: Joven) -> Salida | None:
    """El parche del joven este domingo, si tiene uno."""
    j = services.jornada_abierta(session)
    ins = services._inscripcion(session, joven.id, j.fecha)
    return session.get(Salida, ins.salida_id) if ins else None


def _miembro(session: Session, salida_id: int, joven_id: str) -> ChatMiembro | None:
    return session.exec(
        select(ChatMiembro).where(ChatMiembro.salida_id == salida_id, ChatMiembro.joven_id == joven_id)
    ).first()


def miembros(session: Session, salida_id: int) -> list[Joven]:
    filas = session.exec(select(ChatMiembro).where(ChatMiembro.salida_id == salida_id).order_by(ChatMiembro.id)).all()
    jovenes = [session.get(Joven, m.joven_id) for m in filas]
    return [j for j in jovenes if j is not None]


def simulados_en_chat(session: Session, salida_id: int) -> list[Joven]:
    return [j for j in miembros(session, salida_id) if j.sintetico]


def _elegir_simulados(session: Session, salida: Salida, joven: Joven) -> list[Joven]:
    """Qué simulados del parche están en el chat: primero los de su grupo (si ya se armó), y el resto
    en un orden fijo por parche, hasta CHAT_MAX_SIMULADOS."""
    ids = session.exec(select(Inscripcion.joven_id).where(Inscripcion.salida_id == salida.id)).all()
    simulados = [j for j in (session.get(Joven, i) for i in ids) if j is not None and j.sintetico]
    mi_grupo: set[str] = set()
    a = services._asignacion(session, joven.id, salida.jornada_fecha)
    if a:
        mi_grupo = set(session.exec(select(Asignacion.joven_id).where(Asignacion.grupo_id == a.grupo_id)).all())

    def orden(j: Joven) -> tuple:
        return (j.id not in mi_grupo, hashlib.sha1(f"{salida.id}:{j.id}".encode()).hexdigest())

    return sorted(simulados, key=orden)[: config.CHAT_MAX_SIMULADOS]


def unirse(session: Session, joven: Joven) -> tuple[Salida, bool]:
    """Entra al chat de su parche. Devuelve el parche y si es la primera vez que entra."""
    if joven.suspendido:
        raise LookupError("Tu cuenta está en revisión: por ahora no puedes usar el chat")
    salida = sala_de(session, joven)
    if salida is None:
        raise LookupError("Primero necesitas un parche para este domingo")
    if _miembro(session, salida.id, joven.id):
        return salida, False
    session.add(ChatMiembro(salida_id=salida.id, joven_id=joven.id))
    for sim in _elegir_simulados(session, salida, joven):
        if not _miembro(session, salida.id, sim.id):
            session.add(ChatMiembro(salida_id=salida.id, joven_id=sim.id))
    session.commit()
    return salida, True


def salir(session: Session, joven: Joven) -> None:
    salida = sala_de(session, joven)
    if salida is not None:
        session.exec(delete(ChatMiembro).where(ChatMiembro.salida_id == salida.id, ChatMiembro.joven_id == joven.id))
        session.commit()


def salir_de_la_jornada(session: Session, joven_id: str, fecha) -> None:
    """Al cambiarse o salirse del parche, deja el chat del parche anterior (sin commit)."""
    salidas = select(Salida.id).where(Salida.jornada_fecha == fecha)
    session.exec(delete(ChatMiembro).where(ChatMiembro.joven_id == joven_id, ChatMiembro.salida_id.in_(salidas)))


def _uni(j: Joven) -> str:
    return UNIVERSIDADES_POR_ID[j.universidad]["corto"]


def publicar(session: Session, joven: Joven, texto: str) -> ChatMensaje:
    salida = sala_de(session, joven)
    if salida is None or not _miembro(session, salida.id, joven.id):
        raise LookupError("Únete al chat de tu parche para escribir")
    if joven.suspendido:
        raise LookupError("Tu cuenta está en revisión: por ahora no puedes usar el chat")
    texto = texto.strip()[:500]
    if not texto:
        raise LookupError("El mensaje está vacío")
    m = ChatMensaje(salida_id=salida.id, joven_id=joven.id, nombre=joven.nombre, universidad=_uni(joven),
                    simulado=joven.sintetico, texto=texto)
    session.add(m)
    session.commit()
    session.refresh(m)
    return m


def mensaje_json(m: ChatMensaje, yo: str) -> dict:
    return {"id": m.id, "nombre": m.nombre, "universidad": m.universidad, "simulado": m.simulado,
            "responde_a": m.responde_a, "texto": m.texto, "creado_en": m.creado_en.isoformat(),
            "es_mio": m.joven_id == yo}


def estado(session: Session, joven: Joven, despues_de: int | None = None) -> dict:
    """Lo que ve el joven del chat de su parche. Sin unirse, solo cuántos hay: ni nombres ni mensajes."""
    from . import asistente, chat_simulado

    salida = sala_de(session, joven)
    if salida is None:
        return {"disponible": False, "unido": False}
    gente = miembros(session, salida.id)
    info = {
        "disponible": True,
        "unido": any(j.id == joven.id for j in gente),
        "parche": {
            "id": salida.id, "nombre": salida.nombre, "estacion": tramo_info(salida.tramo_id)["nombre"],
            "hora": FRANJA_NOMBRE[salida.franja], "actividad": salida.actividad,
            "actividad_nombre": ACTIVIDADES_POR_ID[salida.actividad]["nombre"],
        },
        "en_el_chat": len(gente),
    }
    if not info["unido"]:
        return info
    q = select(ChatMensaje).where(ChatMensaje.salida_id == salida.id)
    if despues_de is not None:
        mensajes = session.exec(q.where(ChatMensaje.id > despues_de).order_by(ChatMensaje.id)).all()
    else:
        mensajes = list(reversed(session.exec(q.order_by(ChatMensaje.id.desc()).limit(MAX_MENSAJES)).all()))
    return {
        **info,
        "miembros": [{"nombre": j.nombre, "universidad": _uni(j), "simulado": j.sintetico, "soy_yo": j.id == joven.id}
                     for j in gente],
        "mensajes": [mensaje_json(m, joven.id) for m in mensajes],
        "escribiendo": chat_simulado.escribiendo(salida.id),
        "simulados_conversan": asistente.disponible(),
    }
