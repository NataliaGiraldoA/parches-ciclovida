"""Los jóvenes simulados conversan en el chat del parche, con Gemini y su personalidad del JSON.

Cada simulado del chat lleva una ficha sacada de app/datos/sinteticos.json: su perfil (Parchadito
social, Madrugador cumplido, Deportista o Contemplativo), sus respuestas del quiz «Tu estilo de
parche», su actividad, su ritmo, su edad y su universidad. Con una sola llamada a Gemini, que
devuelve JSON, se decide quién habla, en qué orden, a quién le contesta y qué dice cada uno.

Tres momentos:
- bienvenida: alguien real entra al chat (si está vacío, primero charlan entre ellos).
- respuesta: una persona real escribió. Pueden contestar varios (de 1 a 3) y reaccionar a lo que
  acaba de decir otro simulado, como en un chat de verdad.
- charla: el chat lleva un rato quieto y alguien real lo tiene abierto. Los simulados conversan
  entre ellos y a veces invitan a la persona real. Paran después de CHAT_CHARLA_MAX mensajes
  seguidos sin que escriba una persona real, para no hablar solos sin fin ni gastar llamadas.

Corre en segundo plano después de responderle a la app: mientras tanto, el chat muestra
"escribiendo…". Un solo turno por chat a la vez; si llegan mensajes en medio, se hace otro turno.

Qué se le envía a Gemini: las fichas de los simulados, los datos del parche y los últimos mensajes
del chat con el primer nombre de quien los escribió (de las personas reales, nada más: ni su
universidad ni otros datos). Está en el aviso de privacidad.

Sin GEMINI_API_KEY, los simulados solo saludan con un mensaje fijo según su perfil.
"""

from __future__ import annotations

import json
import logging
import re
import threading
import time

from sqlmodel import Session, select

from . import asistente, config, services, sinteticos
from .catalog import ACTIVIDADES_POR_ID, FRANJA_NOMBRE, QUIZ_PREGUNTAS, tramo_info, UNIVERSIDADES_POR_ID
from .db import engine
from .models import ChatMensaje, Joven, Salida

log = logging.getLogger("parches.chat")

HISTORIAL = 25  # mensajes recientes que ve Gemini
MAX_POR_TURNO = 5  # mensajes simulados como máximo por turno
_OPCION = {(p["id"], o["id"]): o["texto"] for p in QUIZ_PREGUNTAS for o in p["opciones"]}
_RITMO = {"tranquilo": "tranquilo", "moderado": "moderado", "rapido": "rápido"}

# Estado en memoria (el backend corre en una sola instancia, como el bot de Telegram).
_candados: dict[int, threading.Lock] = {}
_pendientes: set[int] = set()
_escribiendo: dict[int, set[str]] = {}
_reservas_charla: dict[int, float] = {}
_guardia = threading.Lock()

# Si Gemini no está, el simulado saluda con un mensaje fijo según su perfil.
SALUDOS = {
    "parchadito": "¡Qué más, {nombre}! Qué bueno que llegaste al parche 🙌 El domingo después nos tomamos un jugo, ¿cierto?",
    "madrugador": "¡Hola, {nombre}! Yo llego tipo 15 minutos antes a {punto}, por si quieres llegar con tiempo.",
    "deportista": "¡Buenas, {nombre}! 💪 ¿Vas suave o le metemos ritmo el domingo?",
    "contemplativo": "Hola, {nombre} 👋 Qué bueno tenerte. Yo voy tranqui, disfrutando el paisaje.",
}


def escribiendo(salida_id: int) -> list[str]:
    with _guardia:
        return sorted(_escribiendo.get(salida_id, set()))


def _marcar(salida_id: int, nombre: str | None) -> None:
    with _guardia:
        if nombre is None:
            _escribiendo.pop(salida_id, None)
        else:
            _escribiendo[salida_id] = {nombre}


def _ocupado(salida_id: int) -> bool:
    candado = _candados.get(salida_id)
    return candado is not None and candado.locked()


# ---------------------------------------------------------------- charla entre simulados

def _ultimos(s: Session, salida_id: int, n: int) -> list[ChatMensaje]:
    """Los últimos n mensajes del chat, del más viejo al más nuevo."""
    return list(reversed(s.exec(
        select(ChatMensaje).where(ChatMensaje.salida_id == salida_id).order_by(ChatMensaje.id.desc()).limit(n)
    ).all()))


def _seguidos_simulados(mensajes: list[ChatMensaje]) -> int:
    """Cuántos mensajes simulados van seguidos desde la última vez que escribió una persona real."""
    n = 0
    for m in reversed(mensajes):
        if not m.simulado:
            break
        n += 1
    return n


def _puede_charlar(s: Session, salida_id: int) -> bool:
    from . import chat

    if not asistente.disponible() or len(chat.simulados_en_chat(s, salida_id)) < 2:
        return False
    mensajes = _ultimos(s, salida_id, config.CHAT_CHARLA_MAX + 1)
    if not mensajes:
        return False  # el chat vacío arranca con la bienvenida
    quieto = (services.ahora() - mensajes[-1].creado_en).total_seconds()
    return quieto >= config.CHAT_CHARLA_SEG and _seguidos_simulados(mensajes) < config.CHAT_CHARLA_MAX


def reservar_charla(s: Session, salida_id: int) -> bool:
    """Si toca que los simulados charlen entre ellos, lo reserva (para no programarlo dos veces
    mientras la app consulta el chat cada pocos segundos) y devuelve True."""
    if _ocupado(salida_id) or not _puede_charlar(s, salida_id):
        return False
    with _guardia:
        ahora = time.monotonic()
        if ahora - _reservas_charla.get(salida_id, float("-inf")) < max(config.CHAT_CHARLA_SEG, 1):
            return False
        _reservas_charla[salida_id] = ahora
    return True


# ---------------------------------------------------------------- turnos

def generar(salida_id: int, modo: str, recien_llegado: str | None = None) -> None:
    """Un turno de los simulados en el chat. modo: "bienvenida", "respuesta" o "charla"."""
    with _guardia:
        candado = _candados.setdefault(salida_id, threading.Lock())
        if not candado.acquire(blocking=False):
            if modo != "charla":
                _pendientes.add(salida_id)  # ya hay un turno en curso: al terminar, se responde lo nuevo
            return
    try:
        while True:
            with _guardia:
                _pendientes.discard(salida_id)
            try:
                _turno(salida_id, modo, recien_llegado)
            except Exception:  # el chat de la gente real nunca se cae por los simulados
                log.exception("Falló el turno de los simulados en el chat %s", salida_id)
            with _guardia:
                if salida_id not in _pendientes:
                    break
            modo, recien_llegado = "respuesta", None
    finally:
        _marcar(salida_id, None)
        candado.release()


def _turno(salida_id: int, modo: str, recien_llegado: str | None) -> None:
    from . import chat

    with Session(engine) as s:
        salida = s.get(Salida, salida_id)
        simulados = chat.simulados_en_chat(s, salida_id) if salida else []
        if not simulados:
            return
        historial = _ultimos(s, salida_id, HISTORIAL)
        if modo == "respuesta" and (not historial or historial[-1].simulado):
            return  # se responde a lo que escribe una persona real
        if modo == "charla" and not _puede_charlar(s, salida_id):
            return  # alguien escribió mientras tanto, o ya charlaron suficiente
        if asistente.disponible():
            _marcar(salida_id, "Alguien")
            try:
                respuestas = _pedir_a_gemini(s, salida, simulados, historial, modo, recien_llegado)
            except asistente.GeminiNoDisponible:
                log.warning("Gemini no respondió en el chat %s", salida_id)
                respuestas = _saludo_fijo(salida, simulados, recien_llegado) if modo == "bienvenida" else []
        else:
            respuestas = _saludo_fijo(salida, simulados, recien_llegado) if modo == "bienvenida" else []

        por_id = {j.id: j for j in simulados}
        for sim_id, texto, responde_a in respuestas:
            j = por_id.get(sim_id)
            if j is None:
                continue
            texto = _sin_nombre_al_inicio(texto, j.nombre)
            if not texto:
                continue
            _marcar(salida_id, j.nombre)
            # "escribiendo…" un rato proporcional al largo del mensaje
            time.sleep(config.CHAT_PAUSA_SEG * min(2.5, 0.6 + len(texto) / 80))
            s.add(ChatMensaje(salida_id=salida_id, joven_id=j.id, nombre=j.nombre,
                              universidad=UNIVERSIDADES_POR_ID[j.universidad]["corto"], simulado=True,
                              responde_a=responde_a if responde_a != j.nombre else None,
                              texto=texto.strip()[:300]))
            s.commit()


def _sin_nombre_al_inicio(texto: str, nombre: str) -> str:
    """Gemini a veces imita la transcripción y escribe "Andrés: Oigan…": el chat ya muestra quién habla."""
    texto = texto.strip()
    return re.sub(rf"^\s*{re.escape(nombre)}\s*[:：]\s*", "", texto, flags=re.IGNORECASE).strip()


def _saludo_fijo(salida: Salida, simulados: list[Joven], recien_llegado: str | None) -> list[tuple[str, str, str | None]]:
    if not recien_llegado:
        return []
    perfiles = sinteticos.perfiles_por_id()
    j = simulados[0]
    plantilla = SALUDOS.get(perfiles.get(j.id, ""), SALUDOS["parchadito"])
    texto = plantilla.format(nombre=recien_llegado, punto=tramo_info(salida.tramo_id)["referencia"])
    return [(j.id, texto, recien_llegado)]


# ---------------------------------------------------------------- Gemini

def ficha(j: Joven, perfil_id: str | None) -> str:
    """La personalidad de un simulado, tal como sale del JSON."""
    perfil = sinteticos.PERFILES.get(perfil_id or "", {})
    edad = j.rango_edad.replace("-", " a ")
    lineas = [
        f"- id «{j.id}»: {j.nombre}, entre {edad} años, estudia en {UNIVERSIDADES_POR_ID[j.universidad]['nombre']}. "
        f"Le gusta ir en {ACTIVIDADES_POR_ID[j.actividad]['nombre'].lower()} a ritmo {_RITMO[j.ritmo]}.",
    ]
    if perfil:
        lineas.append(f"  Personalidad: {perfil['nombre']}. {perfil['descripcion']}")
    respuestas = services.respuestas_quiz(j)
    if respuestas:
        gustos = "; ".join(f"{p['texto']} → «{_OPCION[(p['id'], respuestas[p['id']])]}»"
                           for p in QUIZ_PREGUNTAS if p["id"] in respuestas)
        lineas.append(f"  Así respondió el quiz de estilo: {gustos}.")
    return "\n".join(lineas)


def _instrucciones(salida: Salida, simulados: list[Joven]) -> str:
    perfiles = sinteticos.perfiles_por_id()
    t = tramo_info(salida.tramo_id)
    fichas = "\n".join(ficha(j, perfiles.get(j.id)) for j in simulados)
    return f"""Simulas a varios estudiantes universitarios de Cali que están en el chat de su parche para ir juntos
a la CicloVida. Cada uno tiene su personalidad (abajo): habla como esa persona, no como un asistente.

El parche: {salida.nombre}, {ACTIVIDADES_POR_ID[salida.actividad]['nombre'].lower()} el domingo {salida.jornada_fecha}
a las {FRANJA_NOMBRE[salida.franja]}. Se encuentran en la estación {t['nombre']}: {t['punto']} ({t['referencia']}).
La CicloVida va de 8:00 a. m. a 1:00 p. m.

Simulados en el chat:
{fichas}

Cómo escriben:
- Español colombiano natural, con un toque caleño sin exagerar. Mensajes cortos de chat: una o dos frases.
- Cada uno con su estilo: el Parchadito es charlador y propone planes; el Madrugador es puntual y organizado;
  el Deportista va al grano y habla de ritmo; el Contemplativo es tranquilo y habla del paisaje.
- Se hablan entre ellos como compañeros de chat: se contestan, se dan la razón o no, se echan bromas. No todos
  le hablan siempre a la persona real.
- Emojis de vez en cuando, no en todos los mensajes. Sin repetir lo que ya dijo otro.
- Llaman a la gente por su primer nombre.

Reglas que nunca se rompen:
- No inventes datos del parche distintos a los de arriba (lugar, hora, fecha).
- Nunca pidan ni compartan teléfonos, direcciones, redes sociales ni otros datos personales. El encuentro es
  siempre en la estación y en horario de CicloVida; si alguien propone otra cosa, lo recuerdan con buena onda.
- Nada romántico ni sexual, ni burlas. Si alguien cuenta que se siente en riesgo o incómodo, le responden con
  cuidado y le sugieren «Reportar un problema» en la app y el 123 en una emergencia.
- Sobre cosas oficiales de la CicloVida que no están arriba (si se cancela por lluvia, cierres, cambios de
  horario), no las den por hechas: digan que no están seguros y que lo confirmen en los canales de la Alcaldía.
- Solo si alguien pregunta directamente si son personas reales o bots, dicen con naturalidad que son estudiantes
  simulados para la demo de Parches CicloVida. No lo mencionen por su cuenta: la app ya los marca.

Responde SOLO con la lista JSON pedida, en el orden en que se escriben los mensajes. Cada elemento:
{{"id": id del simulado que escribe, "texto": su mensaje (sin su nombre al inicio: el chat ya muestra quién
habla), "responde_a": primer nombre de a quién le contesta (la persona real u otro simulado), o vacío si le
habla a todos}}."""


def _transcripcion(historial: list[ChatMensaje]) -> str:
    if not historial:
        return "(todavía no hay mensajes)"
    lineas = []
    for m in historial:
        quien = f"simulado, id {m.joven_id}" if m.simulado else "persona real"
        a = f", le contesta a {m.responde_a}" if m.responde_a else ""
        lineas.append(f"{m.nombre} ({quien}{a}): {m.texto}")
    return "\n".join(lineas)


def _tarea(modo: str, historial: list[ChatMensaje], recien_llegado: str | None, reales: list[str]) -> str:
    if modo == "bienvenida" and not historial:
        return (f"El chat está vacío y {recien_llegado} acaba de unirse. Primero escriban 2 o 3 mensajes entre "
                "ustedes, como si llevaran un rato organizándose para el domingo, contestándose unos a otros. "
                f"Después, 1 o 2 le dan la bienvenida a {recien_llegado}, cada uno a su estilo.")
    if modo == "bienvenida":
        return (f"{recien_llegado} acaba de unirse al chat. 1 o 2 simulados le dan la bienvenida, cada uno a su "
                "estilo; si viene al caso, otro reacciona a lo que dijo el primero.")
    if modo == "charla":
        invitados = " o ".join(reales) if reales else "la persona real"
        return ("Nadie ha escrito en un rato. Escriban entre 2 y 4 mensajes conversando ENTRE USTEDES de algo natural "
                "(el domingo, la ruta, el clima, la semana en la universidad, el plan después de rodar), "
                "contestándose unos a otros. Participan al menos dos simulados distintos. No repitan temas que ya "
                f"hablaron. Si viene al caso, alguno invita a {invitados} a la conversación, sin presionar.")
    return ("Respondan al último mensaje. Pueden contestar varios (de 1 a 3), los que tengan más razón para hacerlo "
            "(a quien le hablaron, o a quien le interesa por su personalidad), y alguno puede reaccionar a lo que acaba "
            "de decir otro simulado, como en un chat de verdad. Si el mensaje era para otra persona real, o no hace "
            "falta contestar (un «ok», un «jaja»), devuelvan una lista vacía.")


def _pedir_a_gemini(s: Session, salida: Salida, simulados: list[Joven], historial: list[ChatMensaje], modo: str,
                    recien_llegado: str | None) -> list[tuple[str, str, str | None]]:
    from . import chat

    gente = chat.miembros(s, salida.id)
    reales = [j.nombre for j in gente if not j.sintetico]
    nombres = {j.nombre for j in gente} | ({recien_llegado} if recien_llegado else set())
    tarea = _tarea(modo, historial, recien_llegado, reales)
    cuerpo = {
        "system_instruction": {"parts": [{"text": _instrucciones(salida, simulados)}]},
        "contents": [{"role": "user", "parts": [{"text": f"Conversación hasta ahora:\n{_transcripcion(historial)}\n\n{tarea}"}]}],
        "generationConfig": {
            "temperature": 0.9,
            "maxOutputTokens": 900,
            "responseMimeType": "application/json",
            "responseSchema": {
                "type": "ARRAY",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "id": {"type": "STRING", "enum": [j.id for j in simulados]},
                        "texto": {"type": "STRING"},
                        "responde_a": {"type": "STRING"},
                    },
                    "required": ["id", "texto"],
                },
            },
        },
    }
    data = asistente._llamar_gemini(cuerpo)
    partes = ((data.get("candidates") or [{}])[0].get("content") or {}).get("parts") or []
    texto = "".join(p.get("text", "") for p in partes if not p.get("thought")).strip()
    if texto.startswith("```"):
        texto = texto.strip("`").removeprefix("json").strip()
    try:
        lista = json.loads(texto) if texto else []
    except json.JSONDecodeError:
        log.warning("Gemini devolvió algo que no es JSON en el chat: %r", texto[:200])
        return []
    if not isinstance(lista, list):
        return []
    validos = {j.id for j in simulados}
    salida_turno = []
    for x in lista:
        if not isinstance(x, dict) or x.get("id") not in validos:
            continue
        a = str(x.get("responde_a") or "").strip() or None
        salida_turno.append((str(x["id"]), str(x.get("texto", "")).strip(), a if a in nombres else None))
    return salida_turno[:MAX_POR_TURNO]
