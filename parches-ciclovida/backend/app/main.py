from __future__ import annotations

import logging
import sys
import threading
from contextlib import asynccontextmanager
from datetime import date
from pathlib import Path
from typing import Literal

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

# La consola de Windows usa cp1252/cp850 y rompe las tildes de los logs
# (por ejemplo, el código de demostración). UTF-8 explícito y sin caerse.
for _flujo in (sys.stdout, sys.stderr):
    if hasattr(_flujo, "reconfigure"):
        _flujo.reconfigure(encoding="utf-8", errors="replace")
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlmodel import Session, select

from . import chat, chat_simulado, config, services, stats, telegram, verificacion
from .catalog import (
    ACTIVIDADES_POR_ID, FORO_IDS, FRANJA_ORDEN, MOTIVOS_IDS, QUIZ_POR_ID, RITMO_ORDEN, SEGMENTO_EDAD,
    TRAMOS_POR_ID, tramo_info, UNIVERSIDADES_POR_ID, catalogo,
)
from .privacidad import aviso
from .db import engine, get_session, init_db
from .models import Grupo, Joven, Notificacion, Reporte

log = logging.getLogger("parches")
if not log.handlers:
    # uvicorn solo configura sus propios logs: sin esto, los avisos de la app (carga inicial, bot)
    # no se ven en la consola ni en los logs de Render
    _salida = logging.StreamHandler()
    _salida.setFormatter(logging.Formatter("%(levelname)s:     %(message)s"))
    log.addHandler(_salida)
    log.setLevel(logging.INFO)
STATIC = Path(__file__).resolve().parent.parent / "static"


def _tick() -> None:
    with Session(engine) as s:
        r = services.tick(s)
        if "grupos" in r:
            log.info("Grupos del sábado: %s", r["grupos"])


def _tick_telegram() -> None:
    """El bot responde rápido: revisa sus mensajes cada pocos segundos, aparte del tick general."""
    with Session(engine) as s:
        telegram.procesar_updates(s)


def _sembrar_si_vacia() -> None:
    """Base recién creada (en Render, cada vez que el servidor reinicia): carga los simulados.
    La cuenta demo no cuenta: se crea antes, para que se pueda entrar mientras esto termina."""
    from . import seed

    with Session(engine) as s:
        if s.exec(select(Joven.id).where(Joven.id != seed.DEMO_ID)).first():
            return

    log.info("Base vacía: cargando los jóvenes simulados…")
    try:
        log.info("Datos simulados listos: %s", seed.sembrar())
    except Exception:
        log.exception("No se pudieron cargar los datos simulados")


def _asegurar_demo() -> None:
    from . import seed

    try:
        with Session(engine) as s:
            correo = seed.asegurar_demo(s)
        if correo:
            log.info("Cuenta demo lista: %s (el código de ingreso sale en pantalla)", correo)
    except Exception:
        log.exception("No se pudo crear la cuenta demo")


def _arrancar(scheduler) -> None:
    """Carga inicial (si se pidió) y después el reloj de la semana, para que el tick no corra
    mientras se siembran los domingos simulados."""
    if config.SEMBRAR_AL_INICIAR:
        _sembrar_si_vacia()
        _asegurar_demo()  # con los simulados ya cargados: su parche y sus domingos pasados
    if scheduler is None:
        return
    scheduler.add_job(_tick, "interval", minutes=5, id="tick", next_run_time=services.ahora().replace(tzinfo=config.TZ))
    if telegram.iniciar():  # valida el token, resuelve el @ del bot y registra su menú
        scheduler.add_job(_tick_telegram, "interval", seconds=5, id="telegram", max_instances=1, coalesce=True)
    scheduler.start()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    scheduler = None
    if config.SCHEDULER_ON:
        from apscheduler.schedulers.background import BackgroundScheduler

        scheduler = BackgroundScheduler(timezone=config.TZ)
    if config.SEMBRAR_AL_INICIAR:
        # la cuenta demo existe desde el primer segundo, aunque los simulados tarden en cargar
        _asegurar_demo()
        # la carga tarda: va en otro hilo para que el servidor abra el puerto de una vez (Render
        # da por caído un servicio que no responde a tiempo)
        threading.Thread(target=_arrancar, args=(scheduler,), daemon=True, name="arranque").start()
    else:
        _arrancar(scheduler)
    yield
    if scheduler and scheduler.running:
        scheduler.shutdown(wait=False)


class JSONUtf8(JSONResponse):
    """application/json con charset explícito: ningún cliente adivina la codificación."""

    media_type = "application/json; charset=utf-8"


app = FastAPI(title="Parches CicloVida", version="0.1.0", lifespan=lifespan, default_response_class=JSONUtf8)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.middleware("http")
async def sin_cache_api(request, call_next):
    """El navegador (app web) no debe cachear la API: al refrescar se ven los datos recién guardados."""
    respuesta = await call_next(request)
    if request.url.path.startswith("/api/"):
        respuesta.headers["Cache-Control"] = "no-store"
    return respuesta


# ---------------------------------------------------------------- esquemas

class Preferencias(BaseModel):
    """Solo sirven para recomendar parches: el joven elige a cuál se une."""

    comuna: int = Field(ge=1, le=22)
    tramo_id: str | None = None
    actividad: str
    ritmo: str
    franja: str | None = None

    @field_validator("tramo_id")
    @classmethod
    def _tramo(cls, v):
        if v is not None and v not in TRAMOS_POR_ID:
            raise ValueError("Tramo desconocido")
        return v

    @field_validator("actividad")
    @classmethod
    def _act(cls, v):
        if v not in ACTIVIDADES_POR_ID:
            raise ValueError("Actividad desconocida")
        return v

    @field_validator("ritmo")
    @classmethod
    def _ritmo(cls, v):
        if v not in RITMO_ORDEN:
            raise ValueError("Ritmo desconocido")
        return v

    @field_validator("franja")
    @classmethod
    def _franja(cls, v):
        if v is not None and v not in FRANJA_ORDEN:
            raise ValueError("Franja desconocida")
        return v


class CorreoIn(BaseModel):
    correo: str = Field(max_length=120)
    para: Literal["registro", "ingreso"] = "registro"


class CredencialesIn(BaseModel):
    """Volver a entrar: el mismo correo institucional y un código nuevo."""

    correo: str = Field(max_length=120)
    codigo: str = Field(min_length=6, max_length=6)


class Registro(Preferencias):
    correo: str = Field(max_length=120)  # institucional; no se guarda, solo su huella
    codigo: str = Field(min_length=6, max_length=6)
    nombre: str = Field(min_length=2, max_length=40)
    rango_edad: str
    acepta_datos: bool
    declara_mayor: bool = False  # casilla obligatoria para 18+: queda constancia de que se preguntó
    permiso_acudiente: bool = False
    acudiente_nombre: str | None = Field(default=None, max_length=80)
    primera_vez: bool | None = None  # ¿es su primera vez en la CicloVida? Opcional

    @field_validator("nombre")
    @classmethod
    def _nombre(cls, v):
        return v.strip().split()[0].capitalize()  # solo el nombre de pila

    @field_validator("correo")
    @classmethod
    def _correo(cls, v):
        verificacion.universidad_valida(v)
        return verificacion.normalizar(v)

    @model_validator(mode="after")
    def _consentimientos(self):
        if self.rango_edad not in SEGMENTO_EDAD:
            raise ValueError("Rango de edad desconocido")
        if not self.acepta_datos:
            raise ValueError("Necesitamos tu autorización de tratamiento de datos")
        if SEGMENTO_EDAD[self.rango_edad] == "menor":
            if not config.PERMITIR_MENORES:
                raise ValueError("Por ahora el piloto es solo para jóvenes de 18 a 28 años")
            if not self.permiso_acudiente or len((self.acudiente_nombre or "").strip()) < 3:
                raise ValueError("Si tienes entre 14 y 17 años necesitamos la autorización y el nombre de tu acudiente")
            self.declara_mayor = False  # un menor nunca declara mayoría de edad
        else:
            self.acudiente_nombre = None
            if not self.declara_mayor:
                raise ValueError("Necesitamos que confirmes que tienes 18 años o más")
        return self


class Cambio(BaseModel):
    comuna: int | None = Field(default=None, ge=1, le=22)
    tramo_id: str | None = None
    actividad: str | None = None
    ritmo: str | None = None
    franja: str | None = None
    pausar_esta_semana: bool | None = None


class Respuesta(BaseModel):
    va: bool


class Union(BaseModel):
    parche_id: int


class EncuestaIn(BaseModel):
    asistio: bool
    volveria: bool
    bienestar: int | None = Field(default=None, ge=1, le=5)  # opcional: puede ser dato sensible


class QuizIn(BaseModel):
    """Respuestas del quiz "Tu estilo de parche": {pregunta: opción}. Opcional y sin etiquetas."""

    respuestas: dict[int, str]

    @field_validator("respuestas")
    @classmethod
    def _completas(cls, v):
        for p in QUIZ_POR_ID.values():
            opcion = v.get(p["id"])
            if opcion is None:
                raise ValueError("Falta responder alguna pregunta")
            if opcion not in {o["id"] for o in p["opciones"]}:
                raise ValueError("Hay una respuesta que no es una opción válida")
        return v


class ChatIn(BaseModel):
    texto: str = Field(min_length=1, max_length=500)


class ForoIn(BaseModel):
    categoria: str
    texto: str = Field(min_length=2, max_length=500)

    @field_validator("categoria")
    @classmethod
    def _categoria(cls, v):
        if v not in FORO_IDS:
            raise ValueError("Categoría desconocida")
        return v


class ReporteIn(BaseModel):
    grupo_id: int
    motivo: str
    ref: int | None = None  # integrante del parche; vacío = sobre el grupo en general
    detalle: str = Field(default="", max_length=500)

    @field_validator("motivo")
    @classmethod
    def _motivo(cls, v):
        if v not in MOTIVOS_IDS:
            raise ValueError("Motivo desconocido")
        return v


# ---------------------------------------------------------------- dependencias

def joven_actual(authorization: str = Header(default=""), session: Session = Depends(get_session)) -> Joven:
    token = authorization.removeprefix("Bearer ").strip()
    joven = session.exec(select(Joven).where(Joven.token == token)).first() if token else None
    if not joven:
        raise HTTPException(401, "Sesión no válida")
    return joven


def admin(x_admin_key: str = Header(default="")) -> None:
    if x_admin_key != config.ADMIN_KEY:
        raise HTTPException(403, "Clave de administración incorrecta")


def perfil(j: Joven) -> dict:
    return {
        "id": j.id, "nombre": j.nombre, "rango_edad": j.rango_edad, "comuna": j.comuna,
        "universidad": UNIVERSIDADES_POR_ID[j.universidad]["nombre"],
        "tramo_id": j.tramo_id, "actividad": j.actividad, "ritmo": j.ritmo, "franja": j.franja,
        "pausa_fecha": str(j.pausa_fecha) if j.pausa_fecha else None,
        # solo el hecho de haberlo respondido: las respuestas no salen del servidor
        "quiz_respondido": bool(j.quiz),
    }


# ---------------------------------------------------------------- app móvil

@app.get("/health")
def health():
    return {"ok": True}


@app.get("/api/catalogo")
def get_catalogo(session: Session = Depends(get_session)):
    data = catalogo()
    data["proxima_jornada"] = str(services.jornada_abierta(session).fecha)
    return data


@app.get("/api/aviso-privacidad")
def aviso_privacidad():
    return aviso()


@app.post("/api/verificacion")
def pedir_codigo(body: CorreoIn, session: Session = Depends(get_session)):
    """Envía un código de 6 dígitos al correo institucional. Sin servidor de correo (demo), lo devuelve."""
    try:
        return verificacion.solicitar(session, body.correo, services.ahora(), para=body.para)
    except verificacion.CorreoInvalido as e:
        raise HTTPException(422, str(e))
    except LookupError as e:
        raise HTTPException(409, str(e))
    except RuntimeError as e:
        raise HTTPException(503, str(e))


@app.post("/api/jovenes", status_code=201)
def registrar(body: Registro, session: Session = Depends(get_session)):
    try:
        uni, huella = verificacion.comprobar(session, body.correo, body.codigo, services.ahora())
    except verificacion.CorreoInvalido as e:
        raise HTTPException(422, str(e))
    if session.exec(select(Joven.id).where(Joven.correo_hash == huella)).first():
        raise HTTPException(409, "Ese correo ya tiene una cuenta")
    joven = Joven(
        **body.model_dump(exclude={"correo", "codigo"}), correo_hash=huella, universidad=uni["id"],
        autorizacion_version=config.AVISO_VERSION, autorizacion_en=services.ahora(),
        declara_mayor_en=services.ahora() if body.declara_mayor else None,  # constancia con fecha
    )
    session.add(joven)
    session.commit()
    session.refresh(joven)
    return {"token": joven.token, "joven": perfil(joven)}


@app.post("/api/sesiones")
def ingresar(body: CredencialesIn, session: Session = Depends(get_session)):
    """Volver a entrar con el mismo correo: código nuevo y de vuelta la sesión de siempre."""
    try:
        _, h = verificacion.comprobar(session, verificacion.normalizar(body.correo), body.codigo, services.ahora())
    except verificacion.CorreoInvalido as e:
        raise HTTPException(422, str(e))
    joven = session.exec(select(Joven).where(Joven.correo_hash == h)).first()
    if not joven:
        raise HTTPException(404, "Ese correo aún no tiene cuenta. Crea tu perfil.")
    session.commit()  # consume el código usado
    return {"token": joven.token, "joven": perfil(joven)}


@app.get("/api/yo")
def yo(joven: Joven = Depends(joven_actual)):
    return perfil(joven)


@app.patch("/api/yo")
def cambiar(body: Cambio, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    # exclude_unset (y no exclude_none): un campo enviado como null se guarda como null.
    # Así "estación: Cualquiera" o "hora: Cualquiera" sí quedan guardados al actualizar.
    datos = body.model_dump(exclude_unset=True)
    pausa = datos.pop("pausar_esta_semana", None)
    for k in ("comuna", "actividad", "ritmo"):  # estos nunca pueden quedar vacíos
        if datos.get(k) is None:
            datos.pop(k, None)
    if datos:
        Preferencias(**{**perfil(joven), **datos})  # valida
    j = services.jornada_abierta(session)
    for k, v in datos.items():
        setattr(joven, k, v)
    if pausa is not None:
        joven.pausa_fecha = j.fecha if pausa else None
    session.add(joven)
    session.commit()
    if pausa:
        services.quitar_de_la_jornada(session, joven.id, j.fecha)
        session.commit()
    session.refresh(joven)
    return perfil(joven)


@app.delete("/api/yo", status_code=204)
def borrar(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    services.borrar_joven(session, session.merge(joven))


@app.get("/api/yo/parche")
def mi_parche(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    return services.estado_para(session, joven)


@app.post("/api/yo/quiz")
def responder_quiz(body: QuizIn, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Guarda el quiz "Tu estilo de parche". No devuelve puntajes ni etiquetas: se usa por dentro."""
    services.guardar_quiz(session, joven, body.respuestas)
    return {"ok": True, "mensaje": "¡Listo! Usaremos tus gustos para armarte un parche más afín."}


@app.get("/api/yo/historial")
def mi_historial(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Los domingos pasados: a qué parche fue y con quién."""
    return services.historial_para(session, joven)


@app.get("/api/parches")
def parches(
    tramo: str | None = None,
    franja: str | None = None,
    actividad: str | None = None,
    joven: Joven = Depends(joven_actual),
    session: Session = Depends(get_session),
):
    """Los parches que generó el sistema para el próximo domingo, para elegir uno."""
    return services.listar_parches(session, joven, tramo=tramo, franja=franja, actividad=actividad)


@app.post("/api/yo/parche")
def unirme(body: Union, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        services.unirse(session, joven, body.parche_id)
    except LookupError as e:
        raise HTTPException(409, str(e))
    return services.estado_para(session, joven)


@app.delete("/api/yo/parche")
def salirme(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    services.salir(session, joven)
    return services.estado_para(session, joven)


@app.post("/api/yo/match")
def buscar_match(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Emparejamiento automático: une al joven al parche con gente y sus mismas características.

    Si no existe, lo deja en lista de espera; el sistema reintenta y le avisa al encontrarlo.
    """
    services.emparejar_automatico(session, joven)
    return services.estado_para(session, joven)


@app.delete("/api/yo/espera")
def cancelar_espera(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    services.cancelar_espera(session, joven)
    return services.estado_para(session, joven)


@app.get("/api/yo/notificaciones")
def notificaciones(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    filas = session.exec(
        select(Notificacion).where(Notificacion.joven_id == joven.id).order_by(Notificacion.creado_en.desc()).limit(20)
    ).all()
    return [{"id": n.id, "titulo": n.titulo, "cuerpo": n.cuerpo, "leida": n.leida, "creado_en": n.creado_en.isoformat()}
            for n in filas]


@app.post("/api/yo/notificaciones/leidas")
def marcar_leidas(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    for n in session.exec(select(Notificacion).where(Notificacion.joven_id == joven.id, Notificacion.leida == False)).all():  # noqa: E712
        n.leida = True
        session.add(n)
    session.commit()
    return {"ok": True}


@app.delete("/api/yo/telegram")
def desconectar_telegram(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Suelta el chat de Telegram de esta cuenta (por ejemplo, para conectarlo a otra en la demo)."""
    telegram.desconectar(session, joven)
    return {"ok": True}


@app.get("/api/yo/telegram")
def telegram_estado(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Estado del vínculo con el bot y el enlace t.me para crearlo. Sin bot configurado, se apaga."""
    # hace falta el token Y el nombre del bot: sin nombre no se puede armar el enlace t.me
    if not telegram.disponible() or not config.TELEGRAM_BOT:
        return {"disponible": False, "vinculado": False, "enlace": None, "bot": None}
    telegram.procesar_updates(session)  # así el vínculo se refleja apenas la app refresca
    session.refresh(joven)
    if joven.telegram_chat_id:
        return {"disponible": True, "vinculado": True, "enlace": None, "bot": config.TELEGRAM_BOT}
    if not joven.telegram_codigo:
        from secrets import token_hex

        joven.telegram_codigo = token_hex(6)
        session.add(joven)
        session.commit()
    return {
        "disponible": True, "vinculado": False, "bot": config.TELEGRAM_BOT,
        "enlace": telegram.enlace_para(joven.telegram_codigo),  # app de Telegram (celular/escritorio)
        "enlace_web": telegram.enlace_web_para(joven.telegram_codigo),  # Telegram Web, conserva el código
        "codigo": joven.telegram_codigo,  # respaldo: enviarlo a mano como "/start <código>"
    }


# ---------------------------------------------------------------- chat del parche (opcional)

@app.get("/api/yo/chat")
def mi_chat(tareas: BackgroundTasks, despues_de: int | None = None, joven: Joven = Depends(joven_actual),
            session: Session = Depends(get_session)):
    """El chat de su parche. Sin unirse, solo cuántos hay (ni nombres ni mensajes).
    Con `despues_de`, solo los mensajes nuevos (para consultar cada pocos segundos).

    Mientras alguien real tiene el chat abierto y está quieto un rato, los simulados charlan entre ellos."""
    info = chat.estado(session, joven, despues_de)
    if info.get("unido") and not joven.sintetico and chat_simulado.reservar_charla(session, info["parche"]["id"]):
        tareas.add_task(chat_simulado.generar, info["parche"]["id"], "charla")
    return info


@app.post("/api/yo/chat/unirme")
def unirme_al_chat(tareas: BackgroundTasks, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    """Entrar al chat es opcional. En la demo, los simulados del parche le dan la bienvenida (Gemini)."""
    try:
        salida, nuevo = chat.unirse(session, joven)
    except LookupError as e:
        raise HTTPException(409, str(e))
    if nuevo:
        tareas.add_task(chat_simulado.generar, salida.id, "bienvenida", joven.nombre)
    return chat.estado(session, joven)


@app.delete("/api/yo/chat")
def salir_del_chat(joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    chat.salir(session, joven)
    return chat.estado(session, joven)


@app.post("/api/yo/chat/mensajes", status_code=201)
def escribir_en_el_chat(body: ChatIn, tareas: BackgroundTasks, joven: Joven = Depends(joven_actual),
                        session: Session = Depends(get_session)):
    try:
        m = chat.publicar(session, joven, body.texto)
    except LookupError as e:
        raise HTTPException(409, str(e))
    tareas.add_task(chat_simulado.generar, m.salida_id, "respuesta")
    return chat.mensaje_json(m, joven.id)


# ---------------------------------------------------------------- foro comunal

@app.get("/api/foro")
def foro(categoria: str | None = None, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    if categoria is not None and categoria not in FORO_IDS:
        raise HTTPException(422, "Categoría desconocida")
    return services.foro_lista(session, joven, categoria)


@app.post("/api/foro", status_code=201)
def foro_publicar(body: ForoIn, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        m = services.foro_publicar(session, joven, body.categoria, body.texto)
    except LookupError as e:
        raise HTTPException(409, str(e))
    return {"id": m.id, "nombre": m.nombre, "universidad": m.universidad, "categoria": m.categoria,
            "texto": m.texto, "creado_en": m.creado_en.isoformat(), "es_mio": True}


@app.delete("/api/foro/{mensaje_id}", status_code=204)
def foro_borrar(mensaje_id: int, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        services.foro_borrar(session, joven, mensaje_id)
    except LookupError as e:
        raise HTTPException(409, str(e))


@app.post("/api/yo/parche/respuesta")
def responder(body: Respuesta, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        services.responder(session, joven, body.va)
    except LookupError as e:
        raise HTTPException(409, str(e))
    return services.estado_para(session, joven)


@app.post("/api/yo/encuesta")
def encuesta(body: EncuestaIn, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        services.guardar_encuesta(session, joven, body.asistio, body.volveria, body.bienestar)
    except LookupError as e:
        raise HTTPException(409, str(e))
    return services.estado_para(session, joven)


@app.post("/api/yo/reportes", status_code=201)
def reportar(body: ReporteIn, joven: Joven = Depends(joven_actual), session: Session = Depends(get_session)):
    try:
        services.reportar(session, joven, body.grupo_id, body.motivo, body.detalle, body.ref)
    except LookupError as e:
        raise HTTPException(409, str(e))
    return {"ok": True, "mensaje": "Recibimos tu reporte. Lo revisa una persona del equipo."}


# ---------------------------------------------------------------- administración (demo y operación)

@app.post("/api/admin/armar-grupos", dependencies=[Depends(admin)])
def admin_armar_grupos(session: Session = Depends(get_session)):
    """Para la demo: adelanta lo del sábado 5:00 p. m. (grupos por k-means dentro de cada parche)."""
    try:
        return services.armar_grupos(session, services.jornada_abierta(session).fecha)
    except ValueError as e:
        raise HTTPException(409, str(e))


@app.post("/api/admin/finalizar", dependencies=[Depends(admin)])
def admin_finalizar(session: Session = Depends(get_session)):
    """Para la demo: da por terminada la jornada abierta y abre la encuesta."""
    j = services.jornada_abierta(session)
    j.estado = "finalizada"
    j.finalizada_en = services.ahora()
    session.add(j)
    session.commit()
    return {"finalizada": str(j.fecha), "siguiente": str(services.jornada_abierta(session).fecha)}


@app.get("/api/admin/emparejamiento", dependencies=[Depends(admin)])
def admin_emparejamiento(fecha: date | None = Query(default=None), session: Session = Depends(get_session)):
    """Cada grupo con sus integrantes y por qué quedaron juntos, más el efecto del quiz.

    Del quiz y del perfil solo salen los jóvenes simulados; de las personas reales, ni el nombre ni
    sus respuestas. No es para el tablero de la Secretaría.
    """
    from . import reporte

    r = reporte.generar(session, fecha)
    if r is None:
        raise HTTPException(404, "Todavía no hay grupos armados para ese domingo")
    return r


@app.get("/api/admin/telegram", dependencies=[Depends(admin)])
def admin_telegram(session: Session = Depends(get_session)):
    """Para verificar el anclaje: si el bot está vivo y cuántas cuentas ya se vincularon."""
    vinculados = len(session.exec(select(Joven.id).where(Joven.telegram_chat_id != None)).all())  # noqa: E711
    from . import asistente

    conversacional = {"activo": asistente.disponible(), "modelo": config.GEMINI_MODEL if asistente.disponible() else None}
    if not telegram.disponible():
        return {"configurado": False, "bot": None, "vinculados": vinculados, "conversacional": conversacional,
                "falta": "Pon TELEGRAM_TOKEN en backend/.env (ver .env.example) y reinicia el servidor"}
    falta = None if config.TELEGRAM_BOT else "El token no respondió a getMe: revisa que sea el de @BotFather"
    otra = telegram.otra_instancia_reciente()
    if otra:
        falta = ("Otro programa está leyendo los mensajes con este mismo token: deja un solo backend con él "
                 "o genera un token nuevo con /revoke en @BotFather")
    return {"configurado": True, "bot": config.TELEGRAM_BOT or None, "vinculados": vinculados,
            "conversacional": conversacional, "otra_instancia_detectada": otra, "falta": falta}
def admin_jornada(session: Session = Depends(get_session)):
    j = services.jornada_abierta(session)
    return {**services.resumen_jornada(session, j.fecha), "estado": j.estado}


@app.get("/api/admin/reportes", dependencies=[Depends(admin)])
def admin_reportes(pendientes: bool = True, session: Session = Depends(get_session)):
    """Cola de moderación. Es lo único que muestra personas, y solo con la clave de administración."""
    q = select(Reporte).order_by(Reporte.creado_en.desc())
    if pendientes:
        q = q.where(Reporte.revisado == False)  # noqa: E712
    salida = []
    for r in session.exec(q).all():
        reportado = session.get(Joven, r.reportado_id) if r.reportado_id else None
        grupo = session.get(Grupo, r.grupo_id) if r.grupo_id else None
        salida.append({
            "id": r.id, "fecha": str(r.jornada_fecha), "motivo": r.motivo, "detalle": r.detalle,
            "parche": grupo.nombre if grupo else None,
            "tramo": tramo_info(grupo.tramo_id)["nombre"] if grupo else None,
            "reportado": {"id": reportado.id, "nombre": reportado.nombre, "suspendido": reportado.suspendido} if reportado else None,
            "creado_en": r.creado_en.isoformat(),
        })
    return salida


@app.post("/api/admin/reportes/{reporte_id}/revisar", dependencies=[Depends(admin)])
def admin_revisar(reporte_id: int, reactivar: bool = False, session: Session = Depends(get_session)):
    r = session.get(Reporte, reporte_id)
    if not r:
        raise HTTPException(404, "No existe ese reporte")
    r.revisado = True
    session.add(r)
    if reactivar and r.reportado_id:
        j = session.get(Joven, r.reportado_id)
        if j:
            j.suspendido = False
            session.add(j)
    session.commit()
    return {"ok": True}


# ---------------------------------------------------------------- tablero

@app.get("/api/tablero/jornadas")
def tablero_jornadas(session: Session = Depends(get_session)):
    return stats.jornadas(session)


@app.get("/api/tablero/resumen")
def tablero_resumen(fecha: date | None = Query(default=None), session: Session = Depends(get_session)):
    if fecha is None:
        lista = stats.jornadas(session)
        cerradas = [j for j in lista if j["estado"] == "finalizada"]
        fecha = date.fromisoformat((cerradas or lista)[0]["fecha"]) if lista else services.jornada_abierta(session).fecha
    return stats.resumen(session, fecha)


@app.get("/")
def raiz():
    return RedirectResponse("/tablero/")


@app.get("/api/salud")
def salud():
    """Para el health check de Render: responde apenas el servidor está arriba."""
    return {"ok": True}


app.mount("/tablero", StaticFiles(directory=STATIC / "tablero", html=True), name="tablero")
