"""Emparejamiento automático (match), lista de espera, notificaciones y foro comunal."""

from datetime import timedelta

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import services
from app.db import engine
from app.main import app
from app.models import Espera, Joven
from test_api import ADMIN, armar, auth, estado, nuevo, parche, setup_function, unir  # noqa: F401


def test_preferencias_persisten_incluso_al_limpiarlas():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")  # se registra con estación panamericana
        # volver a "Cualquiera" (null) también debe guardarse
        r = c.patch("/api/yo", json={"tramo_id": None, "franja": None}, headers=auth(ana))
        assert r.status_code == 200 and r.json()["tramo_id"] is None
        # y un cambio normal persiste al volver a consultar
        r = c.patch("/api/yo", json={"comuna": 2, "actividad": "trotar", "ritmo": "rapido"}, headers=auth(ana))
        assert r.status_code == 200
        yo = c.get("/api/yo", headers=auth(ana)).json()
        assert yo["comuna"] == 2 and yo["actividad"] == "trotar" and yo["ritmo"] == "rapido"
        assert yo["tramo_id"] is None


def test_historial_muestra_parches_pasados_y_su_gente():
    with TestClient(app) as c:
        tokens = [nuevo(c, n) for n in ["Ana", "Luis", "Sara"]]
        p = parche(c, tokens[0])
        for t in tokens:
            unir(c, t, p["id"])

        # antes de que termine la jornada no hay historial
        assert c.get("/api/yo/historial", headers=auth(tokens[0])).json() == []

        armar(c)
        c.post("/api/admin/finalizar", headers=ADMIN)
        c.post("/api/yo/encuesta", json={"asistio": True, "volveria": True, "bienestar": 5}, headers=auth(tokens[0]))

        h = c.get("/api/yo/historial", headers=auth(tokens[0])).json()
        assert len(h) == 1
        assert h[0]["asistio"] is True and h[0]["volveria"] is True
        g = h[0]["grupo"]
        assert len(g["miembros"]) == 3 and g["miembros"][0]["soy_yo"]
        assert {m["nombre"] for m in g["miembros"]} == {"Ana", "Luis", "Sara"}

        # quien no respondió la encuesta ve el domingo con asistencia sin responder
        h2 = c.get("/api/yo/historial", headers=auth(tokens[1])).json()
        assert len(h2) == 1 and h2[0]["asistio"] is None


def test_declaracion_de_mayoria_de_edad_obligatoria_y_con_constancia():
    from test_api import codigo, registro

    with TestClient(app) as c:
        correo = "mayor@usbcali.edu.co"
        # sin la casilla marcada: rechazado con mensaje claro
        datos = registro("Ana", correo=correo, codigo=codigo(c, correo), declara_mayor=False)
        r = c.post("/api/jovenes", json=datos)
        assert r.status_code == 422 and "18" in r.text

        # con la casilla: pasa, y queda la constancia con fecha en la base
        datos["declara_mayor"] = True
        datos["codigo"] = codigo(c, correo)
        r = c.post("/api/jovenes", json=datos)
        assert r.status_code == 201
        with Session(engine) as s:
            j = s.exec(select(Joven)).one()
            assert j.declara_mayor is True and j.declara_mayor_en is not None


def test_ingreso_con_el_mismo_correo():
    with TestClient(app) as c:
        correo = "vuelve@usbcali.edu.co"
        token = nuevo(c, "Ana", correo=correo)

        # pedir código "para registro" con un correo ya registrado: rechazado con guía
        r = c.post("/api/verificacion", json={"correo": correo})
        assert r.status_code == 409 and "Ya tengo cuenta" in r.json()["detail"]

        # para ingreso sí, y la sesión que devuelve es la misma cuenta de siempre
        r = c.post("/api/verificacion", json={"correo": correo, "para": "ingreso"})
        assert r.status_code == 200
        codigo = r.json()["codigo_demo"]
        s = c.post("/api/sesiones", json={"correo": correo, "codigo": codigo})
        assert s.status_code == 200
        assert s.json()["token"] == token and s.json()["joven"]["nombre"] == "Ana"

        # ingreso con un correo sin cuenta: rechazado al pedir el código
        r = c.post("/api/verificacion", json={"correo": "nadie@usbcali.edu.co", "para": "ingreso"})
        assert r.status_code == 409

        # código equivocado: rechazado
        r = c.post("/api/verificacion", json={"correo": correo, "para": "ingreso"})
        malo = "000000" if r.json()["codigo_demo"] != "000000" else "111111"
        assert c.post("/api/sesiones", json={"correo": correo, "codigo": malo}).status_code == 422


def test_espera_ofrece_el_mas_parecido_aunque_este_vacio():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")  # bici en Panamericana, sin nadie más
        e = c.post("/api/yo/match", headers=auth(ana)).json()
        assert e["estado"] == "en_espera"
        p = e["espera"]["mas_parecido"]
        assert p is not None and p["tramo"]["id"] == "panamericana" and p["actividad"] == "bici"
        assert p["inscritos"] == 0
        # "Unirme igual": toma la iniciativa y estrena el parche
        r = unir(c, ana, p["id"])
        assert r.status_code == 200 and r.json()["estado"] == "inscrito"


def match(c, tok):
    return c.post("/api/yo/match", headers=auth(tok)).json()


def test_match_automatico_une_al_parche_con_gente():
    with TestClient(app) as c:
        luis = nuevo(c, "Luis")
        p = parche(c, luis)  # bici, panamericana, 8:00
        unir(c, luis, p["id"])

        # Ana tiene las mismas preferencias: el match la une al parche de Luis sin que elija
        ana = nuevo(c, "Ana")
        e = match(c, ana)
        assert e["estado"] == "inscrito" and e["salida"]["id"] == p["id"]


def test_match_prefiere_el_parche_mas_afin():
    with TestClient(app) as c:
        # dos parches de bici en Panamericana con gente: 8:00 (ritmo rápido) y 9:30 (moderado)
        luis = nuevo(c, "Luis", ritmo="rapido")
        p8 = parche(c, luis, franja="08:00")
        unir(c, luis, p8["id"])
        sara = nuevo(c, "Sara", ritmo="moderado")
        p930 = parche(c, sara, franja="09:30")
        unir(c, sara, p930["id"])

        # Ana es moderada y sin hora preferida: queda con Sara, no con Luis
        ana = nuevo(c, "Ana", ritmo="moderado")
        e = match(c, ana)
        assert e["estado"] == "inscrito" and e["salida"]["id"] == p930["id"]


def test_espera_y_aviso_cuando_aparece_parche():
    with TestClient(app) as c:
        # nadie más inscrito: Ana queda en lista de espera
        ana = nuevo(c, "Ana")
        e = match(c, ana)
        assert e["estado"] == "en_espera" and e["espera"]["sugerencias"] == []

        # pedir match otra vez no duplica la espera
        match(c, ana)
        with Session(engine) as s:
            assert len(s.exec(select(Espera)).all()) == 1

        # Luis se une a un parche compatible; el tick revisa las esperas y une a Ana
        luis = nuevo(c, "Luis")
        p = parche(c, luis)
        unir(c, luis, p["id"])
        with Session(engine) as s:
            assert services.revisar_esperas(s) == 1

        e = estado(c, ana)
        assert e["estado"] == "inscrito" and e["salida"]["id"] == p["id"]

        # y le queda la notificación, que puede marcar como leída
        notis = c.get("/api/yo/notificaciones", headers=auth(ana)).json()
        assert len(notis) == 1 and not notis[0]["leida"] and "parche" in notis[0]["titulo"].lower()
        c.post("/api/yo/notificaciones/leidas", headers=auth(ana))
        assert c.get("/api/yo/notificaciones", headers=auth(ana)).json()[0]["leida"]


def test_espera_larga_muestra_sugerencias():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        assert match(c, ana)["estado"] == "en_espera"
        # un parche parecido (patines: misma familia sobre ruedas) con gente, en otra estación
        kev = nuevo(c, "Kevin", actividad="patines", tramo_id="ingenio")
        p = parche(c, kev, tramo="ingenio", actividad="patines")
        unir(c, kev, p["id"])

        # todavía no pasa el lapso: sin sugerencias
        assert estado(c, ana)["espera"]["sugerencias"] == []

        # envejecemos la espera y aparecen, con el parche con gente de primero
        with Session(engine) as s:
            esp = s.exec(select(Espera)).one()
            esp.creado_en = esp.creado_en - timedelta(minutes=60)
            s.add(esp)
            s.commit()
        e = estado(c, ana)
        sug = e["espera"]["sugerencias"]
        assert sug and sug[0]["id"] == p["id"] and sug[0]["inscritos"] == 1

        # cancelar la espera la borra
        e = c.delete("/api/yo/espera", headers=auth(ana)).json()
        assert e["estado"] == "sin_parche"


def test_unirse_a_mano_borra_la_espera():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        assert match(c, ana)["estado"] == "en_espera"
        p = parche(c, ana)
        unir(c, ana, p["id"])
        with Session(engine) as s:
            assert s.exec(select(Espera)).first() is None


SOCIAL = {"1": "a", "2": "a", "3": "b", "4": "a", "5": "a"}
CASERO = {"1": "b", "2": "b", "3": "a", "4": "b", "5": "b"}


def test_quiz_es_opcional_valida_y_privado():
    with TestClient(app) as c:
        cat = c.get("/api/catalogo").json()
        assert len(cat["quiz"]["preguntas"]) == 5

        ana = nuevo(c, "Ana")
        assert c.get("/api/yo", headers=auth(ana)).json()["quiz_respondido"] is False

        # incompleto o con una opción inventada: rechazado
        assert c.post("/api/yo/quiz", json={"respuestas": {"1": "a"}}, headers=auth(ana)).status_code == 422
        malas = {**SOCIAL, "3": "z"}
        assert c.post("/api/yo/quiz", json={"respuestas": malas}, headers=auth(ana)).status_code == 422

        assert c.post("/api/yo/quiz", json={"respuestas": SOCIAL}, headers=auth(ana)).status_code == 200
        # el perfil solo dice que lo respondió: las respuestas y puntajes nunca salen del servidor
        yo = c.get("/api/yo", headers=auth(ana)).json()
        assert yo["quiz_respondido"] is True
        assert "quiz" not in yo and "respuestas" not in yo


def test_match_usa_el_quiz_solo_como_desempate():
    """Dos parches iguales en lo estructural (misma comuna, hora y actividad):
    el quiz inclina la balanza hacia la gente con gustos parecidos."""
    with TestClient(app) as c:
        luis = nuevo(c, "Luis", tramo_id="torres-comfandi", comuna=5)
        c.post("/api/yo/quiz", json={"respuestas": SOCIAL}, headers=auth(luis))
        p_luis = parche(c, luis, tramo="torres-comfandi")
        unir(c, luis, p_luis["id"])

        sara = nuevo(c, "Sara", tramo_id="metropolitana", comuna=5)
        c.post("/api/yo/quiz", json={"respuestas": CASERO}, headers=auth(sara))
        p_sara = parche(c, sara, tramo="metropolitana")
        unir(c, sara, p_sara["id"])

        # Ana no fija estación: los dos parches le sirven igual, pero comparte estilo con Luis
        ana = nuevo(c, "Ana", tramo_id=None, comuna=5)
        c.post("/api/yo/quiz", json={"respuestas": SOCIAL}, headers=auth(ana))
        e = c.post("/api/yo/match", headers=auth(ana)).json()
        assert e["estado"] == "inscrito" and e["salida"]["id"] == p_luis["id"]


def test_bot_telegram_empata_las_funciones(monkeypatch):
    """El bot espeja la app: /start vincula, /parche muestra el estado, /confirmo confirma,
    y el aviso del sábado también llega por el chat."""
    from app import telegram

    enviados: list[tuple[str, str, list | None]] = []
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto, botones)))

    with TestClient(app) as c:
        tokens = [nuevo(c, n) for n in ["Ana", "Luis", "Sara"]]
        p = parche(c, tokens[0])
        for t in tokens:
            unir(c, t, p["id"])

        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            ana.telegram_codigo = "abc123"
            s.add(ana)
            s.commit()

            # chat sin vincular: lo manda a la app
            telegram.atender(s, "555", "/parche")
            assert "Conectar Telegram" in enviados[-1][1]
            # /start con el código: vincula, saluda con la ayuda y cuenta su estado
            telegram.atender(s, "555", "/start abc123")
            assert "Ana" in enviados[-2][1] and "/parche" in enviados[-2][1]
            assert p["nombre"] in enviados[-1][1]
            # /parche antes del sábado: inscrito, el grupo se arma después
            telegram.atender(s, "555", "/parche")
            assert p["nombre"] in enviados[-1][1] and "sábado" in enviados[-1][1]
            # /confirmo antes de tiempo: el mismo mensaje claro de la app
            telegram.atender(s, "555", "/confirmo")
            assert "sábado" in enviados[-1][1]
            # comando inventado: ayuda
            telegram.atender(s, "555", "/baile")
            assert "/ayuda" in enviados[-1][1] or "/parche" in enviados[-1][1]

        armar(c)
        # el aviso del sábado llegó al chat vinculado (y solo a ese: Luis y Sara no vincularon)
        avisos = [(t, b) for chat, t, b in enviados if chat == "555" and "grupo del domingo" in t]
        assert len(avisos) == 1
        assert ("✅ Confirmo, voy", "confirmo") in avisos[0][1][0]  # el aviso trae los botones

        with Session(engine) as s:
            # tocar el botón del aviso confirma, igual que el botón de la app
            telegram.atender_boton(s, "555", "confirmo")
            assert "vas" in enviados[-1][1]
            # /parche ya asignado: punto de encuentro, compañeros y botones para responder
            telegram.atender(s, "555", "/parche")
            assert "Luis" in enviados[-1][1] and "📍" in enviados[-1][1] and enviados[-1][2]

        assert estado(c, tokens[0])["mi_respuesta"] == "confirmado"


def test_bot_telegram_propone_parche_y_publica_en_el_foro(monkeypatch):
    """Sin parche: el bot propone el que más se ajusta y se puede elegir con un botón.
    Y desde el chat se publica en el foro (solo publicar)."""
    from app import telegram

    enviados: list[tuple[str, str, list | None]] = []
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto, botones)))

    with TestClient(app) as c:
        ana_tok = nuevo(c, "Ana")  # bici en Panamericana; nadie más inscrito
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            ana.telegram_chat_id = "777"
            s.add(ana)
            s.commit()

        # entrar en espera desde la app: la propuesta le llega sola al chat
        assert c.post("/api/yo/match", headers=auth(ana_tok)).json()["estado"] == "en_espera"
        texto, botones = enviados[-1][1], enviados[-1][2]
        assert "Hola Ana, todavía no tenemos parche confirmado" in texto
        assert "el que más se ajusta a tus preferencias" in texto
        unir_data = botones[0][0][1]
        assert unir_data.startswith("unir:")

        with Session(engine) as s:
            # /parche en espera repite la propuesta, sin duplicar avisos
            telegram.atender(s, "777", "/parche")
            assert "todavía no tenemos parche" in enviados[-1][1]
            # "Ver otras opciones" y "Prefiero esperar" responden
            telegram.atender_boton(s, "777", "opciones")
            assert enviados[-1][2]
            telegram.atender_boton(s, "777", "esperar")
            assert "sigo buscando" in enviados[-1][1].lower()
            # tocar "Unirme a este parche" la inscribe
            telegram.atender_boton(s, "777", unir_data)
            assert "Te uniste" in enviados[-1][1]
        e = estado(c, ana_tok)
        assert e["estado"] == "inscrito" and e["salida"]["id"] == int(unir_data.split(":")[1])

        with Session(engine) as s:
            # foro en dos pasos: /foro, el texto, y la categoría con botón
            telegram.atender(s, "777", "/foro")
            telegram.atender(s, "777", "¡Primer domingo en parche y fue <genial>!")
            assert "¿En qué tema" in enviados[-1][1]
            telegram.atender_boton(s, "777", "foro:parches")
            assert "Publicado" in enviados[-1][1]
            # foro en un paso, y cancelar a la mitad no publica nada
            telegram.atender(s, "777", "/foro La app podría mostrar el clima")
            telegram.atender_boton(s, "777", "foro:cancelar")

        foro = c.get("/api/foro", headers=auth(ana_tok)).json()
        assert len(foro) == 1 and foro[0]["texto"] == "¡Primer domingo en parche y fue <genial>!"
        assert foro[0]["categoria"] == "parches" and foro[0]["es_mio"]


def _gemini_guionado(pasos):
    """Simula a Gemini: cada llamada devuelve el siguiente paso del guion y guarda lo que recibió."""
    recibidos = []

    def llamar(cuerpo):
        import copy

        recibidos.append(copy.deepcopy(cuerpo))  # copia: la lista de la conversación sigue creciendo
        paso = pasos[len(recibidos) - 1]
        partes = [{"functionCall": {"name": n, "args": a}} for n, a in paso] if isinstance(paso, list) else [{"text": paso}]
        return {"candidates": [{"content": {"role": "model", "parts": partes}}]}

    return llamar, recibidos


def test_bot_conversacional_con_gemini(monkeypatch):
    """Texto libre: Gemini decide qué función usar y el bot actúa de verdad sobre la base."""
    from app import asistente, config, telegram

    enviados: list[tuple[str, str, list | None]] = []
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto, botones)))
    monkeypatch.setattr(config, "GEMINI_API_KEY", "clave-de-prueba")

    with TestClient(app) as c:
        luis = nuevo(c, "Luis", actividad="trotar")
        p = parche(c, luis, franja="08:00", actividad="trotar")
        unir(c, luis, p["id"])
        ana_tok = nuevo(c, "Ana")
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            ana.telegram_chat_id = "888"
            s.add(ana)
            s.commit()

        # 1) "quiero trotar temprano": busca parches y responde con botones de los que encontró
        llamar, recibidos = _gemini_guionado([
            [("buscar_parches", {"actividad": "trotar", "hora": "08:00", "estacion": "panamericana"})],
            "Encontré el parche de trotar a las 8:00 en Panamericana, ya va 1 persona. ¿Te uno?",
        ])
        monkeypatch.setattr(asistente, "_llamar_gemini", llamar)
        with Session(engine) as s:
            telegram.atender(s, "888", "quiero trotar el domingo temprano por panamericana")
        assert "Te uno" in enviados[-1][1]
        assert enviados[-1][2] and enviados[-1][2][0][0][1] == f"unir:{p['id']}"
        # lo que devolvió la función le llegó a Gemini: datos reales, no inventados
        respuesta_fn = recibidos[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
        assert respuesta_fn["parches"][0]["parche_id"] == p["id"] and respuesta_fn["parches"][0]["inscritos"] == 1
        # a Gemini no le llega el correo ni la universidad
        assert "usbcali" not in str(recibidos[0]).lower() and "San Buenaventura" not in str(recibidos[0])

        # 2) "sí, úneme": recuerda la conversación y la une de verdad
        llamar, recibidos = _gemini_guionado([
            [("unirme_a_parche", {"parche_id": p["id"]})],
            "¡Listo! Quedaste en el parche. El sábado a las 5 armamos tu grupo 🏃",
        ])
        monkeypatch.setattr(asistente, "_llamar_gemini", llamar)
        with Session(engine) as s:
            telegram.atender(s, "888", "sí, úneme")
        assert len(recibidos[0]["contents"]) == 3  # los dos turnos anteriores + este mensaje
        assert estado(c, ana_tok)["salida"]["id"] == p["id"]
        assert enviados[-1][2] is None  # ya tiene parche: sin botones de unirse

        # 3) publicar en el foro conversando
        llamar, _ = _gemini_guionado([
            [("publicar_en_foro", {"categoria": "animo", "texto": "Feliz de salir en parche <3"})],
            "Publicado en «Cómo me siento» ✅",
        ])
        monkeypatch.setattr(asistente, "_llamar_gemini", llamar)
        with Session(engine) as s:
            telegram.atender(s, "888", "sí, publícalo")
        foro = c.get("/api/foro", headers=auth(ana_tok)).json()
        assert foro[0]["texto"] == "Feliz de salir en parche <3" and foro[0]["categoria"] == "animo"
        assert "&lt;" not in foro[0]["texto"]  # se guarda tal cual; solo se escapa al mostrar en Telegram

        # 4) si Gemini está saturado (503) aun reintentando, el bot se disculpa y cuenta el estado real
        def falla(_):
            raise asistente.GeminiNoDisponible("503 high demand")

        monkeypatch.setattr(asistente, "_llamar_gemini", falla)
        with Session(engine) as s:
            telegram.atender(s, "888", "quiero saber como voy")
        assert "mucha gente" in enviados[-2][1]
        assert p["nombre"] in enviados[-1][1]  # plan B: su parche de verdad, sin depender de Gemini

        # 5) sin key, el texto libre guía hacia los comandos
        monkeypatch.setattr(config, "GEMINI_API_KEY", "")
        with Session(engine) as s:
            telegram.atender(s, "888", "hola")
        assert "entiendo comandos" in enviados[-1][1]


def test_gemini_reintenta_ante_503_y_cambia_de_modelo(monkeypatch):
    """Un 503 de "alta demanda" no tumba la respuesta: prueba otro modelo y otra ronda."""
    import httpx

    from app import asistente, config

    monkeypatch.setattr(config, "GEMINI_API_KEY", "clave-de-prueba")
    monkeypatch.setattr(config, "GEMINI_MODEL", "modelo-a")
    monkeypatch.setattr(config, "GEMINI_RESPALDO", ["modelo-b"])
    monkeypatch.setattr(asistente, "ESPERAS", (0, 0))
    pedidos = []

    def post(url, **_):
        pedidos.append(url.split("/models/")[1].split(":")[0])
        codigo = 503 if len(pedidos) < 3 else 200  # a y b saturados en la 1.ª ronda; a responde en la 2.ª
        return httpx.Response(codigo, json={"candidates": []}, request=httpx.Request("POST", url))

    monkeypatch.setattr(asistente.httpx, "post", post)
    assert asistente._llamar_gemini({}) == {"candidates": []}
    assert pedidos == ["modelo-a", "modelo-b", "modelo-a"]

    # si nunca responde, avisa con GeminiNoDisponible (y el bot usa su plan B)
    pedidos.clear()
    monkeypatch.setattr(asistente.httpx, "post", lambda url, **_: httpx.Response(503, request=httpx.Request("POST", url)))
    import pytest

    with pytest.raises(asistente.GeminiNoDisponible):
        asistente._llamar_gemini({})


def test_asistente_cambia_de_parche_solo_con_confirmacion():
    """El bot cambia de parche él mismo, pero el servidor exige la confirmación, como el diálogo de la app."""
    from app import asistente

    with TestClient(app) as c:
        ana_tok = nuevo(c, "Ana")
        p1 = parche(c, ana_tok, franja="08:00")
        p2 = parche(c, ana_tok, franja="09:30")
        unir(c, ana_tok, p1["id"])
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            # sin confirmar: no la mueve, y le dice a Gemini que pregunte
            r = asistente.ejecutar(s, ana, "unirme_a_parche", {"parche_id": p2["id"]})
            assert r["ok"] is False and r["requiere_confirmacion"] and r["parche_actual"]["parche_id"] == p1["id"]
        assert estado(c, ana_tok)["salida"]["id"] == p1["id"]

        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            # confirmado: la cambia de verdad
            r = asistente.ejecutar(s, ana, "unirme_a_parche", {"parche_id": p2["id"], "confirmo_cambio": True})
            assert r["ok"] is True and r["cambio_de_parche"] is True
            r = asistente.ejecutar(s, ana, "funcion_inventada", {})
            assert r["ok"] is False
            r = asistente.ejecutar(s, ana, "buscar_parches", {"estacion": "Marte"})
            assert "error" in r and "Panamericana" in r["estaciones"]
        assert estado(c, ana_tok)["salida"]["id"] == p2["id"]


def test_bot_cambia_de_parche_con_botones(monkeypatch):
    from app import telegram

    enviados: list[tuple[str, str, list | None]] = []
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto, botones)))
    with TestClient(app) as c:
        ana_tok = nuevo(c, "Ana")
        p1 = parche(c, ana_tok, franja="08:00")
        p2 = parche(c, ana_tok, franja="11:00")
        unir(c, ana_tok, p1["id"])
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            ana.telegram_chat_id = "999"
            s.add(ana)
            s.commit()
            # tocar "unir" a otro parche pide confirmar con dos botones
            telegram.atender_boton(s, "999", f"unir:{p2['id']}")
            assert p1["nombre"] in enviados[-1][1]
            assert enviados[-1][2] == [[("✅ Sí, cámbiame", f"cambiar:{p2['id']}"), ("Me quedo", "quedarme")]]
            # "Me quedo" no cambia nada
            telegram.atender_boton(s, "999", "quedarme")
        assert estado(c, ana_tok)["salida"]["id"] == p1["id"]
        with Session(engine) as s:
            telegram.atender_boton(s, "999", f"cambiar:{p2['id']}")
            assert "cambié" in enviados[-1][1]
        assert estado(c, ana_tok)["salida"]["id"] == p2["id"]


def test_enlaces_de_telegram_conservan_el_codigo(monkeypatch):
    """El enlace web va directo a Telegram Web con el código dentro (t.me lo pierde al pasar a la web)."""
    from urllib.parse import unquote

    from app import config, telegram

    monkeypatch.setattr(config, "TELEGRAM_TOKEN", "123:abc")
    monkeypatch.setattr(config, "TELEGRAM_BOT", "Parcherito_bot")
    assert telegram.enlace_para("c0d1g0") == "https://t.me/Parcherito_bot?start=c0d1g0"
    web = telegram.enlace_web_para("c0d1g0")
    assert web.startswith("https://web.telegram.org/k/#?tgaddr=")
    assert unquote(web.split("tgaddr=")[1]) == "tg://resolve?domain=Parcherito_bot&start=c0d1g0"


def test_un_chat_de_telegram_va_con_una_sola_cuenta(monkeypatch):
    """Demo con un solo Telegram: al conectarlo desde otra cuenta, el chat pasa a esa cuenta."""
    from app import telegram

    enviados: list[tuple[str, str, list | None]] = []
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto, botones)))
    with TestClient(app) as c:
        ana_tok, beto_tok = nuevo(c, "Ana"), nuevo(c, "Beto")
        unir(c, ana_tok, parche(c, ana_tok, franja="08:00")["id"])
        unir(c, beto_tok, parche(c, beto_tok, franja="11:00")["id"])
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            beto = s.exec(select(Joven).where(Joven.nombre == "Beto")).one()
            ana.telegram_codigo, beto.telegram_codigo = "cod-ana", "cod-beto"
            s.add(ana)
            s.add(beto)
            s.commit()

            telegram.atender(s, "555", "/start cod-ana")
            telegram.atender(s, "555", "/cuenta")
            assert "Ana" in enviados[-1][1]
            # Beto conecta el mismo chat: pasa a Beto y Ana queda sin chat
            telegram.atender(s, "555", "/start cod-beto")
            assert "estaba conectado a la cuenta de Ana" in enviados[-2][1]
            telegram.atender(s, "555", "/parche")
            assert "11:00" in enviados[-1][1]  # habla como Beto
            s.refresh(ana)
            assert ana.telegram_chat_id is None
            # /start sin código dice con qué cuenta está y cómo cambiarla
            telegram.atender(s, "555", "/start")
            assert "Beto" in enviados[-1][1] and "Conectar Telegram" in enviados[-1][1]
            # /desconectar lo suelta
            telegram.atender(s, "555", "/desconectar")
            telegram.atender(s, "555", "/parche")
            assert "No reconozco este chat" in enviados[-1][1]

            # datos viejos: el chat pegado a dos cuentas -> no adivina, pide reconectar
            ana.telegram_chat_id = beto.telegram_chat_id = "777"
            s.add(ana)
            s.add(beto)
            s.commit()
            telegram.atender(s, "777", "/parche")
            assert "varias cuentas" in enviados[-1][1] and "Ana" in enviados[-1][1]
            # ...y /desconectar, que el mismo aviso sugiere, sí funciona: lo suelta de todas
            telegram.atender(s, "777", "/desconectar")
            assert "desconecté este chat" in enviados[-1][1]
            s.refresh(ana)
            s.refresh(beto)
            assert ana.telegram_chat_id is None and beto.telegram_chat_id is None
            telegram.atender(s, "777", "/parche")
            assert "No reconozco este chat" in enviados[-1][1]
            # y conectar desde la app (/start con código) también resuelve el caso de varias cuentas
            ana.telegram_chat_id = beto.telegram_chat_id = "888"
            beto.telegram_codigo = "cod-beto-2"
            s.add(ana)
            s.add(beto)
            s.commit()
            telegram.atender(s, "888", "/start cod-beto-2")
            s.refresh(ana)
            assert ana.telegram_chat_id is None and "Beto" in enviados[-2][1]

        # desde la app también se puede desconectar
        assert c.delete("/api/yo/telegram", headers=auth(ana_tok)).json() == {"ok": True}
        with Session(engine) as s:
            ana = s.exec(select(Joven).where(Joven.nombre == "Ana")).one()
            assert ana.telegram_chat_id is None and ana.telegram_codigo not in (None, "cod-ana")


def test_foro_publicar_listar_borrar():
    with TestClient(app) as c:
        ana = nuevo(c, "ana maría")
        luis = nuevo(c, "Luis")

        r = c.post("/api/foro", json={"categoria": "parches", "texto": "El parche Samán estuvo genial"},
                   headers=auth(ana))
        assert r.status_code == 201 and r.json()["nombre"] == "Ana" and r.json()["universidad"] == "USB Cali"
        c.post("/api/foro", json={"categoria": "app", "texto": "Me gustaría ver el clima del domingo"},
               headers=auth(luis))

        lista = c.get("/api/foro", headers=auth(ana)).json()
        assert len(lista) == 2 and lista[0]["texto"].startswith("Me gustaría")  # más reciente primero
        assert lista[1]["es_mio"] and not lista[0]["es_mio"]

        solo_app = c.get("/api/foro", params={"categoria": "app"}, headers=auth(ana)).json()
        assert len(solo_app) == 1

        # solo el autor puede borrar
        ajeno = c.delete(f"/api/foro/{lista[0]['id']}", headers=auth(ana))
        assert ajeno.status_code == 409
        assert c.delete(f"/api/foro/{lista[1]['id']}", headers=auth(ana)).status_code == 204
        assert len(c.get("/api/foro", headers=auth(ana)).json()) == 1

        # categoría inventada: rechazada
        assert c.post("/api/foro", json={"categoria": "otra", "texto": "hola"}, headers=auth(ana)).status_code == 422


def test_catalogo_trae_foro_espera_y_coordenadas():
    with TestClient(app) as c:
        cat = c.get("/api/catalogo").json()
        assert {x["id"] for x in cat["foro_categorias"]} == {"parches", "app", "animo"}
        assert cat["espera_minutos"] > 0
        assert all("lat" in t and "lng" in t for t in cat["tramos"])


def test_borrar_datos_limpia_espera_y_foro():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        match(c, ana)
        c.post("/api/foro", json={"categoria": "animo", "texto": "Muy contenta de salir"}, headers=auth(ana))
        assert c.delete("/api/yo", headers=auth(ana)).status_code == 204
        with Session(engine) as s:
            assert s.exec(select(Espera)).first() is None
            assert s.exec(select(Joven)).first() is None
        luis = nuevo(c, "Luis")
        assert c.get("/api/foro", headers=auth(luis)).json() == []
