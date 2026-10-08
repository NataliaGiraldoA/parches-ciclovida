"""Asistente conversacional del bot de Telegram, con Gemini y function calling.

El joven escribe con sus palabras ("quiero trotar el domingo temprano", "¿quién va conmigo?",
"publica en el foro que me encantó") y Gemini decide qué función del backend usar. Las
funciones son las mismas de la app (services.py), así que el modelo nunca inventa parches,
horarios ni personas: solo cuenta lo que devuelven.

Qué se le envía a Gemini: los mensajes que el joven le escribe al bot, su primer nombre, sus
preferencias y lo que devuelven las funciones. Nunca el correo, la universidad ni datos de otras
personas más allá del primer nombre que el grupo ya ve. Está declarado en el aviso de privacidad.

Sin GEMINI_API_KEY, el bot sigue con comandos y botones (ver telegram.py).
"""

from __future__ import annotations

import logging
import re
import unicodedata

import httpx
from sqlmodel import Session

from . import config
from .catalog import ACTIVIDADES, FORO_CATEGORIAS, FORO_IDS, FRANJAS, JORNADA_FIN, JORNADA_INICIO, TRAMOS
from .models import Joven

log = logging.getLogger("parches.asistente")

MAX_PASOS = 5  # llamadas a funciones por mensaje, para que nunca se quede en un bucle
MAX_HISTORIAL = 12  # turnos de texto que se recuerdan por chat (en memoria)
_historial: dict[str, list[dict]] = {}


def disponible() -> bool:
    return bool(config.GEMINI_API_KEY)


def olvidar(chat_id: str) -> None:
    _historial.pop(chat_id, None)


# ---------------------------------------------------------------- funciones que puede usar Gemini

HERRAMIENTAS = [
    {
        "name": "ver_mi_estado",
        "description": "Estado del joven para el próximo domingo: si tiene parche, su grupo, quién confirmó, "
                       "si está en lista de espera (con el parche que más se ajusta) y sus preferencias. "
                       "Úsala antes de responder cualquier cosa sobre 'mi parche' o 'mi grupo'.",
        "parameters": {"type": "OBJECT", "properties": {}},
    },
    {
        "name": "buscar_parches",
        "description": "Busca parches del próximo domingo que le sirven al joven. Todos los filtros son opcionales; "
                       "sin filtros devuelve los que más se ajustan a sus preferencias.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "actividad": {"type": "STRING", "enum": [a["id"] for a in ACTIVIDADES]},
                "hora": {"type": "STRING", "enum": [f["id"] for f in FRANJAS],
                         "description": "Hora de salida: 08:00, 09:30 u 11:00"},
                "estacion": {"type": "STRING", "description": "Nombre de la estación, como lo diga el joven"},
            },
        },
    },
    {
        "name": "unirme_a_parche",
        "description": "Inscribe al joven en un parche, o lo CAMBIA de parche si ya tiene uno. Solo con un "
                       "parche_id que haya salido de buscar_parches o ver_mi_estado, y solo cuando el joven lo "
                       "pidió o aceptó. Si ya está en otro parche y aún no confirmó el cambio, devuelve "
                       "requiere_confirmacion: pregúntale si quiere salir de su parche actual y, cuando diga que "
                       "sí, vuelve a llamarla con confirmo_cambio=true.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "parche_id": {"type": "INTEGER"},
                "confirmo_cambio": {"type": "BOOLEAN",
                                    "description": "true solo si el joven ya confirmó que quiere salir de su parche actual"},
            },
            "required": ["parche_id"],
        },
    },
    {
        "name": "confirmar_asistencia",
        "description": "Responde si el joven va o no va el domingo con su grupo. Solo funciona desde el sábado "
                       "a las 5:00 p. m., cuando ya tiene grupo.",
        "parameters": {
            "type": "OBJECT",
            "properties": {"va": {"type": "BOOLEAN"}},
            "required": ["va"],
        },
    },
    {
        "name": "publicar_en_foro",
        "description": "Publica un mensaje en el foro comunal con el primer nombre del joven. Úsala directamente "
                       "si él dictó el mensaje y pidió publicarlo; si solo contó una idea, propón el texto y "
                       "publícalo cuando diga que sí.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "categoria": {"type": "STRING", "enum": [c["id"] for c in FORO_CATEGORIAS],
                              "description": "parches = mis parches, app = la app, animo = cómo me siento"},
                "texto": {"type": "STRING", "description": "El mensaje tal como lo aprobó el joven (máximo 500)"},
            },
            "required": ["categoria", "texto"],
        },
    },
]


def _sin_tildes(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")


def _tramo_de(texto: str) -> str | None:
    buscado = _sin_tildes(texto).replace("estacion", "").strip()
    for t in TRAMOS:
        if buscado and (buscado in _sin_tildes(t["nombre"]) or buscado == t["id"]):
            return t["id"]
    return None


def _parche_corto(p: dict) -> dict:
    return {
        "parche_id": p["id"], "nombre": p["nombre"], "actividad": p["actividad_nombre"], "hora": p["hora_nombre"],
        "estacion": p["tramo"]["nombre"], "punto": f"{p['punto_encuentro']} ({p['referencia']})",
        "inscritos": p["inscritos"], "ritmo_del_grupo": p.get("ritmo_nombre"),
        "coincide_con_tus_preferencias": p.get("para_ti", False),
    }


def _ver_mi_estado(session: Session, joven: Joven) -> dict:
    from . import services

    info = services.estado_para(session, joven)
    salida = {
        "estado": info["estado"], "domingo": info["jornada"]["fecha"],
        "preferencias": {
            "actividad": joven.actividad, "ritmo": joven.ritmo, "hora": joven.franja or "cualquiera",
            "estacion": next((t["nombre"] for t in TRAMOS if t["id"] == joven.tramo_id), "cualquiera"),
            "comuna": joven.comuna,
        },
    }
    if info["salida"]:
        salida["parche"] = _parche_corto(info["salida"])
    if info["grupo"]:
        g = info["grupo"]
        salida["grupo"] = {
            "nombre": g["nombre"], "punto": f"{g['punto_encuentro']} ({g['referencia']})", "hora": g["hora_nombre"],
            "companeros": [{"nombre": m["nombre"], "confirmo": m["estado"]} for m in g["miembros"] if not m["soy_yo"]],
            "mi_respuesta": info["mi_respuesta"],
        }
    if info["espera"] and info["espera"].get("mas_parecido"):
        salida["parche_que_mas_se_ajusta"] = _parche_corto(info["espera"]["mas_parecido"])
    return salida


def _buscar_parches(session: Session, joven: Joven, actividad: str | None = None, hora: str | None = None,
                    estacion: str | None = None) -> dict:
    from . import services

    tramo = None
    if estacion:
        tramo = _tramo_de(estacion)
        if tramo is None:
            return {"error": f"No encontré la estación «{estacion}»", "estaciones": [t["nombre"] for t in TRAMOS]}
    if not (actividad or hora or estacion):
        parches = services.sugerencias_para(session, joven, limite=5)
    else:
        parches = services.listar_parches(session, joven, tramo=tramo, franja=hora, actividad=actividad)["parches"]
        parches.sort(key=lambda p: (not p["para_ti"], -p["inscritos"]))
    return {"parches": [_parche_corto(p) for p in parches[:5]]}


def _unirme(session: Session, joven: Joven, parche_id: int, confirmo_cambio: bool = False) -> dict:
    from . import services

    info = services.estado_para(session, joven)
    actual = info.get("salida")
    if info["estado"] in ("inscrito", "asignado") and actual and actual["id"] != parche_id and not confirmo_cambio:
        # Igual que el diálogo de la app: cambiarse deja un cupo libre, así que se confirma primero.
        return {
            "ok": False, "requiere_confirmacion": True,
            "parche_actual": _parche_corto(actual),
            "con_grupo_armado": info["estado"] == "asignado",
            "mensaje": "Pregúntale si quiere salir de su parche actual (y de su grupo, si ya se armó) para pasarse "
                       "al nuevo. Si dice que sí, llama de nuevo con confirmo_cambio=true.",
        }
    try:
        services.unirse(session, joven, int(parche_id))
    except LookupError as e:
        return {"ok": False, "motivo": str(e)}
    cambio = bool(actual and actual["id"] != parche_id)
    return {"ok": True, "cambio_de_parche": cambio, **_ver_mi_estado(session, joven)}


def _confirmar(session: Session, joven: Joven, va: bool) -> dict:
    from . import services

    try:
        services.responder(session, joven, bool(va))
    except LookupError as e:
        return {"ok": False, "motivo": str(e)}
    return {"ok": True, "respuesta": "confirmado" if va else "declinado"}


def _publicar(session: Session, joven: Joven, categoria: str, texto: str) -> dict:
    from . import services

    texto = (texto or "").strip()
    if categoria not in FORO_IDS:
        return {"ok": False, "motivo": "Tema desconocido"}
    if not 2 <= len(texto) <= config.FORO_MAX:
        return {"ok": False, "motivo": f"El mensaje debe tener entre 2 y {config.FORO_MAX} caracteres"}
    try:
        services.foro_publicar(session, joven, categoria, texto)
    except LookupError as e:
        return {"ok": False, "motivo": str(e)}
    return {"ok": True}


def ejecutar(session: Session, joven: Joven, nombre: str, args: dict) -> dict:
    """Corre una función pedida por Gemini. Cualquier error vuelve como dato, nunca como excepción."""
    try:
        if nombre == "ver_mi_estado":
            return _ver_mi_estado(session, joven)
        if nombre == "buscar_parches":
            return _buscar_parches(session, joven, args.get("actividad"), args.get("hora"), args.get("estacion"))
        if nombre == "unirme_a_parche":
            return _unirme(session, joven, int(args["parche_id"]), bool(args.get("confirmo_cambio", False)))
        if nombre == "confirmar_asistencia":
            return _confirmar(session, joven, bool(args["va"]))
        if nombre == "publicar_en_foro":
            return _publicar(session, joven, args.get("categoria", ""), args.get("texto", ""))
    except Exception as e:  # noqa: BLE001
        log.exception("Falló la función %s", nombre)
        session.rollback()
        return {"ok": False, "motivo": f"Error interno: {e.__class__.__name__}"}
    return {"ok": False, "motivo": f"No existe la función {nombre}"}


# ---------------------------------------------------------------- conversación

def _instrucciones(session: Session, joven: Joven) -> str:
    from . import services

    domingo = services.jornada_abierta(session).fecha
    estaciones = "; ".join(f"{t['nombre']} (comuna {t['comuna']})" for t in TRAMOS)
    return f"""Eres Parcherito, el bot de Parches CicloVida: ayudas a estudiantes universitarios de Cali a ir en parche
(grupos de 3 a 6) a la CicloVida del domingo. Hablas en español, cálido, cercano y con toque caleño, sin exagerar.

Hoy es {services.ahora().date().isoformat()}. El próximo domingo de CicloVida es {domingo}, de {JORNADA_INICIO} a {JORNADA_FIN}.
Salidas a las 8:00, 9:30 y 11:00. Actividades: bici, patines, trotar, caminar. Estaciones: {estaciones}.
Cómo funciona: el joven se une a un parche (estación + hora + actividad). El sábado a las 5:00 p. m. un algoritmo
arma grupos de 3 a 6 dentro de cada parche según ritmo, edad y experiencia, y desde ahí puede confirmar si va.

Hablas con {joven.nombre}.

Reglas:
- Tú mismo haces las cosas desde el chat: unirse a un parche, cambiarse de parche, confirmar si va y publicar
  en el foro. Nunca le digas que tiene que ir a la app para eso. La app solo hace falta para leer el foro,
  ver el mapa o borrar sus datos.
- Nunca inventes parches, horarios, estaciones ni personas. Para cualquier dato usa las funciones.
- Antes de unir a alguien a un parche, asegúrate de que lo pidió o lo aceptó. Si está en espera y no sabe qué
  hacer, propónle el parche que más se ajusta y pregúntale si lo quiere.
- Cambio de parche: si ya tiene uno y elige otro, confírmale en una frase que sale de su parche actual (y de
  su grupo, si ya se armó) y pregúntale si sigue. Cuando diga que sí, usa unirme_a_parche con
  confirmo_cambio=true. Si en el mismo mensaje ya pidió claramente el cambio («cámbiame al Ceiba»), hazlo
  de una con confirmo_cambio=true.
- Foro: si te dicta el mensaje y te pide publicarlo («publica en el foro que…»), publícalo de una eligiendo
  el tema. Si solo te cuenta una idea, propón el texto y el tema y publícalo cuando diga que sí. Los temas
  se llaman «Mis parches», «La app» y «Cómo me siento»: di siempre esos nombres, nunca los identificadores
  internos (parches, app, animo).
- Si alguien menciona acoso, riesgo o que se sintió inseguro: toma en serio lo que cuenta, dile que use
  «Reportar un problema» dentro de su parche en la app y que en una emergencia llame al 123.
- Si alguien cuenta que se siente mal emocionalmente, responde con empatía y sin diagnosticar; sugiérele hablar
  con alguien de confianza o con bienestar universitario, y el 123 si está en peligro.
- Temas ajenos a la CicloVida y los parches: responde en una línea y vuelve al tema.
- Respuestas cortas (máximo unas 6 líneas), texto plano sin markdown, algún emoji ocasional.
"""


_REINTENTABLES = {404, 429, 500, 502, 503, 504}
ESPERAS = (0, 1.5, 3.0)  # segundos antes de cada ronda: los 503 de "alta demanda" suelen durar poco


class GeminiNoDisponible(Exception):
    """Gemini no respondió después de reintentar con todos los modelos."""


def _llamar_gemini(cuerpo: dict) -> dict:
    """Una llamada a la API de Gemini. Aislada para poder simularla en las pruebas.

    Si un modelo no existe (404) o está saturado (429/5xx, p. ej. el 503 "high demand"),
    prueba los de respaldo; si todos fallan, espera un poco y hace otra ronda.
    """
    import time

    ultimo: Exception | None = None
    modelos = list(dict.fromkeys([config.GEMINI_MODEL, *config.GEMINI_RESPALDO]))
    for espera in ESPERAS:
        if espera:
            time.sleep(espera)
        for modelo in modelos:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent"
            try:
                r = httpx.post(url, json=cuerpo, headers={"x-goog-api-key": config.GEMINI_API_KEY}, timeout=20)
            except httpx.HTTPError as e:
                ultimo = e
                continue
            if r.status_code in _REINTENTABLES:
                log.warning("Gemini %s respondió %s; pruebo otro", modelo, r.status_code)
                ultimo = httpx.HTTPStatusError(f"{modelo}: {r.status_code}", request=r.request, response=r)
                continue
            r.raise_for_status()  # 400/401/403: la key o el pedido están mal, no sirve reintentar
            return r.json()
    raise GeminiNoDisponible(str(ultimo or "sin modelos configurados"))


def conversar(session: Session, joven: Joven, chat_id: str, texto: str) -> tuple[str, list[dict]]:
    """Responde un mensaje libre. Devuelve el texto y los parches que se mostraron en este turno
    (para ofrecerlos también como botones).

    Lanza GeminiNoDisponible si Gemini no respondió ni reintentando: quien llama decide el plan B.
    """
    historial = _historial.setdefault(chat_id, [])
    contenidos = [*historial, {"role": "user", "parts": [{"text": texto}]}]
    mostrados: list[dict] = []

    for _ in range(MAX_PASOS):
        try:
            data = _llamar_gemini({
                "system_instruction": {"parts": [{"text": _instrucciones(session, joven)}]},
                "contents": contenidos,
                "tools": [{"function_declarations": HERRAMIENTAS}],
                "generationConfig": {"temperature": 0.6, "maxOutputTokens": 800},
            })
        except GeminiNoDisponible:
            raise
        except Exception as e:  # noqa: BLE001
            log.warning("Gemini no respondió: %s", e)
            raise GeminiNoDisponible(str(e)) from e

        candidato = (data.get("candidates") or [{}])[0]
        contenido = candidato.get("content") or {"role": "model", "parts": []}
        partes = contenido.get("parts") or []
        llamadas = [p["functionCall"] for p in partes if "functionCall" in p]
        if not llamadas:
            respuesta = "".join(p.get("text", "") for p in partes).strip()
            if not respuesta:
                respuesta = "No te entendí bien 😅 ¿Me lo cuentas de otra forma?"
            historial.extend([{"role": "user", "parts": [{"text": texto}]},
                              {"role": "model", "parts": [{"text": respuesta}]}])
            del historial[:-MAX_HISTORIAL]
            return respuesta, mostrados

        # El contenido del modelo va tal cual (conserva las firmas de razonamiento de Gemini).
        contenidos.append({"role": "model", "parts": partes})
        respuestas = []
        for ll in llamadas:
            resultado = ejecutar(session, joven, ll.get("name", ""), ll.get("args") or {})
            if ll.get("name") == "buscar_parches":
                mostrados.extend(resultado.get("parches", []))
            if ll.get("name") == "ver_mi_estado" and "parche_que_mas_se_ajusta" in resultado:
                mostrados.append(resultado["parche_que_mas_se_ajusta"])
            respuestas.append({"functionResponse": {"name": ll.get("name", ""), "response": resultado}})
        contenidos.append({"role": "user", "parts": respuestas})

    return "Me enredé un poco con eso 😅 ¿Me lo pides de nuevo, más cortico?", mostrados


def a_html(texto: str) -> str:
    """Texto del modelo a HTML seguro para Telegram: escapa todo y respeta **negritas**."""
    from html import escape

    seguro = escape(texto)
    seguro = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", seguro)
    return seguro.replace("*", "")[:4000]
