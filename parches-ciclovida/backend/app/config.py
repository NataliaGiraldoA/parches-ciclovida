import os
from pathlib import Path
from zoneinfo import ZoneInfo


def _cargar_env() -> None:
    """Lee backend/.env (KEY=valor, # comentarios) sin pisar variables ya definidas.

    Así el token de Telegram y demás secretos viven en un archivo ignorado por git,
    en vez de escribirse en la terminal cada vez. Sin dependencias nuevas.
    """
    ruta = Path(__file__).resolve().parent.parent / ".env"
    if not ruta.exists():
        return
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, _, valor = linea.partition("=")
        clave, valor = clave.strip(), valor.strip().strip('"').strip("'")
        if clave and clave not in os.environ:
            os.environ[clave] = valor


_cargar_env()

TZ = ZoneInfo("America/Bogota")

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./parches.db")
# `or`: una variable definida pero vacía (p. ej. en Render) no deja la clave en blanco
ADMIN_KEY = os.getenv("ADMIN_KEY") or "dedsec-demo"
SCHEDULER_ON = os.getenv("SCHEDULER", "1") == "1"

# Si la base arranca vacía, carga los jóvenes simulados al iniciar. En Render el disco se borra en
# cada despliegue o reinicio: así la demo nunca sale en blanco.
SEMBRAR_AL_INICIAR = os.getenv("SEMBRAR_AL_INICIAR", "0") == "1"

# Si una persona real pide un parche sin gente (cualquier estación, hora o actividad), se le suman
# jóvenes simulados para que el match salga de una; sin esto casi siempre queda en lista de espera.
# Aplica a todas las cuentas. Con RELLENAR_CON_SIMULADOS=0 se apaga y vuelve la lista de espera.
RELLENAR_CON_SIMULADOS = os.getenv("RELLENAR_CON_SIMULADOS", "1") == "1"

GRUPO_MIN = int(os.getenv("GRUPO_MIN", "3"))
GRUPO_OBJETIVO = int(os.getenv("GRUPO_OBJETIVO", "5"))
GRUPO_MAX = int(os.getenv("GRUPO_MAX", "6"))

# Peso de cada pregunta del quiz de estilo en k-means (ritmo pesa 1.0, edad 0.6, experiencia 0.4).
# Con los 1.500 simulados: 0.2 casi no mejora la afinidad de estilo (+1 punto sobre no usarlo) y deja
# el ritmo intacto; 0.5 la sube 6 puntos a cambio de 4 puntos menos de grupos con el mismo ritmo.
# Medirlo con: python -m app.reporte (ver README).
PESO_QUIZ = float(os.getenv("PESO_QUIZ", "0.2"))

# Anonimato del tablero: conteos por debajo de K_CONTEO se muestran como "<K";
# promedios con menos de K_PROMEDIO respuestas no se muestran.
K_CONTEO = int(os.getenv("K_CONTEO", "5"))
K_PROMEDIO = int(os.getenv("K_PROMEDIO", "3"))

# Calendario semanal (hora de Cali)
EMPAREJAR_SABADO = os.getenv("EMPAREJAR_SABADO", "17:00")  # cierra inscripciones del domingo
FINALIZAR_DOMINGO = os.getenv("FINALIZAR_DOMINGO", "13:00")  # fin de la jornada, abre encuesta
DIAS_ENCUESTA = int(os.getenv("DIAS_ENCUESTA", "4"))  # la encuesta queda abierta hasta el jueves

# Recomendación del mentor: piloto solo con mayores de 18. Con PERMITIR_MENORES=1 se aceptan
# jóvenes de 14 a 17 con el consentimiento de su acudiente, y nunca se mezclan con adultos.
PERMITIR_MENORES = os.getenv("PERMITIR_MENORES", "0") == "1"

# Seguridad: con este número de reportes de personas distintas, alguien sale del emparejamiento
# hasta que un moderador lo revise.
REPORTES_PARA_SUSPENDER = int(os.getenv("REPORTES_PARA_SUSPENDER", "2"))

# Emparejamiento automático: si no hay un parche con gente y las mismas características,
# el joven queda en espera. Pasados estos minutos, la app le muestra parches parecidos.
ESPERA_MINUTOS = int(os.getenv("ESPERA_MINUTOS", "10"))

# Bot de Telegram (opcional). Con el token y el nombre del bot, el joven vincula su cuenta
# desde la app y recibe por Telegram el aviso cuando su espera encuentra parche.
TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN", "")
TELEGRAM_BOT = os.getenv("TELEGRAM_BOT", "")  # nombre de usuario del bot, sin @

# Bot conversacional (opcional): con la API key de Gemini, el bot entiende texto libre
# ("quiero trotar el domingo temprano") y usa las mismas funciones del backend.
# Sin key, el bot sigue funcionando con comandos y botones.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.1-flash-lite")
# Si el modelo principal no está disponible (404) o está saturado (429/5xx), se prueban estos en orden.
GEMINI_RESPALDO = [m.strip() for m in os.getenv("GEMINI_RESPALDO", "gemini-3.5-flash,gemini-flash-latest").split(",")
                   if m.strip()]

# Pronóstico del domingo (Open-Meteo, gratis y sin clave). Con CLIMA=0 la app simplemente no lo muestra.
CLIMA_ON = os.getenv("CLIMA", "1") == "1"

# Foro comunal: largo máximo de cada mensaje.
FORO_MAX = int(os.getenv("FORO_MAX", "500"))

# Chat del parche. En la demo, hasta CHAT_MAX_SIMULADOS jóvenes simulados del parche entran al chat y
# conversan con Gemini según su personalidad del JSON. CHAT_PAUSA_SEG es la pausa de "escribiendo…"
# antes de cada mensaje simulado, para que se sienta como un chat de verdad.
CHAT_MAX_SIMULADOS = int(os.getenv("CHAT_MAX_SIMULADOS", "5"))
CHAT_PAUSA_SEG = float(os.getenv("CHAT_PAUSA_SEG", "1.5"))
# Charla entre simulados: si el chat lleva CHAT_CHARLA_SEG segundos quieto y alguien real lo tiene
# abierto, conversan entre ellos. Paran después de CHAT_CHARLA_MAX mensajes seguidos sin que escriba
# una persona real (así no hablan solos sin fin ni gastan llamadas a Gemini).
CHAT_CHARLA_SEG = float(os.getenv("CHAT_CHARLA_SEG", "90"))
CHAT_CHARLA_MAX = int(os.getenv("CHAT_CHARLA_MAX", "8"))

# Versión del aviso de privacidad que se guarda con cada autorización (Ley 1581 de 2012).
# .3: bot conversacional (Gemini); .4: ubicación para la ruta al parche; .5: respuestas del quiz de estilo;
# .6: chat del parche
AVISO_VERSION = "2026-09-25.6"

# Verificación con correo institucional. El correo no se guarda: solo su huella HMAC con SECRETO.
SECRETO = os.getenv("SECRETO", "dedsec-demo-cambiar")
CODIGO_MINUTOS = int(os.getenv("CODIGO_MINUTOS", "15"))
SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASS", "")
SMTP_FROM = os.getenv("SMTP_FROM", "Parches CicloVida <no-responder@parches.local>")
# Sin servidor de correo, para la demo la API devuelve el código en la respuesta. En un piloto: CORREO_DEMO=0.
CORREO_DEMO = os.getenv("CORREO_DEMO", "1") == "1"
