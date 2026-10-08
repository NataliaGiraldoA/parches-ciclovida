"""Bot de Telegram (opcional): las funciones clave de la app, empatadas en el chat.

Con TELEGRAM_TOKEN en backend/.env:
- El joven vincula su cuenta abriendo t.me/<bot>?start=<código> desde la app.
- Por el chat recibe los avisos (propuesta de parche, match encontrado, grupo del sábado).
- Y puede hacer desde el chat, con botones:
    /parche    ver su parche o, si aún no tiene, la propuesta que más se ajusta y unirse
    /confirmo  confirmar que va (también con botón en el aviso del sábado)
    /novoy     avisar que no va
    /foro      publicar un mensaje en el foro comunal (solo publicar; leer es en la app)
    /ayuda     la lista de comandos

Sin token, todo esto se apaga y la app solo muestra el aviso interno.
"""

from __future__ import annotations

import logging
from html import escape as h

import httpx
from sqlmodel import Session, select

from . import asistente, config
from .models import Joven

log = logging.getLogger("parches.telegram")
_offset = 0  # último update procesado de getUpdates
_ultimo_conflicto: float = 0.0  # cuándo Telegram avisó que otro programa lee con este mismo token


def otra_instancia_reciente(segundos: int = 120) -> bool:
    """True si hace poco otro programa (p. ej. otro backend) leyó los mensajes con este token."""
    import time

    return bool(_ultimo_conflicto) and time.time() - _ultimo_conflicto < segundos

# Estado de conversación del foro, por chat. En memoria: el bot corre en una sola instancia.
_foro_esperando: set[str] = set()  # chats a los que se les pidió escribir el mensaje
_foro_pendiente: dict[str, str] = {}  # texto listo, falta elegir la categoría

Botones = list[list[tuple[str, str]]]  # filas de (texto del botón, callback_data)

AYUDA = (
    "Esto es lo que puedo hacer:\n"
    "/parche — tu parche, o uno para elegir ahora mismo\n"
    "/confirmo — confirmar que vas\n"
    "/novoy — avisar que no vas\n"
    "/foro — publicar un mensaje en el foro\n"
    "/cuenta — con qué cuenta está conectado este chat\n"
    "/ayuda — este mensaje\n"
    "Leer el foro y ver el mapa es en la app 📱"
)
AYUDA_CONVERSACION = (
    "También puedes escribirme normal, como a un parcero 🗣️ Por ejemplo: «quiero trotar el domingo "
    "temprano», «¿quién va conmigo?», «cámbiame al parche de las 8» o «publica en el foro que me encantó "
    "el parche»."
)


def _como_cambiar() -> str:
    return ("Para usar otra cuenta con este chat, ábrela en la app y toca «Conectar Telegram»: el chat pasa a esa "
            "cuenta. Para soltarla, /desconectar.")


def _ayuda() -> str:
    return f"{AYUDA}\n\n{AYUDA_CONVERSACION}" if asistente.disponible() else AYUDA


def disponible() -> bool:
    return bool(config.TELEGRAM_TOKEN)


def enlace_para(codigo: str) -> str | None:
    """Enlace para la app de Telegram (celular o escritorio)."""
    if not disponible() or not config.TELEGRAM_BOT:
        return None
    return f"https://t.me/{config.TELEGRAM_BOT}?start={codigo}"


def enlace_web_para(codigo: str) -> str | None:
    """Enlace directo a Telegram Web con el código incluido.

    Si se abre t.me desde el navegador, Telegram intenta abrir la app instalada, y al pasar por
    «abrir en web» suele perder el ?start=: el botón Start manda /start sin código y no vincula.
    Con tgaddr, Telegram Web abre el chat del bot conservando el código.
    """
    if not disponible() or not config.TELEGRAM_BOT:
        return None
    from urllib.parse import quote

    return "https://web.telegram.org/k/#?tgaddr=" + quote(
        f"tg://resolve?domain={config.TELEGRAM_BOT}&start={codigo}", safe="")


def _api(metodo: str, **params):
    if not disponible():
        return None
    try:
        r = httpx.post(f"https://api.telegram.org/bot{config.TELEGRAM_TOKEN}/{metodo}", json=params, timeout=10)
        data = r.json()
        if not data.get("ok"):
            descripcion = data.get("description") or ""
            if metodo == "getUpdates" and "Conflict" in descripcion:
                _avisar_conflicto()
            else:
                log.warning("Telegram rechazó %s: %s", metodo, descripcion)
        return data.get("result") if data.get("ok") else None
    except Exception as e:  # la app nunca se cae por Telegram
        log.warning("Telegram no respondió (%s): %s", metodo, e)
        return None


def _avisar_conflicto() -> None:
    """Dos programas leyendo con el mismo token se roban los mensajes: el /start puede caer en el
    otro, que tiene otra base de datos y no conoce el código de vinculación. Se avisa fuerte, cada minuto."""
    import time

    global _ultimo_conflicto
    ahora = time.time()
    if ahora - _ultimo_conflicto > 60:
        log.error("OTRO PROGRAMA está usando este mismo TELEGRAM_TOKEN (Telegram responde 'Conflict'). "
                  "Los mensajes del bot se reparten entre los dos y el /start puede no vincular. Deja un solo "
                  "backend con este token, o genera uno nuevo con /revoke en @BotFather.")
    _ultimo_conflicto = ahora


def enviar(chat_id: str, texto: str, botones: Botones | None = None) -> None:
    params: dict = {"chat_id": chat_id, "text": texto, "parse_mode": "HTML"}
    if botones:
        params["reply_markup"] = {
            "inline_keyboard": [[{"text": t, "callback_data": d} for t, d in fila] for fila in botones]
        }
    _api("sendMessage", **params)


def iniciar() -> str | None:
    """Al arrancar el servidor: valida el token, resuelve el @ del bot y registra el menú."""
    if not disponible():
        return None
    yo = _api("getMe")
    if not yo:
        log.warning("TELEGRAM_TOKEN configurado pero getMe falló: revisa el token o la red")
        return None
    real = yo.get("username", "")
    # El @ que dice Telegram manda: si el .env trae otro nombre, el enlace t.me
    # llevaría a un bot ajeno y el /start nunca llegaría a este.
    if config.TELEGRAM_BOT and config.TELEGRAM_BOT.lstrip("@").lower() != real.lower():
        log.warning("TELEGRAM_BOT=%s no coincide con el bot del token (@%s): se usa @%s",
                    config.TELEGRAM_BOT, real, real)
    config.TELEGRAM_BOT = real
    _api("setMyCommands", commands=[
        {"command": "parche", "description": "Tu parche, o uno para elegir ya"},
        {"command": "confirmo", "description": "Confirmar que vas"},
        {"command": "novoy", "description": "Avisar que no vas"},
        {"command": "foro", "description": "Publicar en el foro"},
        {"command": "cuenta", "description": "Con qué cuenta estás conectado"},
        {"command": "desconectar", "description": "Soltar este chat de tu cuenta"},
        {"command": "ayuda", "description": "Qué puede hacer este bot"},
    ])
    log.info("Bot de Telegram listo: @%s", config.TELEGRAM_BOT)
    return config.TELEGRAM_BOT


# ---------------------------------------------------------------- recepción

def procesar_updates(session: Session) -> None:
    """Lee los mensajes y toques de botón pendientes del bot y atiende cada uno."""
    global _offset
    if not disponible():
        return
    updates = _api("getUpdates", offset=_offset, timeout=0) or []
    for u in updates:
        _offset = max(_offset, u["update_id"] + 1)
        try:
            if "callback_query" in u:
                cq = u["callback_query"]
                _api("answerCallbackQuery", callback_query_id=cq["id"])
                msg = cq.get("message") or {}
                chat_id = str((msg.get("chat") or {}).get("id", ""))
                if chat_id:
                    atender_boton(session, chat_id, cq.get("data") or "", msg.get("message_id"))
                continue
            msg = u.get("message") or {}
            texto = (msg.get("text") or "").strip()
            chat_id = str((msg.get("chat") or {}).get("id", ""))
            if chat_id and texto:
                atender(session, chat_id, texto)
        except Exception:  # un mensaje raro no debe tumbar a los demás
            log.exception("Error atendiendo un update de Telegram")
            session.rollback()


def _jovenes_de(session: Session, chat_id: str) -> list[Joven]:
    return list(session.exec(select(Joven).where(Joven.telegram_chat_id == chat_id)).all())


def _joven_de(session: Session, chat_id: str) -> Joven | None:
    """La cuenta conectada a este chat. Un chat va con una sola cuenta: si por datos viejos hay varias,
    no se adivina cuál (se pide reconectar desde la app)."""
    jovenes = _jovenes_de(session, chat_id)
    return jovenes[0] if len(jovenes) == 1 else None


def _olvidar_chat(chat_id: str) -> None:
    """Lo que el bot recordaba de este chat era de la cuenta anterior."""
    asistente.olvidar(chat_id)
    _foro_esperando.discard(chat_id)
    _foro_pendiente.pop(chat_id, None)


def desconectar(session: Session, joven: Joven) -> None:
    """Suelta el chat de Telegram de esta cuenta (y le da un código nuevo para volver a conectarse)."""
    from secrets import token_hex

    if joven.telegram_chat_id:
        _olvidar_chat(joven.telegram_chat_id)
    joven.telegram_chat_id = None
    joven.telegram_codigo = token_hex(6)
    session.add(joven)
    session.commit()


def vincular(session: Session, chat_id: str, joven: Joven) -> list[str]:
    """Conecta el chat a esta cuenta y se lo quita a cualquier otra: un chat, una cuenta.
    Devuelve los nombres de las cuentas que lo tenían antes."""
    anteriores = [j for j in _jovenes_de(session, chat_id) if j.id != joven.id]
    for j in anteriores:
        j.telegram_chat_id = None
        session.add(j)
    if anteriores:
        _olvidar_chat(chat_id)
    joven.telegram_chat_id = chat_id
    session.add(joven)
    session.commit()
    return [j.nombre for j in anteriores]


def atender(session: Session, chat_id: str, texto: str) -> None:
    """Un mensaje de texto: vincular con /start <código>, un comando o el texto del foro."""
    joven = _joven_de(session, chat_id)
    partes = texto.split(maxsplit=1)
    comando = partes[0].lower().split("@")[0] if partes and partes[0].startswith("/") else ""
    resto = partes[1].strip() if len(partes) > 1 else ""

    if comando == "/start":
        candidato = session.exec(select(Joven).where(Joven.telegram_codigo == resto)).first() if resto else None
        if candidato:
            antes = vincular(session, chat_id, candidato)
            cambio = (f"\n\nEste chat estaba conectado a la cuenta de {h(', '.join(antes))}; desde ahora es de la tuya."
                      if antes else "")
            enviar(chat_id, f"¡Listo, {h(candidato.nombre)}! Ya quedamos conectados 🚲{cambio}\n\n{_ayuda()}")
            enviar_estado(session, chat_id, candidato)
        elif joven:
            enviar(chat_id, f"Este chat está conectado a la cuenta de {h(joven.nombre)}.\n\n{_como_cambiar()}")
        else:
            enviar(chat_id, "¡Hola! 👋 Para vincular tu cuenta, abre Parches CicloVida, toca «Conectar Telegram» "
                            "y envíame aquí el código que aparece, así: /start <código>")
        return

    if joven is None:
        varias = _jovenes_de(session, chat_id)
        if varias and comando == "/desconectar":
            # chat pegado a varias cuentas (datos viejos): se suelta de todas
            nombres = ", ".join(j.nombre for j in varias)
            for j in varias:
                desconectar(session, j)
            enviar(chat_id, f"Listo: desconecté este chat de las cuentas de {h(nombres)}. Para conectarte, abre la "
                            "app con la cuenta que quieras usar y toca «Conectar Telegram».")
            return
        if varias:
            enviar(chat_id, f"Este chat quedó conectado a varias cuentas ({h(', '.join(j.nombre for j in varias))}). "
                            f"{_como_cambiar()}")
        else:
            enviar(chat_id, "No reconozco este chat. Abre Parches CicloVida y toca «Conectar Telegram» para vincularlo.")
        return

    if comando == "/cuenta":
        from .catalog import UNIVERSIDADES_POR_ID

        enviar(chat_id, f"Estás conectado como <b>{h(joven.nombre)}</b> "
                        f"({h(UNIVERSIDADES_POR_ID[joven.universidad]['corto'])}).\n\n{_como_cambiar()}")
        return
    if comando == "/desconectar":
        nombre = joven.nombre
        desconectar(session, joven)
        enviar(chat_id, f"Listo: este chat ya no está conectado a la cuenta de {h(nombre)}. "
                        "Para volver a conectarte, toca «Conectar Telegram» en la app.")
        return

    # Texto suelto mientras el bot espera el mensaje del foro
    if not comando and chat_id in _foro_esperando:
        _foro_esperando.discard(chat_id)
        _preguntar_categoria(chat_id, texto)
        return
    if comando:  # cualquier comando cancela un foro a medias
        _foro_esperando.discard(chat_id)
    else:
        _conversar(session, chat_id, joven, texto)
        return

    if comando in ("/parche", "/estado", "/elegir"):
        enviar_estado(session, chat_id, joven, buscar=True)
    elif comando in ("/confirmo", "/novoy"):
        _responder(session, chat_id, joven, comando == "/confirmo")
    elif comando == "/foro":
        if resto:
            _preguntar_categoria(chat_id, resto)
        else:
            _foro_esperando.add(chat_id)
            enviar(chat_id, "¡Dale! Escríbeme lo que quieras contarle a la comunidad: cómo te fue en tu "
                            "parche, qué mejorarías de la app o cómo te sientes. Para salir, /cancelar.")
    elif comando == "/cancelar":
        _foro_pendiente.pop(chat_id, None)
        asistente.olvidar(chat_id)
        enviar(chat_id, "Listo, cancelado. Empezamos de cero cuando quieras.")
    elif comando in ("/ayuda", "/help"):
        enviar(chat_id, _ayuda())
    else:
        enviar(chat_id, f"Ese comando no lo conozco 😅\n\n{_ayuda()}")


def _conversar(session: Session, chat_id: str, joven: Joven, texto: str) -> None:
    """Texto libre: con Gemini, conversación; sin key, una guía hacia los comandos."""
    from . import services

    if not asistente.disponible():
        enviar(chat_id, f"Por ahora entiendo comandos 🙂\n\n{AYUDA}")
        return
    _api("sendChatAction", chat_id=chat_id, action="typing")
    try:
        respuesta, mostrados = asistente.conversar(session, joven, chat_id, texto)
    except asistente.GeminiNoDisponible:
        # Plan B: aunque no pueda conversar, le cuenta lo más útil (su parche) con los botones de siempre.
        enviar(chat_id, "Uy, ahorita tengo mucha gente hablándome y se me enredó la cadena 🚲 "
                        "Escríbeme de nuevo en un minutico. Mientras tanto, esto es lo que sé de tu parche:")
        enviar_estado(session, chat_id, joven)
        return
    botones: Botones = []
    # Los parches que el asistente mencionó también quedan como botones, por si es más fácil tocar.
    if mostrados:
        info = services.estado_para(session, joven)
        actual = (info.get("salida") or {}).get("id")
        tiene = info["estado"] in ("inscrito", "asignado")
        verbo = "Cambiarme a" if tiene else "Unirme a"
        vistos: set[int] = set()
        for p in mostrados:
            if p["parche_id"] not in vistos and p["parche_id"] != actual and len(vistos) < 3:
                vistos.add(p["parche_id"])
                botones.append([(f"{verbo} {p['nombre']} · {p['hora']}", f"unir:{p['parche_id']}")])
    enviar(chat_id, asistente.a_html(respuesta), botones or None)


def atender_boton(session: Session, chat_id: str, data: str, message_id: int | None = None) -> None:
    """Un toque en un botón del chat."""
    from . import services

    joven = _joven_de(session, chat_id)
    if joven is None:
        enviar(chat_id, "No reconozco este chat. Abre Parches CicloVida y toca «Conectar Telegram».")
        return
    if message_id is not None:  # la decisión ya se tomó: el mensaje queda sin botones
        _api("editMessageReplyMarkup", chat_id=chat_id, message_id=message_id, reply_markup={"inline_keyboard": []})

    accion, _, valor = data.partition(":")
    if accion == "unir" and valor.isdigit():
        _unirse(session, chat_id, joven, int(valor))
    elif accion == "cambiar" and valor.isdigit():
        _unirse(session, chat_id, joven, int(valor), confirmado=True)
    elif accion == "quedarme":
        enviar(chat_id, "Perfecto, sigues en tu parche 👍")
    elif accion == "opciones":
        _enviar_opciones(session, chat_id, joven)
    elif accion == "esperar":
        enviar(chat_id, "Perfecto, sigo buscando tu match 🔍 Apenas alguien encaje contigo, te aviso por aquí.")
    elif accion in ("confirmo", "novoy"):
        _responder(session, chat_id, joven, accion == "confirmo")
    elif accion == "foro":
        texto = _foro_pendiente.pop(chat_id, None)
        if valor == "cancelar" or texto is None:
            enviar(chat_id, "Listo, no publiqué nada." if valor == "cancelar"
                   else "Ese mensaje ya no está. Escribe /foro para publicar uno nuevo.")
            return
        _publicar_foro(session, chat_id, joven, valor, texto)
    elif accion == "parche":
        enviar_estado(session, chat_id, joven, buscar=True)


# ---------------------------------------------------------------- parche

def enviar_estado(session: Session, chat_id: str, joven: Joven, buscar: bool = False) -> None:
    """Lo mismo que muestra la pantalla de inicio, contado en el chat y con botones.

    Con `buscar`, si aún no tiene parche corre el match automático, igual que la app.
    """
    from . import services

    info = services.estado_para(session, joven)
    if buscar and info["estado"] == "sin_parche":
        services.emparejar_automatico(session, joven, avisar_telegram=False)
        info = services.estado_para(session, joven)
        if info["estado"] == "inscrito":
            s = info["salida"]
            enviar(chat_id, f"¡Match! 🎉 Te uní al <b>{h(s['nombre'])}</b>: hay gente con tus mismos planes.\n\n"
                            + _resumen_estado(info))
            return
    if info["estado"] == "en_espera":
        propuesta = propuesta_para(session, joven, info)
        if propuesta:
            enviar(chat_id, *propuesta)
            return
    if info["estado"] == "asignado":
        enviar(chat_id, _resumen_estado(info), [[("✅ Confirmo, voy", "confirmo"), ("❌ No voy", "novoy")]])
        return
    enviar(chat_id, _resumen_estado(info))


def propuesta_para(session: Session, joven: Joven, info: dict | None = None) -> tuple[str, Botones] | None:
    """"Hola X, todavía no tenemos parche confirmado…" con el parche que más se ajusta y sus botones."""
    from . import services

    info = info or services.estado_para(session, joven)
    p = (info.get("espera") or {}).get("mas_parecido")
    if not p:
        return None
    gente = ("Aún no hay nadie inscrito: ¡puedes ser quien lo arranque!" if p["inscritos"] == 0
             else f"Ya van {p['inscritos']} {'estudiante' if p['inscritos'] == 1 else 'estudiantes'}.")
    texto = (
        f"Hola {h(joven.nombre)}, todavía no tenemos parche confirmado: estamos buscando un match "
        "perfecto para ti 🔍\n\nPero si quieres elegir uno ahora mismo, este es el que más se ajusta "
        f"a tus preferencias:\n\n{_ficha(p)}\n{gente}"
    )
    botones = [
        [("✅ Unirme a este parche", f"unir:{p['id']}")],
        [("🔎 Ver otras opciones", "opciones")],
        [("⏳ Prefiero esperar el match", "esperar")],
    ]
    return texto, botones


def _ficha(p: dict) -> str:
    return (
        f"<b>{h(p['nombre'])}</b>\n"
        f"{h(p['actividad_nombre'])} a las {h(p['hora_nombre'])} · Estación {h(p['tramo']['nombre'])}\n"
        f"📍 {h(p['punto_encuentro'])} ({h(p['referencia'])})"
    )


def _enviar_opciones(session: Session, chat_id: str, joven: Joven) -> None:
    from . import services

    info = services.estado_para(session, joven)
    ya = (info.get("espera") or {}).get("mas_parecido") or {}
    opciones = [s for s in services.sugerencias_para(session, joven, limite=5) if s["id"] != ya.get("id")][:4]
    if not opciones:
        enviar(chat_id, "Por ahora no hay otras opciones parecidas. En la app puedes ver todos los parches.")
        return
    lineas = [f"{i + 1}. {_ficha(s)}\n   {s['inscritos']} inscritos" for i, s in enumerate(opciones)]
    botones = [[(f"{i + 1}. Unirme a {s['nombre']}", f"unir:{s['id']}")] for i, s in enumerate(opciones)]
    botones.append([("⏳ Prefiero esperar el match", "esperar")])
    enviar(chat_id, "Otras opciones que te pueden servir:\n\n" + "\n\n".join(lineas), botones)


def _unirse(session: Session, chat_id: str, joven: Joven, salida_id: int, confirmado: bool = False) -> None:
    from . import services

    info = services.estado_para(session, joven)
    actual = info.get("salida")
    cambio = info["estado"] in ("inscrito", "asignado") and actual is not None and actual["id"] != salida_id
    if cambio and not confirmado:
        # Igual que el diálogo de la app: cambiarse deja un cupo libre, así que se confirma con un toque.
        grupo = " y de tu grupo" if info["estado"] == "asignado" else ""
        enviar(chat_id, f"Ahora estás en el <b>{h(actual['nombre'])}</b>. Si te cambias, sales de ese parche{grupo} "
                        "y tu cupo queda libre para alguien más. ¿Te cambio?",
               [[("✅ Sí, cámbiame", f"cambiar:{salida_id}"), ("Me quedo", "quedarme")]])
        return
    try:
        services.unirse(session, joven, salida_id)
    except LookupError as e:
        enviar(chat_id, h(str(e)))
        return
    info = services.estado_para(session, joven)
    enviar(chat_id, ("¡Listo! Te cambié de parche 🔄" if cambio else "¡Listo! Te uniste 🙌") + "\n\n" + _resumen_estado(info))


def _responder(session: Session, chat_id: str, joven: Joven, va: bool) -> None:
    from . import services

    try:
        services.responder(session, joven, va)
        enviar(chat_id, "¡Buena! Tu parche ya sabe que vas 🚴 Nos vemos el domingo."
               if va else "Gracias por avisar: tu parche ya lo sabe. ¡Que sea el próximo domingo!")
    except LookupError as e:
        enviar(chat_id, h(str(e)))


_EMOJI_CIELO = {"sol": "☀️", "nubes_sol": "⛅", "nubes": "☁️", "lluvia": "🌧️", "tormenta": "⛈️"}


def _clima_y_racha(info: dict) -> str:
    """El pronóstico a la hora del parche y la racha, cuando los hay."""
    lineas = []
    if c := info.get("clima"):
        lineas.append(f"{_EMOJI_CIELO.get(c['icono'], '🌤️')} {h(c['cielo'])}, {c['temperatura']} °C · "
                      f"{c['lluvia']} % de lluvia. {h(c['consejo'])}")
    racha = (info.get("racha") or {}).get("actual", 0)
    if racha >= 2:
        lineas.append(f"🔥 Llevas {racha} domingos seguidos. Si vas, llegas a {racha + 1}.")
    return "\n\n" + "\n".join(lineas) if lineas else ""


def _resumen_estado(info: dict) -> str:
    """El mismo estado que muestra la pantalla de inicio, contado en un mensaje."""
    fecha = info["jornada"]["fecha"]
    estado = info["estado"]
    if estado == "asignado":
        g = info["grupo"]
        otros = ", ".join(h(m["nombre"]) for m in g["miembros"] if not m["soy_yo"])
        return (
            f"<b>{h(g['nombre'])}</b> · domingo {fecha}\n"
            f"{h(g['actividad_nombre'])} a las {h(g['hora_nombre'])}\n"
            f"📍 {h(g['punto_encuentro'])} ({h(g['referencia'])})\n"
            f"Van contigo: {otros or 'por definir'}\n"
            f"{g['confirmados']} de {len(g['miembros'])} han confirmado."
            + _clima_y_racha(info)
        )
    if estado == "inscrito":
        s = info["salida"]
        return (
            f"Estás en el <b>{h(s['nombre'])}</b> · domingo {fecha}\n"
            f"{h(s['actividad_nombre'])} a las {h(s['hora_nombre'])} en {h(s['tramo']['nombre'])}.\n"
            "El sábado a las 5:00 p. m. armamos tu grupo y te aviso por aquí."
            + _clima_y_racha(info)
        )
    if estado == "en_espera":
        return "Sigo buscando un parche con tus mismos planes 🔍 Apenas aparezca, te aviso por aquí."
    if estado == "pausado":
        return "Esta semana estás descansando. Si cambias de idea, elige un parche en la app."
    if estado == "suspendido":
        return "Tu cuenta está en revisión. Si crees que es un error, escríbenos desde la app."
    return f"Aún no tienes parche para el domingo {fecha}. Escribe /parche y te busco uno al toque."


# ---------------------------------------------------------------- foro

def _preguntar_categoria(chat_id: str, texto: str) -> None:
    from .catalog import FORO_CATEGORIAS

    texto = texto.strip()
    if len(texto) < 2:
        enviar(chat_id, "Ese mensaje quedó muy corto. Escribe /foro y cuéntanos un poco más.")
        return
    if len(texto) > config.FORO_MAX:
        enviar(chat_id, f"Ese mensaje es muy largo (máximo {config.FORO_MAX} caracteres). Intenta resumirlo con /foro.")
        return
    _foro_pendiente[chat_id] = texto
    botones = [[(c["nombre"], f"foro:{c['id']}")] for c in FORO_CATEGORIAS]
    botones.append([("Cancelar", "foro:cancelar")])
    enviar(chat_id, "¿En qué tema lo publico?", botones)


def _publicar_foro(session: Session, chat_id: str, joven: Joven, categoria: str, texto: str) -> None:
    from . import services
    from .catalog import FORO_CATEGORIAS, FORO_IDS

    if categoria not in FORO_IDS:
        enviar(chat_id, "Ese tema no existe. Escribe /foro para intentarlo de nuevo.")
        return
    try:
        services.foro_publicar(session, joven, categoria, texto)
    except LookupError as e:
        enviar(chat_id, h(str(e)))
        return
    nombre = next(c["nombre"] for c in FORO_CATEGORIAS if c["id"] == categoria)
    enviar(chat_id, f"¡Publicado en «{h(nombre)}»! ✅ Lo ves junto a los demás en la pestaña Foro de la app.")
