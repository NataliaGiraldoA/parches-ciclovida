"""Aviso de privacidad (Ley 1581 de 2012 y Decreto 1377 de 2013).

BORRADOR para el prototipo. Antes de un piloto con personas reales debe revisarlo
quien vaya a ser el responsable del tratamiento, y completar los datos entre corchetes.
"""

from .config import AVISO_VERSION, PERMITIR_MENORES


def aviso() -> dict:
    secciones = [
        {
            "titulo": "Quién trata tus datos",
            "texto": "Equipo Dedsec, como responsable del prototipo Parches CicloVida. "
                     "Contacto: [correo del equipo]. Parches CicloVida no es un canal oficial de la Alcaldía de Cali.",
        },
        {
            "titulo": "Qué datos pedimos",
            "texto": "Tu correo institucional, solo para comprobar que estudias en una universidad de Cali: no lo "
                     "guardamos, guardamos una huella cifrada que no permite recuperarlo y el nombre de tu universidad. "
                     "Además, tu primer nombre, tu rango de edad, la comuna donde vives, tu estación favorita, tu "
                     "actividad, tu ritmo y el parche que elijas. Si respondes el quiz opcional «Tu estilo de parche», "
                     "guardamos tus respuestas (cinco preguntas sobre cómo te gusta el domingo). Después de cada "
                     "domingo, si fuiste, si volverías y, si quieres, cómo te sentiste del 1 al 5. No pedimos "
                     "documento, dirección, teléfono ni fotos.",
        },
        {
            "titulo": "Para qué los usamos",
            "texto": "1) Verificar que todas las personas de los parches son estudiantes. "
                     "2) Recomendarte parches y, dentro del parche que elijas, armar grupos de 3 a 6 con un algoritmo "
                     "k-means que usa tu ritmo, tu rango de edad, cuántos domingos has ido y, si respondiste el quiz, "
                     "tu estilo de parche, solo para desempatar. "
                     "3) Enviarte los avisos del sábado y del domingo. "
                     "4) Medir, solo con cifras agregadas por comuna y por grupo, si la CicloVida acompañada funciona.",
        },
        {
            "titulo": "Quién ve qué",
            "texto": "Tu grupo ve tu primer nombre, tu universidad, tu actividad y si confirmaste. La lista de parches "
                     "solo muestra cuántas personas van, nunca quiénes. Nadie ve tus respuestas del quiz: ni tu "
                     "grupo ni la Secretaría, y la app no te pone ninguna etiqueta. La Secretaría del Deporte y la "
                     "Recreación, si recibe el tablero, ve cifras agregadas: los conteos menores a 5 no se muestran y "
                     "nunca aparecen nombres. No vendemos ni compartimos tus datos con nadie más.",
        },
        {
            "titulo": "Chat de tu parche (opcional)",
            "texto": "Unirte al chat de tu parche es opcional. Si entras, quienes estén en ese chat ven tu primer nombre, "
                     "tu universidad y lo que escribes; quien no entra no ve nada. Si te cambias o te sales del parche, "
                     "sales también de su chat, y tus mensajes se borran si borras tus datos. En esta demo, algunas "
                     "personas del chat son estudiantes simulados, marcados con IA: para que respondan, los últimos "
                     "mensajes del chat, con el primer nombre de quien los escribió, se procesan con Gemini, un servicio "
                     "de Google. Nunca compartas tu teléfono ni tu dirección: el encuentro es en la estación.",
        },
        {
            "titulo": "Tu ubicación, solo para la ruta",
            "texto": "Si tocas «Cómo llego» en el mapa, la app te pide la ubicación del teléfono para trazar la ruta "
                     "hasta la estación de tu parche. Se usa solo en tu teléfono: no la enviamos a Parches CicloVida "
                     "ni la guardamos. Para calcular la ruta, el punto de partida y el de llegada se envían al servicio "
                     "de rutas de OpenStreetMap (OSRM), y a Google Maps si eliges navegar paso a paso. Es opcional: "
                     "el resto de la app funciona sin ella.",
        },
        {
            "titulo": "Si usas el bot de Telegram",
            "texto": "Conectar Telegram es opcional. Si le escribes al bot con tus palabras, el texto de esos mensajes, "
                     "tu primer nombre y tus preferencias de parche se procesan con Gemini, un servicio de Google, "
                     "solo para entenderte y responderte. No le enviamos tu correo, tu universidad ni datos de otras "
                     "personas de tu grupo. Si prefieres que no pase por ese servicio, usa los comandos y botones del "
                     "bot o la app.",
        },
        {
            "titulo": "Dato sensible y opcional",
            "texto": "La pregunta de cómo te sentiste puede considerarse un dato sensible. Responderla es opcional: "
                     "puedes enviar la encuesta sin contestarla.",
        },
        {
            "titulo": "Tus derechos",
            "texto": "Puedes conocer, actualizar y corregir tus datos, revocar esta autorización y pedir que los "
                     "borremos. Desde la app: Ajustes > Borrar mis datos. También por correo a [correo del equipo]. "
                     "Respondemos consultas en máximo 10 días hábiles y reclamos en máximo 15.",
        },
        {
            "titulo": "Cuánto tiempo los guardamos",
            "texto": "Mientras dure el piloto. Al terminar se borran los datos personales y quedan solo las cifras agregadas.",
        },
        {
            "titulo": "Seguridad en los encuentros",
            "texto": "Los encuentros son siempre en una estación pública de la CicloVida y en su horario. Si algo te hace "
                     "sentir en riesgo, usa Reportar un problema dentro de tu parche. En una emergencia llama al 123.",
        },
    ]
    if PERMITIR_MENORES:
        secciones.insert(4, {
            "titulo": "Si tienes entre 14 y 17 años",
            "texto": "Necesitamos la autorización de tu mamá, papá o acudiente, y su nombre. Los menores de edad solo "
                     "van en parches con otros menores de edad.",
        })
    return {"version": AVISO_VERSION, "titulo": "Aviso de privacidad", "secciones": secciones}
