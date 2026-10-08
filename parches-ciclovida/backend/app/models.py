from datetime import date, datetime
from secrets import token_urlsafe
from uuid import uuid4

from sqlalchemy import JSON, DateTime
from sqlmodel import Field, SQLModel


# Todas las horas se guardan sin zona, en hora de Cali (UTC-5, sin horario de verano).
def _ahora() -> datetime:
    from .config import TZ

    return datetime.now(TZ).replace(tzinfo=None)


class Joven(SQLModel, table=True):
    id: str = Field(default_factory=lambda: uuid4().hex, primary_key=True)
    token: str = Field(default_factory=lambda: token_urlsafe(24), index=True, unique=True)
    nombre: str = Field(max_length=40)  # solo el nombre de pila: es lo único que ve el grupo
    # Estudiante verificado: del correo institucional solo guardamos su huella HMAC y la universidad.
    correo_hash: str = Field(index=True, unique=True)
    universidad: str = Field(index=True)
    rango_edad: str
    comuna: int = Field(index=True)
    # Preferencias: solo sirven para recomendar parches, el joven elige cuál.
    tramo_id: str | None = Field(default=None, index=True)
    actividad: str
    ritmo: str
    franja: str | None = None
    acepta_datos: bool
    autorizacion_version: str = ""  # versión del aviso de privacidad aceptado
    autorizacion_en: datetime | None = Field(default=None, sa_type=DateTime)  # prueba de la autorización
    # Constancia de la declaración de mayoría de edad: casilla obligatoria en el registro
    # para quien dice tener 18 o más. Se guarda que se preguntó y cuándo se aceptó.
    declara_mayor: bool = False
    declara_mayor_en: datetime | None = Field(default=None, sa_type=DateTime)
    permiso_acudiente: bool = False
    acudiente_nombre: str | None = Field(default=None, max_length=80)
    suspendido: bool = False  # por reportes, hasta revisión
    pausa_fecha: date | None = None  # "esta semana no voy"
    # Telegram (opcional): para avisarle cuando su espera encuentra parche.
    telegram_chat_id: str | None = Field(default=None, index=True)
    telegram_codigo: str | None = Field(default=None, index=True)
    # Quiz "Tu estilo de parche" (opcional). Criterio secundario para armar grupos afines; quien no
    # lo responde queda neutro. Nunca se muestra a nadie ni llega al tablero.
    #   quiz_respuestas: lo que respondió, tal cual, como JSON: {"1": "a", "2": "c", ...}
    #   quiz: el vector que usa k-means, 5 valores de 0 a 1 como "1,0.5,1,1,0" (se recalcula de las
    #         respuestas; queda también para las cuentas que respondieron antes de guardarlas)
    quiz_respuestas: dict | None = Field(default=None, sa_type=JSON)
    quiz: str | None = None
    # "¿Habías ido antes a la CicloVida?" Línea base para medir cuántos llegan gracias a la app. None = no respondió.
    primera_vez: bool | None = None
    sintetico: bool = False  # datos de demostración generados por seed.py
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class Verificacion(SQLModel, table=True):
    """Código de 6 dígitos enviado al correo institucional. Se borra al registrarse."""

    correo_hash: str = Field(primary_key=True)
    codigo_hash: str
    expira: datetime = Field(sa_type=DateTime)
    intentos: int = 0


class Jornada(SQLModel, table=True):
    fecha: date = Field(primary_key=True)
    estado: str = "inscripcion"  # inscripcion | emparejada (grupos armados el sábado) | finalizada
    emparejada_en: datetime | None = Field(default=None, sa_type=DateTime)
    finalizada_en: datetime | None = Field(default=None, sa_type=DateTime)


class Salida(SQLModel, table=True):
    """Un parche de la lista. Lo genera el sistema para cada estación, hora y actividad; el joven elige."""

    id: int | None = Field(default=None, primary_key=True)
    jornada_fecha: date = Field(foreign_key="jornada.fecha", index=True)
    nombre: str
    tramo_id: str = Field(index=True)
    segmento: str
    franja: str
    actividad: str


class Inscripcion(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    salida_id: int = Field(foreign_key="salida.id", index=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    jornada_fecha: date = Field(index=True)
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class Grupo(SQLModel, table=True):
    """Grupo de 3 a 6 dentro de un parche. Lo arma k-means el sábado a las 5:00 p. m."""

    id: int | None = Field(default=None, primary_key=True)
    jornada_fecha: date = Field(foreign_key="jornada.fecha", index=True)
    salida_id: int | None = Field(default=None, foreign_key="salida.id", index=True)
    nombre: str
    tramo_id: str = Field(index=True)
    segmento: str
    franja: str
    actividad: str
    nivel: str = "armado"  # armado | juntado (incluye gente de un parche que no se llenó)


class Asignacion(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    grupo_id: int = Field(foreign_key="grupo.id", index=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    jornada_fecha: date = Field(index=True)
    estado: str = "pendiente"  # pendiente | confirmado | declinado
    ajustes: str = ""  # "franja,actividad": lo que cambió al juntarlo con otro parche
    tarde: bool = False  # se unió después de que se armaron los grupos
    respondido_en: datetime | None = Field(default=None, sa_type=DateTime)


class Encuesta(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    jornada_fecha: date = Field(index=True)
    grupo_id: int | None = Field(default=None, foreign_key="grupo.id")
    asistio: bool
    volveria: bool
    bienestar: int | None = None  # 1 a 5, solo si asistió
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class Espera(SQLModel, table=True):
    """Quien no encontró parche con gente compatible queda en espera; el sistema lo reintenta
    en cada tick y le avisa (app y Telegram) apenas aparezca uno."""

    id: int | None = Field(default=None, primary_key=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    jornada_fecha: date = Field(index=True)
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class Notificacion(SQLModel, table=True):
    """Avisos dentro de la app: por ahora, "tu espera encontró parche"."""

    id: int | None = Field(default=None, primary_key=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    titulo: str
    cuerpo: str
    leida: bool = False
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class MensajeForo(SQLModel, table=True):
    """Foro comunal: comentarios sobre los parches, la app o cómo se sienten."""

    id: int | None = Field(default=None, primary_key=True)
    joven_id: str | None = Field(default=None, foreign_key="joven.id", index=True)
    nombre: str  # primer nombre, igual que en el grupo
    universidad: str  # nombre corto
    categoria: str  # parches | app | animo
    texto: str = Field(max_length=500)
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class ChatMiembro(SQLModel, table=True):
    """Quién se unió al chat de un parche. Es opcional: solo quien entra ve el chat y es visto en él
    (primer nombre y universidad). En la demo, algunos simulados del parche también entran."""

    id: int | None = Field(default=None, primary_key=True)
    salida_id: int = Field(foreign_key="salida.id", index=True)
    joven_id: str = Field(foreign_key="joven.id", index=True)
    unido_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class ChatMensaje(SQLModel, table=True):
    """Mensaje del chat de un parche. Solo lo ven quienes se unieron al chat."""

    id: int | None = Field(default=None, primary_key=True)
    salida_id: int = Field(foreign_key="salida.id", index=True)
    joven_id: str | None = Field(default=None, foreign_key="joven.id", index=True)
    nombre: str  # primer nombre, como en el grupo
    universidad: str  # nombre corto
    simulado: bool = False  # lo escribió un joven simulado de la demo (con Gemini)
    responde_a: str | None = Field(default=None, max_length=40)  # primer nombre de a quién le contesta
    texto: str = Field(max_length=500)
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)


class Reporte(SQLModel, table=True):
    """Botón "Reportar un problema". Solo lo ve moderación, nunca el tablero."""

    id: int | None = Field(default=None, primary_key=True)
    reporta_id: str | None = Field(default=None, foreign_key="joven.id", index=True)
    reportado_id: str | None = Field(default=None, foreign_key="joven.id", index=True)
    grupo_id: int | None = Field(default=None, foreign_key="grupo.id")
    jornada_fecha: date = Field(index=True)
    motivo: str
    detalle: str = Field(default="", max_length=500)
    revisado: bool = False
    creado_en: datetime = Field(default_factory=_ahora, sa_type=DateTime)
