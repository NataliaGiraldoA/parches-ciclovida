"""Catálogo fijo de la CicloVida de Cali.

Estaciones 2026: la CicloVida central (Panamericana, Ingenio, Dorada, La Luna y Metropolitana) y
las seis comunitarias (Ciudad de Cali, Sol de Oriente, San Carlos, Las Américas, Torres de Comfandi
y Brisas de los Álamos), según El Tiempo y los boletines de la Alcaldía (cali.gov.co). Los puntos de
Dorada (Calle 9 con Carrera 66), La Luna (Calle 13 con Autopista Suroriental), Metropolitana
(Cementerio Metropolitano del Norte) y Ciudad de Cali (avenida Ciudad de Cali, Carrera 29 con
Calle 55) salen de publicaciones de la Alcaldía; los demás, de las direcciones de El País. Las coordenadas son aproximadas (OpenStreetMap): sirven para el mapa, no para navegar.
Validarlas con la Secretaría del Deporte y la Recreación antes de un piloto.
"""

JORNADA_INICIO = "08:00"
JORNADA_FIN = "13:00"

# Barrios de referencia por comuna (los más reconocibles, no la lista completa del DAP).
# Sirven para que el joven se ubique al elegir; validar con Planeación antes de un piloto.
BARRIOS_COMUNA = {
    1: ["Terrón Colorado", "Vista Hermosa", "Aguacatal", "Patio Bonito"],
    2: ["Santa Mónica", "La Flora", "Chipichape", "Menga", "Brisas de los Álamos"],
    3: ["San Antonio", "El Peñón", "Granada", "San Nicolás", "Centenario"],
    4: ["Salomia", "La Isla", "Popular", "Manzanares", "Jorge Isaacs"],
    5: ["Torres de Comfandi", "Los Andes", "Chiminangos", "Villa del Sol"],
    6: ["Petecuy", "Floralia", "Los Alcázares", "San Luis", "Calimío"],
    7: ["Alfonso López", "Siete de Agosto", "Puerto Mallarino", "Base Aérea"],
    8: ["El Troncal", "Las Américas", "La Base", "La Floresta", "Simón Bolívar"],
    9: ["Alameda", "Bretaña", "Guayaquil", "Obrero", "Junín"],
    10: ["El Guabal", "Santa Elena", "Olímpico", "Cristóbal Colón", "El Dorado"],
    11: ["San Carlos", "La Fortaleza", "León XIII", "Aguablanca", "La Independencia"],
    12: ["Doce de Octubre", "El Paraíso", "Asturias", "Sindical"],
    13: ["El Diamante", "El Poblado", "El Vergel", "Ulpiano Lloreda", "Los Comuneros II"],
    14: ["Alfonso Bonilla Aragón", "Manuela Beltrán", "Las Orquídeas", "Puertas del Sol"],
    15: ["El Retiro", "El Vallado", "Ciudad Córdoba", "Mojica", "Morichal"],
    16: ["Mariano Ramos", "República de Israel", "Unión de Vivienda Popular", "Antonio Nariño"],
    17: ["El Ingenio", "Ciudad Jardín", "El Caney", "El Limonar", "Ciudad Capri"],
    18: ["Meléndez", "Los Chorros", "Buenos Aires", "Alto Nápoles", "Caldas"],
    19: ["San Fernando", "El Refugio", "El Lido", "Pampalinda", "Tequendama"],
    20: ["Siloé", "Lleras Camargo", "Belisario Caicedo", "La Sultana", "Tierra Blanca"],
    21: ["Pízamos", "Calimío Decepaz", "Potrero Grande", "Valle Grande", "Desepaz"],
    22: ["Pance", "Ciudad Campestre", "Club Campestre", "Río Lili"],
}

COMUNAS = [{"id": n, "nombre": f"Comuna {n}", "barrios": BARRIOS_COMUNA[n]} for n in range(1, 23)]

TRAMOS = [
    # CicloVida central: cinco estaciones
    {"id": "panamericana", "nombre": "Panamericana", "comuna": 19,
     "punto": "Calle 9 con Carrera 37A", "referencia": "Canchas Panamericanas",
     "lat": 3.4283, "lng": -76.5388},
    {"id": "ingenio", "nombre": "El Ingenio", "comuna": 17,
     "punto": "Calle 16 con Carrera 83", "referencia": "Parque de El Ingenio",
     "lat": 3.3850, "lng": -76.5282},
    {"id": "dorada", "nombre": "Dorada", "comuna": 17,
     "punto": "Calle 9 con Carrera 66", "referencia": "Zona Dorada, El Gran Limonar",
     "lat": 3.3981, "lng": -76.5446},
    {"id": "la-luna", "nombre": "La Luna", "comuna": 9,
     "punto": "Calle 13 con Autopista Suroriental", "referencia": "Hotel La Luna y puente de La Luna",
     "lat": 3.4322, "lng": -76.5273},
    {"id": "metropolitana", "nombre": "Metropolitana", "comuna": 5,
     "punto": "Cementerio Metropolitano del Norte", "referencia": "Barrio Metropolitano del Norte, Calle 69",
     "lat": 3.4836, "lng": -76.4919},
    # CicloVida comunitaria: seis estaciones
    {"id": "ciudad-de-cali", "nombre": "Ciudad de Cali", "comuna": 12,
     "punto": "Carrera 29 con Calle 55", "referencia": "Avenida Ciudad de Cali, estación Colonia Nariñense",
     "lat": 3.4251, "lng": -76.5031},
    {"id": "sol-de-oriente", "nombre": "Sol de Oriente", "comuna": 21,
     "punto": "Carrera 25A # 89-16", "referencia": "Colegio Compartir",
     "lat": 3.4175, "lng": -76.4745},
    {"id": "san-carlos", "nombre": "San Carlos", "comuna": 11,
     "punto": "Calle 32 con Carrera 31", "referencia": "San Carlos y La Fortaleza",
     "lat": 3.4250, "lng": -76.5090},
    {"id": "americas", "nombre": "Las Américas", "comuna": 8,
     "punto": "Calle 39 con Carrera 11D", "referencia": "Las Américas",
     "lat": 3.4478, "lng": -76.5085},
    {"id": "torres-comfandi", "nombre": "Torres de Comfandi", "comuna": 5,
     "punto": "Carrera 1D con Calle 56", "referencia": "Torres de Comfandi",
     "lat": 3.4686, "lng": -76.5058},
    {"id": "brisas", "nombre": "Brisas de los Álamos", "comuna": 2,
     "punto": "Avenida 2 Norte con Calle 72N", "referencia": "Brisas y Guaduales",
     "lat": 3.4930, "lng": -76.5100},
]
TRAMOS_POR_ID = {t["id"]: t for t in TRAMOS}

# Estaciones que salieron de la CicloVida. No se ofrecen ni se abren parches en ellas: solo sirven para
# leer grupos y parches viejos que siguen en la base (historial, reportes, tablero).
TRAMOS_RETIRADOS = [
    {"id": "siloe", "nombre": "Siloé", "comuna": 20,
     "punto": "Diagonal 53 con Calle 9 Oeste", "referencia": "Parque Urbanización Venezuela",
     "lat": 3.4248, "lng": -76.5575},
    {"id": "petecuy", "nombre": "Petecuy", "comuna": 6,
     "punto": "Carrera 1D con Calle 73A", "referencia": "Petecuy", "lat": 3.4800, "lng": -76.4990},
    {"id": "corredor-verde", "nombre": "Corredor Verde", "comuna": 7,
     "punto": "Carrera 8 con Calle 62", "referencia": "Corredor Verde", "lat": 3.4655, "lng": -76.4960},
    {"id": "prado", "nombre": "El Prado", "comuna": 11,
     "punto": "Autopista Suroriental con Transversal 29", "referencia": "El Prado", "lat": 3.4195, "lng": -76.5140},
    {"id": "fortaleza", "nombre": "La Fortaleza", "comuna": 11,
     "punto": "Calle 32 con Carrera 31", "referencia": "San Carlos y La Fortaleza", "lat": 3.4250, "lng": -76.5090},
    {"id": "morichal", "nombre": "Morichal", "comuna": 15,
     "punto": "Calle 54 entre Carreras 25 y 46", "referencia": "Morichal de Comfandi", "lat": 3.4040, "lng": -76.4960},
]

# La estación activa que reemplaza a cada retirada (la más cercana): a quien la tenía de preferida se
# le cambia al arrancar el backend.
REEMPLAZO_TRAMO = {
    "siloe": "dorada", "petecuy": "metropolitana", "corredor-verde": "torres-comfandi",
    "prado": "la-luna", "fortaleza": "san-carlos", "morichal": "sol-de-oriente",
}

_TRAMOS_TODOS = {t["id"]: t for t in TRAMOS + TRAMOS_RETIRADOS}


def tramo_info(tramo_id: str) -> dict:
    """La estación de un parche o grupo guardado, siga activa o ya se haya retirado."""
    return _TRAMOS_TODOS[tramo_id]

# familia: con quién se puede mezclar una actividad cuando no alcanza el grupo
ACTIVIDADES = [
    {"id": "bici", "nombre": "Bici", "familia": "ruedas"},
    {"id": "patines", "nombre": "Patines", "familia": "ruedas"},
    {"id": "trotar", "nombre": "Trotar", "familia": "a_pie"},
    {"id": "caminar", "nombre": "Caminar", "familia": "a_pie"},
]
ACTIVIDADES_POR_ID = {a["id"]: a for a in ACTIVIDADES}

RITMOS = [
    {"id": "tranquilo", "nombre": "Tranquilo", "detalle": "Paseo, sin afán", "orden": 0},
    {"id": "moderado", "nombre": "Moderado", "detalle": "Constante, con pausas", "orden": 1},
    {"id": "rapido", "nombre": "Rápido", "detalle": "Para entrenar", "orden": 2},
]
RITMO_ORDEN = {r["id"]: r["orden"] for r in RITMOS}

FRANJAS = [
    {"id": "08:00", "nombre": "8:00 a. m.", "orden": 0},
    {"id": "09:30", "nombre": "9:30 a. m.", "orden": 1},
    {"id": "11:00", "nombre": "11:00 a. m.", "orden": 2},
]
FRANJA_ORDEN = {f["id"]: f["orden"] for f in FRANJAS}
FRANJA_NOMBRE = {f["id"]: f["nombre"] for f in FRANJAS}

# Ley 375 de 1997: joven = 14 a 28 años. Menores y mayores de edad nunca se mezclan.
RANGOS_EDAD = [
    {"id": "14-17", "nombre": "14 a 17 años", "segmento": "menor"},
    {"id": "18-22", "nombre": "18 a 22 años", "segmento": "mayor"},
    {"id": "23-28", "nombre": "23 a 28 años", "segmento": "mayor"},
]
SEGMENTO_EDAD = {r["id"]: r["segmento"] for r in RANGOS_EDAD}

# Motivos del botón "Reportar un problema"
MOTIVOS_REPORTE = [
    {"id": "riesgo", "nombre": "Me hizo sentir en riesgo"},
    {"id": "acoso", "nombre": "Acoso, irrespeto o comentarios fuera de lugar"},
    {"id": "fuera_estacion", "nombre": "Insistió en vernos fuera de la estación o pidió datos personales"},
    {"id": "otro", "nombre": "Otro problema"},
]
MOTIVOS_IDS = {m["id"] for m in MOTIVOS_REPORTE}

# Quiz "Tu estilo de parche": 5 preguntas cortas y en tono de CicloVida, opcional.
# Cada pregunta mapea por dentro a una dimensión de 0 a 1 (sociabilidad del plan, charla,
# gusto por lo nuevo, esperar al grupo, puntualidad); la idea viene de los Cinco Grandes,
# pero sin lenguaje clínico ni etiquetas: nadie ve "eres X", ni en su perfil ni en el de otros.
# Es un criterio SECUNDARIO de desempate al armar grupos (peso menor que ritmo, edad y
# experiencia) y sus respuestas nunca llegan al tablero de la Secretaría.
QUIZ_PREGUNTAS = [
    {"id": 1, "texto": "Termina la CicloVida. ¿Cuál es el plan?", "opciones": [
        {"id": "a", "texto": "¡Jugo y charla con el parche!", "valor": 1.0},
        {"id": "b", "texto": "Foto del grupo y a la casa", "valor": 0.0},
        {"id": "c", "texto": "Depende de cómo esté el ambiente", "valor": 0.5},
    ]},
    {"id": 2, "texto": "En plena ruta, tú vas…", "opciones": [
        {"id": "a", "texto": "Echando cuento todo el camino", "valor": 1.0},
        {"id": "b", "texto": "En mi mundo, gozándome el paisaje", "valor": 0.0},
        {"id": "c", "texto": "Un rato de charla, un rato de silencio", "valor": 0.5},
    ]},
    {"id": 3, "texto": "¿Ruta de siempre o ruta nueva?", "opciones": [
        {"id": "a", "texto": "La de siempre, a la fija", "valor": 0.0},
        {"id": "b", "texto": "¡Nueva! A ver qué aparece", "valor": 1.0},
    ]},
    {"id": 4, "texto": "Alguien del parche se queda atrás…", "opciones": [
        {"id": "a", "texto": "Paramos todos: nadie se queda", "valor": 1.0},
        {"id": "b", "texto": "Cada quien a su paso y nos vemos adelante", "valor": 0.0},
    ]},
    {"id": 5, "texto": "Domingo, 7:50 a. m. Tú estás…", "opciones": [
        {"id": "a", "texto": "Hace rato en la estación", "valor": 1.0},
        {"id": "b", "texto": "Llegando justo con la salida", "valor": 0.0},
    ]},
]
QUIZ_POR_ID = {p["id"]: p for p in QUIZ_PREGUNTAS}


def puntuar_quiz(respuestas: dict[int, str]) -> tuple[float, ...]:
    """De {pregunta: opción} al vector interno de 5 valores entre 0 y 1, en orden de pregunta."""
    valores = []
    for p in QUIZ_PREGUNTAS:
        opcion = next(o for o in p["opciones"] if o["id"] == respuestas[p["id"]])
        valores.append(opcion["valor"])
    return tuple(valores)


def quiz() -> dict:
    return {
        "titulo": "Tu estilo de parche",
        "detalle": "5 preguntas, un minuto. Es opcional: solo sirve para juntarte con gente que "
                   "disfruta el domingo como tú. Nadie ve tus respuestas, ni siquiera tu grupo.",
        "preguntas": QUIZ_PREGUNTAS,
    }


# Categorías del foro comunal
FORO_CATEGORIAS = [
    {"id": "parches", "nombre": "Mis parches"},
    {"id": "app", "nombre": "La app"},
    {"id": "animo", "nombre": "Cómo me siento"},
]
FORO_IDS = {c["id"] for c in FORO_CATEGORIAS}

# Territorio inicial: universidades de Cali. Se acepta el dominio o cualquier subdominio
# (u.icesi.edu.co entra por icesi.edu.co). Confirmar con cada universidad el dominio de sus estudiantes.
UNIVERSIDADES = [
    {"id": "univalle", "nombre": "Universidad del Valle", "corto": "Univalle",
     "dominios": ["correounivalle.edu.co", "univalle.edu.co"]},
    {"id": "uao", "nombre": "Universidad Autónoma de Occidente", "corto": "UAO", "dominios": ["uao.edu.co"]},
    {"id": "usb", "nombre": "Universidad de San Buenaventura Cali", "corto": "USB Cali", "dominios": ["usbcali.edu.co"]},
    {"id": "javeriana", "nombre": "Pontificia Universidad Javeriana Cali", "corto": "Javeriana",
     "dominios": ["javerianacali.edu.co"]},
    {"id": "icesi", "nombre": "Universidad Icesi", "corto": "Icesi", "dominios": ["icesi.edu.co"]},
    {"id": "usc", "nombre": "Universidad Santiago de Cali", "corto": "USC", "dominios": ["usc.edu.co"]},
    {"id": "unilibre", "nombre": "Universidad Libre, seccional Cali", "corto": "Unilibre", "dominios": ["unilibre.edu.co"]},
    {"id": "unicatolica", "nombre": "Fundación Universitaria Católica Lumen Gentium", "corto": "Unicatólica",
     "dominios": ["unicatolica.edu.co"]},
    {"id": "uniajc", "nombre": "Institución Universitaria Antonio José Camacho", "corto": "UNIAJC",
     "dominios": ["uniajc.edu.co"]},
]
UNIVERSIDADES_POR_ID = {u["id"]: u for u in UNIVERSIDADES}


def universidad_de(correo: str) -> dict | None:
    dominio = correo.rsplit("@", 1)[-1].strip().lower()
    for u in UNIVERSIDADES:
        if any(dominio == d or dominio.endswith("." + d) for d in u["dominios"]):
            return u
    return None


# Árboles de Cali para nombrar los parches
NOMBRES_PARCHE = [
    "Samán", "Guayacán", "Ceiba", "Chiminango", "Gualanday", "Cañaguate",
    "Caracolí", "Almendro", "Tulipán", "Iguá", "Carbonero", "Pisamo",
]


def rangos_permitidos() -> list[dict]:
    from .config import PERMITIR_MENORES

    return [r for r in RANGOS_EDAD if PERMITIR_MENORES or r["segmento"] == "mayor"]


def catalogo() -> dict:
    from .config import ESPERA_MINUTOS, PERMITIR_MENORES

    return {
        "foro_categorias": FORO_CATEGORIAS,
        "espera_minutos": ESPERA_MINUTOS,
        "quiz": quiz(),
        "comunas": COMUNAS,
        "tramos": TRAMOS,
        "actividades": ACTIVIDADES,
        "ritmos": RITMOS,
        "franjas": FRANJAS,
        "rangos_edad": rangos_permitidos(),
        "permite_menores": PERMITIR_MENORES,
        "motivos_reporte": MOTIVOS_REPORTE,
        "universidades": [{"id": u["id"], "nombre": u["nombre"], "corto": u["corto"], "dominios": u["dominios"]}
                          for u in UNIVERSIDADES],
        "jornada": {"inicio": JORNADA_INICIO, "fin": JORNADA_FIN, "dia": "domingo"},
    }
