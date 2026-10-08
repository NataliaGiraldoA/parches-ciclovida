"""Chat del parche: opcional, privado, entre personas reales y con simulados que conversan con Gemini."""

import json

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import asistente, chat_simulado, config
from app.db import engine
from app.main import app
from app.models import Inscripcion, Joven
from app.seed import sembrar
from test_api import auth, nuevo, unir


@pytest.fixture(autouse=True)
def _sin_pausas(monkeypatch):
    monkeypatch.setattr(config, "CHAT_PAUSA_SEG", 0)  # sin "escribiendo…" en las pruebas


def _parche_con_simulados(c, tok) -> dict:
    """El parche de bici en Panamericana con más simulados inscritos."""
    lista = c.get("/api/parches", params={"tramo": "panamericana", "actividad": "bici"}, headers=auth(tok)).json()["parches"]
    return max(lista, key=lambda p: p["inscritos"])


def _chat(c, tok, **params):
    return c.get("/api/yo/chat", params=params, headers=auth(tok)).json()


def test_chat_es_opcional_privado_y_entre_personas_reales():
    sembrar(total=300, reset=True)
    with TestClient(app) as c:
        # sin parche no hay chat
        sin = nuevo(c, "Carla")
        assert _chat(c, sin) == {"disponible": False, "unido": False}
        assert c.post("/api/yo/chat/unirme", headers=auth(sin)).status_code == 409

        ana = nuevo(c, "Ana")
        p = _parche_con_simulados(c, ana)
        unir(c, ana, p["id"])
        # con parche pero sin unirse: solo cuántos hay, ni nombres ni mensajes
        e = _chat(c, ana)
        assert e["disponible"] and not e["unido"] and e["en_el_chat"] == 0
        assert "mensajes" not in e and "miembros" not in e
        assert c.post("/api/yo/chat/mensajes", json={"texto": "hola"}, headers=auth(ana)).status_code == 409

        # unirse: entran algunos simulados del parche y, sin Gemini, uno saluda con un mensaje fijo
        e = c.post("/api/yo/chat/unirme", headers=auth(ana)).json()
        assert e["unido"] and any(m["soy_yo"] for m in e["miembros"])
        simulados = [m for m in e["miembros"] if m["simulado"]]
        assert 1 <= len(simulados) <= config.CHAT_MAX_SIMULADOS
        e = _chat(c, ana)
        assert len(e["mensajes"]) == 1 and e["mensajes"][0]["simulado"] and "Ana" in e["mensajes"][0]["texto"]

        # Ana escribe; sin Gemini los simulados no contestan
        r = c.post("/api/yo/chat/mensajes", json={"texto": "¿Alguien lleva bomba de aire?"}, headers=auth(ana))
        assert r.status_code == 201 and r.json()["es_mio"]
        ultimo = r.json()["id"]
        assert _chat(c, ana, despues_de=ultimo)["mensajes"] == []

        # otra persona real entra al mismo chat y conversan de verdad
        beto = nuevo(c, "Beto")
        unir(c, beto, p["id"])
        c.post("/api/yo/chat/unirme", headers=auth(beto))
        textos = [m["texto"] for m in _chat(c, beto)["mensajes"]]
        assert "¿Alguien lleva bomba de aire?" in textos
        c.post("/api/yo/chat/mensajes", json={"texto": "Yo llevo una, Ana"}, headers=auth(beto))
        nuevos = _chat(c, ana, despues_de=ultimo)["mensajes"]
        assert "Beto" in nuevos[0]["texto"] and nuevos[0]["simulado"]  # un simulado le da la bienvenida
        reales = [m for m in nuevos if not m["simulado"]]
        assert [m["texto"] for m in reales] == ["Yo llevo una, Ana"] and not reales[0]["es_mio"]
        assert reales[0]["universidad"] == "USB Cali"
        assert any(m["nombre"] == "Beto" for m in _chat(c, ana)["miembros"])

        # salir del chat: deja de verlo y los demás dejan de verlo a él
        e = c.delete("/api/yo/chat", headers=auth(beto)).json()
        assert not e["unido"] and "mensajes" not in e
        assert not any(m["nombre"] == "Beto" for m in _chat(c, ana)["miembros"])

        # cambiarse de parche también saca del chat del parche anterior
        otro = next(x for x in c.get("/api/parches", params={"tramo": "metropolitana"}, headers=auth(ana)).json()["parches"])
        unir(c, ana, otro["id"])
        assert not _chat(c, ana)["unido"]
        c.post("/api/yo/chat/unirme", headers=auth(beto))
        assert not any(m["nombre"] == "Ana" for m in _chat(c, beto)["miembros"])

        # borrar los datos borra sus mensajes
        assert c.delete("/api/yo", headers=auth(ana)).status_code == 204
        assert "¿Alguien lleva bomba de aire?" not in [m["texto"] for m in _chat(c, beto)["mensajes"]]


def test_los_simulados_conversan_con_gemini_y_su_personalidad_del_json(monkeypatch):
    sembrar(total=300, reset=True)
    monkeypatch.setattr(config, "GEMINI_API_KEY", "clave-de-prueba")
    pedidos, guion = [], []

    def gemini_falso(cuerpo):
        pedidos.append(cuerpo)
        ids = cuerpo["generationConfig"]["responseSchema"]["items"]["properties"]["id"]["enum"]
        respuesta = guion.pop(0)(ids) if guion else []
        texto = respuesta if isinstance(respuesta, str) else json.dumps(respuesta)
        return {"candidates": [{"content": {"role": "model", "parts": [{"text": texto}]}}]}

    monkeypatch.setattr(asistente, "_llamar_gemini", gemini_falso)
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        p = _parche_con_simulados(c, ana)
        unir(c, ana, p["id"])

        # al entrar a un chat vacío: charla previa entre simulados y bienvenida (un id inventado se descarta)
        guion.append(lambda ids: [{"id": ids[0], "texto": "¿Quién va el domingo?"},
                                  {"id": ids[-1], "texto": "¡Yo! Llego temprano"},
                                  {"id": "sim-9999", "texto": "no estoy en el chat"},
                                  {"id": ids[0], "texto": "¡Bienvenida, Ana!"}])
        c.post("/api/yo/chat/unirme", headers=auth(ana))
        e = _chat(c, ana)
        assert [m["texto"] for m in e["mensajes"]] == ["¿Quién va el domingo?", "¡Yo! Llego temprano", "¡Bienvenida, Ana!"]
        assert all(m["simulado"] for m in e["mensajes"])

        # la ficha de cada simulado sale del JSON: perfil y respuestas del quiz
        instrucciones = pedidos[0]["system_instruction"]["parts"][0]["text"]
        assert "Personalidad:" in instrucciones and "Termina la CicloVida" in instrucciones
        assert "Calle 9 con Carrera 37A" in instrucciones  # los datos reales del parche

        # Ana pregunta y un simulado responde; a Gemini llega su primer nombre, sin su universidad
        guion.append(lambda ids: [{"id": ids[1 % len(ids)], "texto": "Yo llevo bomba, tranqui"}])
        c.post("/api/yo/chat/mensajes", json={"texto": "¿Alguien lleva bomba de aire?"}, headers=auth(ana))
        assert _chat(c, ana)["mensajes"][-1]["texto"] == "Yo llevo bomba, tranqui"
        conversacion = pedidos[-1]["contents"][0]["parts"][0]["text"]
        assert "Ana (persona real): ¿Alguien lleva bomba de aire?" in conversacion

        # "ok" no amerita respuesta; y si Gemini devuelve algo raro, el chat no se cae
        guion.append(lambda ids: [])
        c.post("/api/yo/chat/mensajes", json={"texto": "ok"}, headers=auth(ana))
        guion.append(lambda ids: "esto no es json")
        c.post("/api/yo/chat/mensajes", json={"texto": "jaja"}, headers=auth(ana))
        assert [m["texto"] for m in _chat(c, ana)["mensajes"][-2:]] == ["ok", "jaja"]

        # si Gemini está caído al entrar alguien más, un simulado saluda con el mensaje fijo de su perfil
        def caido(_):
            raise asistente.GeminiNoDisponible("503")

        monkeypatch.setattr(asistente, "_llamar_gemini", caido)
        beto = nuevo(c, "Beto")
        unir(c, beto, p["id"])
        c.post("/api/yo/chat/unirme", headers=auth(beto))
        assert "Beto" in _chat(c, beto)["mensajes"][-1]["texto"]


def test_varios_contestan_se_responden_entre_ellos_y_charlan_si_el_chat_esta_quieto(monkeypatch):
    sembrar(total=300, reset=True)
    monkeypatch.setattr(config, "GEMINI_API_KEY", "clave-de-prueba")
    pedidos, guion = [], []

    def gemini_falso(cuerpo):
        pedidos.append(cuerpo)
        ids = cuerpo["generationConfig"]["responseSchema"]["items"]["properties"]["id"]["enum"]
        texto = json.dumps(guion.pop(0)(ids) if guion else [])
        return {"candidates": [{"content": {"role": "model", "parts": [{"text": texto}]}}]}

    monkeypatch.setattr(asistente, "_llamar_gemini", gemini_falso)
    with TestClient(app) as c, Session(engine) as s:
        ana = nuevo(c, "Ana")
        p = _parche_con_simulados(c, ana)
        unir(c, ana, p["id"])
        c.post("/api/yo/chat/unirme", headers=auth(ana))  # sin guion: bienvenida vacía
        nombre = {j.id: j.nombre for j in (s.get(Joven, i) for i in s.exec(
            select(Inscripcion.joven_id).where(Inscripcion.salida_id == p["id"])).all()) if j}

        # contestan varios y uno le responde a otro simulado; un nombre que no está en el chat se descarta
        guion.append(lambda ids: [{"id": ids[0], "texto": "Yo llevo bomba", "responde_a": "Ana"},
                                  {"id": ids[1], "texto": f"¡Y yo parches, {nombre[ids[0]]}!", "responde_a": nombre[ids[0]]},
                                  {"id": ids[2], "texto": "Todo listo entonces", "responde_a": "Pedro"}])
        c.post("/api/yo/chat/mensajes", json={"texto": "¿Alguien lleva bomba de aire?"}, headers=auth(ana))
        ultimos = _chat(c, ana)["mensajes"][-3:]
        assert [m["simulado"] for m in ultimos] == [True, True, True]
        assert ultimos[0]["responde_a"] == "Ana"
        assert ultimos[1]["responde_a"] == ultimos[0]["nombre"]  # se contestan entre ellos
        assert ultimos[2]["responde_a"] is None
        assert "de 1 a 3" in pedidos[-1]["contents"][0]["parts"][0]["text"]

        # con el chat quieto (umbral en 0 para la prueba), al consultarlo los simulados charlan entre ellos
        monkeypatch.setattr(config, "CHAT_CHARLA_SEG", 0)
        monkeypatch.setattr(config, "CHAT_CHARLA_MAX", 5)
        chat_simulado._reservas_charla.clear()
        guion.append(lambda ids: [{"id": ids[0], "texto": f"{nombre[ids[0]]}: ¿Vieron que va a hacer sol?", "responde_a": ""},
                                  {"id": ids[1], "texto": "Ojalá, así rodamos rico", "responde_a": nombre[ids[0]]}])
        antes = len(pedidos)
        _chat(c, ana)
        assert len(pedidos) == antes + 1
        tarea = pedidos[-1]["contents"][0]["parts"][0]["text"]
        assert "ENTRE USTEDES" in tarea and "Ana" in tarea  # pueden invitar a la persona real
        charla = _chat(c, ana)["mensajes"][-2:]
        assert [m["texto"] for m in charla] == ["¿Vieron que va a hacer sol?", "Ojalá, así rodamos rico"]

        # tope: con 5 mensajes simulados seguidos (3 + 2) ya no charlan más hasta que escriba alguien real
        chat_simulado._reservas_charla.clear()
        antes = len(pedidos)
        _chat(c, ana)
        assert len(pedidos) == antes
        c.post("/api/yo/chat/mensajes", json={"texto": "jaja buenísimo"}, headers=auth(ana))  # guion vacío: nadie contesta
        chat_simulado._reservas_charla.clear()
        antes = len(pedidos)
        _chat(c, ana)
        assert len(pedidos) == antes + 1  # vuelve a haber charla

        # sin Gemini no hay charla, y quien no está en el chat no la dispara
        monkeypatch.setattr(config, "GEMINI_API_KEY", "")
        chat_simulado._reservas_charla.clear()
        antes = len(pedidos)
        _chat(c, ana)
        beto = nuevo(c, "Beto")
        unir(c, beto, p["id"])
        _chat(c, beto)
        assert len(pedidos) == antes


def test_los_simulados_del_chat_son_de_ese_parche(monkeypatch):
    sembrar(total=300, reset=True)
    monkeypatch.setattr(config, "CHAT_MAX_SIMULADOS", 3)
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        p = _parche_con_simulados(c, ana)
        unir(c, ana, p["id"])
        c.post("/api/yo/chat/unirme", headers=auth(ana))
        with Session(engine) as s:
            from app import chat

            sims = chat.simulados_en_chat(s, p["id"])
            inscritos = set(s.exec(select(Inscripcion.joven_id).where(Inscripcion.salida_id == p["id"])).all())
            assert 1 <= len(sims) <= 3 and all(j.sintetico and j.id in inscritos for j in sims)
            # la ficha que ve Gemini trae el perfil y el quiz del JSON
            con_quiz = next((j for j in s.exec(select(Joven).where(Joven.sintetico == True)).all()  # noqa: E712
                             if j.quiz_respuestas), None)
            texto = chat_simulado.ficha(con_quiz, "deportista")
            assert "Deportista" in texto and "quiz" in texto and con_quiz.nombre in texto
