"""Lo que necesita el despliegue en Vercel: cuenta demo sin arranque, webhook de Telegram, cron y pocas consultas."""

from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlmodel import Session, select

from app import config, seed, telegram
from app.db import engine
from app.main import app
from app.models import Joven
from test_api import ADMIN, auth, nuevo, parche, setup_function, unir  # noqa: F401


def test_cuenta_demo_se_crea_sola_al_pedir_su_codigo():
    """En Vercel no hay arranque que cree la cuenta demo: tiene que aparecer la primera vez que se pide."""
    with TestClient(app) as c:
        with Session(engine) as s:
            assert s.get(Joven, seed.DEMO_ID) is None
        r = c.post("/api/verificacion", json={"correo": seed.DEMO_CORREO, "para": "ingreso"})
        assert r.status_code == 200, r.text
        r = c.post("/api/sesiones", json={"correo": seed.DEMO_CORREO, "codigo": r.json()["codigo_demo"]})
        assert r.status_code == 200, r.text
        assert r.json()["joven"]["id"] == seed.DEMO_ID
        # nadie puede registrarla como cuenta nueva
        r = c.post("/api/verificacion", json={"correo": seed.DEMO_CORREO, "para": "registro"})
        assert r.status_code == 409


def test_cuenta_demo_se_repara_si_la_base_viene_de_otro_secreto():
    """Si la base se sembró con otro SECRETO, la huella del correo no coincide y la demo "no tenía cuenta"."""
    with TestClient(app) as c:
        with Session(engine) as s:
            seed.asegurar_demo(s)
            demo = s.get(Joven, seed.DEMO_ID)
            demo.correo_hash = "huella-de-otro-secreto"
            s.add(demo)
            s.commit()
        r = c.post("/api/verificacion", json={"correo": seed.DEMO_CORREO, "para": "ingreso"})
        assert r.status_code == 200, r.text


def test_nombre_del_bot_sin_arroba():
    """Con @, t.me/@bot abre la portada de Telegram y no el bot."""
    assert config.nombre_bot("@Parcherito_bot ") == "Parcherito_bot"
    assert config.nombre_bot("Parcherito_bot") == "Parcherito_bot"


def test_webhook_de_telegram_exige_el_secreto_y_atiende_el_mensaje(monkeypatch):
    enviados: list[tuple[str, str]] = []
    monkeypatch.setattr(config, "TELEGRAM_TOKEN", "123:abc")
    monkeypatch.setattr(config, "TELEGRAM_BOT", "Parcherito_bot")
    monkeypatch.setattr(config, "TELEGRAM_WEBHOOK_SECRET", "secreto-de-prueba")
    monkeypatch.setattr(telegram, "_api", lambda metodo, **_: None)  # sin red
    monkeypatch.setattr(telegram, "enviar", lambda chat, texto, botones=None: enviados.append((chat, texto)))
    with TestClient(app) as c:
        tok = nuevo(c, "Ana")
        codigo = c.get("/api/yo/telegram", headers=auth(tok)).json()["codigo"]
        update = {"update_id": 1, "message": {"chat": {"id": 555}, "text": f"/start {codigo}"}}

        assert c.post("/api/telegram/webhook", json=update).status_code == 401
        r = c.post("/api/telegram/webhook", json=update,
                   headers={"X-Telegram-Bot-Api-Secret-Token": "otro"})
        assert r.status_code == 401

        r = c.post("/api/telegram/webhook", json=update,
                   headers={"X-Telegram-Bot-Api-Secret-Token": "secreto-de-prueba"})
        assert r.status_code == 200, r.text
        assert "Ana" in enviados[0][1]
        assert c.get("/api/yo/telegram", headers=auth(tok)).json()["vinculado"] is True


def test_en_modo_webhook_no_se_hace_polling(monkeypatch):
    """Con webhook, getUpdates responde "Conflict": el backend no debe pedirlos."""
    llamadas: list[str] = []
    monkeypatch.setattr(config, "TELEGRAM_TOKEN", "123:abc")
    monkeypatch.setattr(config, "TELEGRAM_MODO", "webhook")
    monkeypatch.setattr(telegram, "_api", lambda metodo, **_: llamadas.append(metodo))
    with Session(engine) as s:
        telegram.procesar_updates(s)
    assert "getUpdates" not in llamadas


def test_registrar_webhook_y_diagnostico(monkeypatch):
    llamadas: dict[str, dict] = {}
    respuestas = {"getMe": {"username": "Parcherito_bot"}, "setWebhook": True, "setMyCommands": True,
                  "getWebhookInfo": {"url": "https://parches.example/api/telegram/webhook", "pending_update_count": 0}}

    def api(metodo, **params):
        llamadas[metodo] = params
        return respuestas.get(metodo)

    monkeypatch.setattr(config, "TELEGRAM_TOKEN", "123:abc")
    monkeypatch.setattr(config, "TELEGRAM_BOT", "@Parcherito_bot")
    monkeypatch.setattr(config, "TELEGRAM_MODO", "webhook")
    monkeypatch.setattr(config, "TELEGRAM_WEBHOOK_SECRET", "secreto-de-prueba")
    monkeypatch.setattr(config, "URL_PUBLICA", "https://parches.example")
    monkeypatch.setattr(telegram, "_api", api)
    with TestClient(app) as c:
        assert c.post("/api/admin/telegram/webhook").status_code == 403
        r = c.post("/api/admin/telegram/webhook", headers=ADMIN)
        assert r.status_code == 200, r.text
        assert llamadas["setWebhook"]["url"] == "https://parches.example/api/telegram/webhook"
        assert llamadas["setWebhook"]["secret_token"] == "secreto-de-prueba"
        assert r.json()["bot"] == "Parcherito_bot"

        info = c.get("/api/admin/telegram", headers=ADMIN).json()
        assert info["modo"] == "webhook" and info["falta"] is None
        respuestas["getWebhookInfo"] = {"url": "", "pending_update_count": 4}
        info = c.get("/api/admin/telegram", headers=ADMIN).json()
        assert "Falta registrar el webhook" in info["falta"] and info["webhook"]["pendientes"] == 4


def _bot_en_webhook(monkeypatch, respuestas: dict) -> list[tuple[str, dict]]:
    """Bot en modo webhook (Vercel), sin red: devuelve las llamadas que se le hacen a Telegram."""
    llamadas: list[tuple[str, dict]] = []

    def api(metodo, **params):
        llamadas.append((metodo, params))
        return respuestas.get(metodo)

    monkeypatch.setattr(config, "TELEGRAM_TOKEN", "123:abc")
    monkeypatch.setattr(config, "TELEGRAM_BOT", "Parcherito_bot")
    monkeypatch.setattr(config, "TELEGRAM_MODO", "webhook")
    monkeypatch.setattr(config, "TELEGRAM_WEBHOOK_SECRET", "secreto-de-prueba")
    monkeypatch.setattr(config, "URL_PUBLICA", "https://parches.example")
    monkeypatch.setattr(telegram, "_webhook_revisado", False)  # instancia recién arrancada
    monkeypatch.setattr(telegram, "_webhook_rehecho", 0.0)
    monkeypatch.setattr(telegram, "_api", api)
    return llamadas


def test_webhook_sin_registrar_se_registra_al_conectar_telegram(monkeypatch):
    """Sin el paso manual del curl, el bot no recibía nada: al abrir «Conectar Telegram» se registra solo."""
    respuestas = {"getMe": {"username": "Parcherito_bot"}, "setWebhook": True, "setMyCommands": True,
                  "getWebhookInfo": {"url": "", "pending_update_count": 2}}
    llamadas = _bot_en_webhook(monkeypatch, respuestas)
    with TestClient(app) as c:
        tok = nuevo(c, "Ana")
        assert c.get("/api/yo/telegram", headers=auth(tok)).json()["disponible"] is True
        registro = [p for m, p in llamadas if m == "setWebhook"]
        assert registro == [{"url": "https://parches.example/api/telegram/webhook",
                             "secret_token": "secreto-de-prueba", "allowed_updates": ["message", "callback_query"]}]

        # una vez por instancia: refrescar la pantalla no vuelve a preguntarle a Telegram
        llamadas.clear()
        c.get("/api/yo/telegram", headers=auth(tok))
        assert [m for m, _ in llamadas] == []


def test_webhook_ya_registrado_no_se_toca(monkeypatch):
    respuestas = {"getWebhookInfo": {"url": "https://parches.example/api/telegram/webhook", "pending_update_count": 0}}
    llamadas = _bot_en_webhook(monkeypatch, respuestas)
    with TestClient(app) as c:
        tok = nuevo(c, "Ana")
        c.get("/api/yo/telegram", headers=auth(tok))
    assert [m for m, _ in llamadas] == ["getWebhookInfo"]


def test_mensaje_con_otro_secreto_vuelve_a_registrar_el_webhook(monkeypatch):
    """Un webhook registrado sin secreto (como antes) hacía que cada mensaje rebotara con 401."""
    respuestas = {"getMe": {"username": "Parcherito_bot"}, "setWebhook": True, "setMyCommands": True,
                  "getWebhookInfo": {"url": "https://parches.example/api/telegram/webhook", "pending_update_count": 1}}
    llamadas = _bot_en_webhook(monkeypatch, respuestas)
    update = {"update_id": 1, "message": {"chat": {"id": 555}, "text": "/ayuda"}}
    with TestClient(app) as c:
        # la URL coincide, así que la revisión normal no lo detecta: el secreto no se ve en getWebhookInfo
        c.get("/api/yo/telegram", headers=auth(nuevo(c, "Ana")))
        assert "setWebhook" not in [m for m, _ in llamadas]

        assert c.post("/api/telegram/webhook", json=update).status_code == 401
        assert [p["secret_token"] for m, p in llamadas if m == "setWebhook"] == ["secreto-de-prueba"]

        # alguien insistiendo con otro secreto no lo hace registrar en cada llamada
        llamadas.clear()
        assert c.post("/api/telegram/webhook", json=update).status_code == 401
        assert [m for m, _ in llamadas] == []


def test_diagnostico_avisa_si_telegram_no_logra_entregar(monkeypatch):
    respuestas = {"getWebhookInfo": {"url": "https://parches.example/api/telegram/webhook", "pending_update_count": 3,
                                     "last_error_message": "Wrong response from the webhook: 401 Unauthorized"}}
    _bot_en_webhook(monkeypatch, respuestas)
    with TestClient(app) as c:
        info = c.get("/api/admin/telegram", headers=ADMIN).json()
    assert "401 Unauthorized" in info["falta"] and info["webhook"]["pendientes"] == 3


def test_el_domingo_siguiente_tambien_arranca_con_simulados(monkeypatch):
    """En Neon se siembra una sola vez: pasado ese domingo, el siguiente salía vacío y el mapa en ceros."""
    from app import services
    from app.models import Inscripcion

    monkeypatch.setattr(services, "_simulados_revisados", set())
    seed.sembrar(total=240, reset=True)
    with TestClient(app) as c:
        tok = nuevo(c, "Ana")

        def gente_en_el_mapa():
            return sum(p["inscritos"] for p in c.get("/api/parches", headers=auth(tok)).json()["parches"])

        assert gente_en_el_mapa() > 60
        siguiente = c.post("/api/admin/finalizar", headers=ADMIN).json()["siguiente"]
        assert 80 < gente_en_el_mapa() < 160  # ~la mitad de los 240

        # idempotente: llamarlo otra vez (otra instancia de Vercel) no duplica a nadie
        with Session(engine) as s:
            assert services.poblar_con_simulados(s, date.fromisoformat(siguiente)) == 0
            ids = s.exec(select(Inscripcion.joven_id).where(Inscripcion.jornada_fecha == date.fromisoformat(siguiente))).all()
            assert len(ids) == len(set(ids))


def test_cron_de_vercel_llama_con_get_y_secreto(monkeypatch):
    monkeypatch.setenv("CRON_SECRET", "s3cr3t")
    with TestClient(app) as c:
        assert c.get("/api/cron").status_code == 401
        r = c.get("/api/cron", headers={"Authorization": "Bearer s3cr3t"})
        assert r.status_code == 200 and r.json()["ok"]
        assert c.post("/api/cron", headers={"Authorization": "Bearer s3cr3t"}).status_code == 200


def test_mi_parche_no_hace_una_consulta_por_persona():
    """En Neon cada consulta es un viaje por la red: con una por inscrito, "Mi parche" pasaba de 10 s."""
    with TestClient(app) as c:
        toks = [nuevo(c, f"Persona{i}") for i in range(25)]
        p = parche(c, toks[0])
        for t in toks:
            unir(c, t, p["id"])
        consultas = []

        def contar(*_args, **_kw):
            consultas.append(1)

        event.listen(engine, "before_cursor_execute", contar)
        try:
            r = c.get("/api/yo/parche", headers=auth(toks[0]))
        finally:
            event.remove(engine, "before_cursor_execute", contar)
        assert r.status_code == 200 and r.json()["salida"]["inscritos"] == 25
        assert len(consultas) < 25, len(consultas)
        with Session(engine) as s:
            assert len(s.exec(select(Joven)).all()) == 25
