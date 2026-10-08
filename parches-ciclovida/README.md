# Parches CicloVida

Prototipo TRL 3 del equipo Dedsec para el reto CicloVida del Hackathon Smart City Expo Cali 2026.

Un estudiante universitario de Cali verifica su correo institucional y crea su perfil. Cada semana el sistema abre parches en las 11 estaciones de la CicloVida, uno por hora (8:00, 9:30, 11:00) y actividad (bici, patines, trotar, caminar). Al entrar, un match automático (la misma idea de distancia del k-means) lo une al parche que ya tiene gente con su hora, estación y actividad; si no existe, queda en lista de espera y se le avisa —en la app y por Telegram— apenas aparezca, con parches parecidos como plan B. También puede elegir a mano, ver las zonas en un mapa interactivo y comentar en el foro comunal. El sábado a las 5:00 p. m. un algoritmo k-means divide a la gente de cada parche en grupos de 3 a 6 y a las 7:00 p. m. le llega la notificación para confirmar. Ese es el momento en que decide si sale el domingo. Al terminar la jornada, la app le pregunta si fue, si volvería y, de forma opcional, cómo se sintió del 1 al 5. La Secretaría ve un tablero web solo con cifras agregadas por comuna y por grupo.

```
parches-ciclovida/
├── app/        App móvil en Flutter (Android, iOS y web para proyectar)
└── backend/    FastAPI + SQLite: registro, emparejamiento, encuestas, tablero web
```

## Qué pide el reto y dónde está

| Requisito TRL 3 | Dónde |
|---|---|
| Registro con correo institucional | `app/lib/screens/registro.dart`, `POST /api/verificacion`, `POST /api/jovenes`, `backend/app/verificacion.py` |
| Volver a entrar (login) | `app/lib/screens/ingreso.dart`, `POST /api/verificacion` con `para: "ingreso"`, `POST /api/sesiones` |
| Match automático de parche | `POST /api/yo/match`, `emparejar_automatico` en `backend/app/services.py` |
| Lista de espera con aviso | `revisar_esperas` (tick cada 5 min), `GET /api/yo/notificaciones`, bot de Telegram en `backend/app/telegram.py` |
| Parches generados por el sistema | `GET /api/parches`, `POST /api/yo/parche`, `app/lib/screens/elegir_parche.dart` |
| Agrupamiento con k-means | `backend/app/matching.py` (funciones puras, con pruebas) |
| Notificaciones | `app/lib/notificaciones.dart`: sábado 7:00 p. m. y domingo 1:30 p. m., cada semana |
| Mapa interactivo de zonas | `app/lib/screens/mapa.dart` (flutter_map + OpenStreetMap, 11 estaciones) |
| Foro comunal | `GET/POST /api/foro`, `app/lib/screens/foro.dart` |
| Historial de domingos | `GET /api/yo/historial`, `app/lib/screens/historial.dart` (a qué parches fue y con quién) |
| Quiz "Tu estilo de parche" | `POST /api/yo/quiz`, `QUIZ_PREGUNTAS` en `backend/app/catalog.py`, `app/lib/screens/quiz.dart` |
| Base de datos | SQLite con SQLModel, `backend/app/models.py` |
| Tablero | `http://localhost:8000/tablero/`, `backend/static/tablero/` |

## Match automático, espera y Telegram

Recién registrado, la app no muestra una lista para escoger: llama a `POST /api/yo/match` y el
sistema une al joven al parche que **ya tiene gente** con sus mismas características (misma actividad
y, si las declaró, misma estación y hora), eligiendo el más afín con la misma idea de distancia del
k-means (hora, ritmo mediano del parche, cercanía de comuna, tamaño). Siempre puede tocar
"Prefiero elegir yo" y escoger a mano. Ese match automático corre solo al registrarse: en las semanas
siguientes (por ejemplo, después de terminar el domingo en la demo) la persona lo pide con **Buscar
match** o elige a mano.

Si no existe ninguno, la pantalla de espera muestra el parche más parecido —aunque esté vacío— por
si quiere tomar la iniciativa y estrenarlo; si no, queda en
**lista de espera**: el scheduler la revisa cada 5 minutos y, apenas alguien compatible se inscribe,
lo une y le avisa dentro de la app y por Telegram. Pasados
`ESPERA_MINUTOS` (10 por defecto), la app le muestra además parches parecidos o disponibles para que
no siga esperando si no quiere.

### Anclar el bot de Telegram (5 minutos)

1. En Telegram, habla con **@BotFather** → `/newbot` → dale un nombre y un usuario (p. ej.
   `ParchesCicloVidaBot`). Te entrega un **token**.
2. `cd backend && copy .env.example .env` y pega el token en `TELEGRAM_TOKEN=`. Nada más:
   el `@` del bot se detecta solo con `getMe`, y el menú de comandos se registra al arrancar.
3. Reinicia el backend. En el log debe salir `Bot de Telegram listo: @TuBot`; también puedes
   verificar con `GET /api/admin/telegram` (dice si está configurado, el `@` y cuántas cuentas
   se han vinculado, y qué falta si algo no cuadra).
4. En la app, toca **Conectar Telegram** (tarjeta de espera o Ajustes): se abre
   `t.me/<bot>?start=<código>` y el backend vincula el chat. El bot revisa sus mensajes cada
   20 segundos.

Sin token, todo lo de Telegram se apaga solo y queda el aviso interno de la app.

El bot empata las funciones de la app en el chat (`backend/app/telegram.py`):

| En el chat | Qué hace |
|---|---|
| `/parche` | Tu estado del domingo. Si aún no tienes parche, corre el match; si quedas en espera, te propone el que más se ajusta con botones **Unirme**, **Ver otras opciones** y **Prefiero esperar** |
| `/confirmo` / `/novoy` | Lo mismo que el botón de confirmar de la app (también son botones en el aviso del sábado) |
| `/foro` | Publicar en el foro: escribes el mensaje y eliges el tema con un botón. Leer el foro es en la app |
| `/cuenta` | Con qué cuenta está conectado el chat |
| `/desconectar` | Suelta el chat de tu cuenta (también con **Desconectar** en la tarjeta de Telegram de la app) |
| `/ayuda` | La lista de comandos |
| Propuesta de parche | Al entrar en lista de espera: "Hola X, todavía no tenemos parche confirmado… este es el que más se ajusta a tus preferencias" |
| Aviso de match | Cuando tu lista de espera encuentra parche |
| Aviso del sábado | Cuando k-means arma tu grupo, con botones ✅ Confirmo / ❌ No voy |

**Un chat, una cuenta.** Un chat de Telegram queda conectado a una sola cuenta. Si en la demo se
prueba con un solo Telegram y varias cuentas, basta con tocar **Conectar Telegram** desde la cuenta
que se quiere usar: el chat pasa a esa cuenta y la anterior queda desconectada (el bot lo avisa).

**Un token, un backend.** Si dos backends corren con el mismo `TELEGRAM_TOKEN` (por ejemplo, el de
dos personas del equipo), los dos leen los mismos mensajes y los dos contestan. El que no tiene el
chat vinculado en su base de datos responde «No reconozco este chat», justo debajo de la respuesta
buena. Cada quien debe usar su propio bot (`/newbot` en @BotFather), o solo un computador debe dejar
el token en su `.env`.

Cambiarse de parche también se hace desde el chat. Como deja un cupo libre, el bot pide
confirmarlo, igual que el diálogo de la app: con botones **✅ Sí, cámbiame** / **Me quedo**, o
conversando. La confirmación la exige el servidor (`confirmo_cambio`), no solo el prompt.

### Bot conversacional (Gemini)

Con `GEMINI_API_KEY` en `backend/.env` (se saca en https://aistudio.google.com/apikey), el bot
entiende texto libre: «quiero trotar el domingo temprano por Panamericana», «¿quién va conmigo?»,
«sí, úneme», «publica en el foro que me encantó el parche». Está en `backend/app/asistente.py`:

- **Function calling.** Gemini no responde de memoria: llama a las mismas funciones de la app
  (`ver_mi_estado`, `buscar_parches`, `unirme_a_parche`, `confirmar_asistencia`, `publicar_en_foro`),
  así que nunca inventa parches, horas ni personas. Los parches que menciona también salen como
  botones "Unirme".
- **Hace las cosas él mismo.** Unirse, cambiarse de parche (con confirmación), confirmar
  asistencia y publicar en el foro se resuelven en el chat; solo manda a la app para leer el foro,
  ver el mapa o borrar datos. Si le dictas un mensaje para el foro, lo publica de una.
- **Reglas en el prompt.** Une o publica solo si el joven lo pidió o aceptó; ante acoso o riesgo
  remite a "Reportar un problema" y al 123; ante malestar emocional responde con empatía y sin
  diagnosticar.
- **Memoria corta.** Recuerda los últimos 12 turnos por chat (en memoria); `/cancelar` la borra.
- **Privacidad.** A Gemini van los mensajes que el joven le escribe al bot, su primer nombre y sus
  preferencias; nunca el correo ni la universidad. Quedó declarado en el aviso de privacidad
  (versión `2026-09-25.3`).
- **Sin key**, el texto libre responde con la lista de comandos, y todo lo demás sigue igual.
  Si Gemini falla o no hay red, el bot responde con una salida amable y no se cae.

El modelo es `gemini-3.1-flash-lite` por defecto (rápido, ~2 s); si no está disponible o está saturado, prueba en orden `gemini-3.5-flash` y `gemini-flash-latest` (`GEMINI_RESPALDO`). Se cambia con `GEMINI_MODEL`. `GET /api/admin/telegram`
muestra si el modo conversacional está activo.

## Quiz "Tu estilo de parche" (afinidad, sin etiquetas)

Cinco preguntas cortas en tono de CicloVida ("Termina la CicloVida, ¿cuál es el plan?: ¡jugo y
charla con el parche! / foto y a la casa"). Las dimensiones que mide (plan social, charla, gusto
por lo nuevo, esperar al grupo, madrugar) están inspiradas en dimensiones clásicas de afinidad,
pero sin lenguaje clínico. Reglas de diseño, pedidas por el equipo:

- **Al inicio, pero opcional.** Aparece apenas se crea el perfil, antes del primer match, con
  "Ahora no" / "No quiero hacerlo ahora". Quien lo salta ve la invitación en "Mi parche" y en
  Ajustes para hacerlo después, y mientras tanto queda en el punto medio y se agrupa igual por
  comuna, estación, actividad y hora.
- **Criterio secundario.** En k-means pesa 0,2 por pregunta (menos que ritmo 1,0, edad 0,6 y
  experiencia 0,4) y en el match automático solo desempata entre parches estructuralmente
  equivalentes. El peso se ajusta con `PESO_QUIZ`; su efecto medido está en "Datos simulados y
  reporte del emparejamiento".
- **Se guarda lo que respondió.** `Joven.quiz_respuestas` guarda las respuestas tal cual, como JSON
  (`{"1": "a", "2": "c", …}`), y `Joven.quiz` el vector de 0 a 1 que usa k-means. El vector se
  recalcula de las respuestas, así que si se cambia el valor de una opción no hay que migrar nada.
- **Sin etiquetas.** El servidor no devuelve puntajes ni perfiles: la app solo sabe si ya se
  respondió (`quiz_respondido`). Nadie ve "eres X", ni en su perfil ni en el de otros.
- **Invisible para la Secretaría.** Las respuestas de personas reales no llegan al tablero ni a
  ningún reporte: el reporte del emparejamiento solo muestra las de los jóvenes simulados.

## Chat del parche (opcional)

Apenas te unes a un parche, "Mi parche" pregunta **¿Deseas unirte al chat de tu parche?** con
**Unirme al chat** y **Ahora no**. Nadie queda adentro sin quererlo; si dices "Ahora no", queda un
enlace discreto para entrar después. El código está en `backend/app/chat.py` y
`app/lib/screens/chat.dart`.

- **Conversación real.** Las personas reales que entran al chat del mismo parche se leen entre sí.
  La app consulta los mensajes nuevos cada 2,5 s y muestra "escribiendo…".
- **Privacidad.** Solo quien entra ve el chat y es visto en él, con su primer nombre y su universidad,
  lo mismo que ve su grupo. Quien no entra solo sabe cuántos hay. Al cambiarse o salirse del parche,
  sale también de su chat, y al borrar la cuenta se borran sus mensajes.
- **Simulados con IA** (`backend/app/chat_simulado.py`). En la demo, hasta `CHAT_MAX_SIMULADOS`
  (5) jóvenes simulados del parche entran al chat, primero los de tu grupo si ya se armó. Cada uno
  habla con **su personalidad del JSON**: su perfil (Parchadito, Madrugador, Deportista o
  Contemplativo) y sus respuestas del quiz, además de su actividad, ritmo, edad y universidad. Una
  sola llamada a Gemini con respuesta en JSON decide quién habla, en qué orden, a quién le contesta
  y qué dice.
- **Varios a la vez y entre ellos.** A cada mensaje tuyo pueden contestar de 1 a 3 simulados, y
  alguno puede reaccionarle a otro: se dan la razón, se contradicen con buena onda, se echan
  bromas. La app muestra a quién le habla cada uno ("↪ a Laura"). Al entrar a un chat vacío,
  primero charlan entre ellos y después te dan la bienvenida.
- **Charla cuando el chat está quieto.** Si nadie escribe en `CHAT_CHARLA_SEG` (90 s) y alguien real
  tiene el chat abierto, los simulados conversan solos (el domingo, la ruta, el clima, la semana en
  la u) y a veces te invitan. Paran después de `CHAT_CHARLA_MAX` (8) mensajes seguidos sin que
  escriba una persona real, así que nunca hablan sin fin ni gastan llamadas a Gemini de más.
- **Reglas de los simulados.** No inventan datos del parche. Nunca piden ni dan teléfonos, direcciones
  ni redes (si alguien pide WhatsApp, proponen seguir por el chat). El encuentro es siempre en la
  estación. Nada romántico. Ante un riesgo, recuerdan «Reportar un problema» y el 123. Si les
  preguntan, dicen que son simulados.
- **Siempre marcados.** En la app los simulados llevan **✨ IA**, para que nadie crea que habla con una
  persona real. Sin `GEMINI_API_KEY` solo saludan con un mensaje fijo según su perfil, y si Gemini
  está caído el chat de las personas reales sigue funcionando.
- **Qué va a Gemini.** Las fichas de los simulados, los datos del parche y los últimos 25 mensajes con
  el primer nombre de quien los escribió; de las personas reales, nada más. Está en el aviso de
  privacidad (versión `2026-09-25.6`).

## Mapa y foro

- **Mapa** (pestaña Mapa): cada estación se marca con la **figura de su actividad** (bici, patines,
  trotar, caminar) en el color de la marca, sin círculos: la actividad con más gente, o la del
  filtro que elijas arriba (los chips hacen de leyenda). Un número pequeño dice cuántos van este
  domingo; la figura clara, que aún no hay nadie. Tu estación lleva la etiqueta **Tu parche**, con
  zoom aparecen los nombres, y el mapa no rota. La ficha de la estación muestra cuánta gente va por
  actividad y la hora con más gente. El mapa base es OpenStreetMap en gris claro, con un filtro de
  color (`ColorFiltered`), para que resalten los colores de las actividades. Los mapas base claros
  gratuitos, como CARTO, ahora piden API key.
- **Ruta a tu parche** (`app/lib/ruta.dart`): con el botón **Cómo llego a mi parche** la app toma la
  ubicación del teléfono (geolocator) y traza la ruta por calles hasta la estación de tu parche con el
  servicio público de rutas de OpenStreetMap (OSRM de FOSSGIS, sin API key): perfil de bici para
  bici y patines, a pie para trotar y caminar. La tarjeta muestra el tiempo, la distancia y **a qué
  hora salir** para llegar con 10 minutos de margen, y un botón para **navegar paso a paso** en Google
  Maps. La ubicación no se envía al backend ni se guarda (quedó en el aviso de privacidad, versión
  `2026-09-25.4`). En el navegador, la ubicación solo funciona en `localhost` o con HTTPS; desde un
  celular que abre la app web por `http://192.168…`, el navegador la bloquea. Para un piloto con mucha
  gente conviene montar un OSRM propio.
- **Barrios por comuna**: `BARRIOS_COMUNA` en `backend/app/catalog.py` (barrios de referencia, no la
  lista completa del DAP). Al elegir comuna en el registro o en preferencias, la app muestra abajo
  en pequeño los barrios que cubre; la estación elegida muestra su punto, referencia y barrios cercanos.
- **Foro comunal** (pestaña Foro): mensajes con primer nombre y universidad —lo mismo que ve el
  grupo—, en tres categorías: mis parches, la app y cómo me siento. Cada quien puede borrar solo sus
  mensajes, y todos se borran con el derecho de supresión.

## Racha, clima del domingo y compartir

- **Racha** (`racha_para` en `backend/app/services.py`): los domingos seguidos que la persona ha ido,
  contando hacia atrás desde el último que ya terminó. Un domingo cuenta si en la encuesta dijo que
  fue; si no la respondió, cuenta si había confirmado. Faltar el último domingo la deja en cero,
  pero la app recuerda la mejor racha. En la app es el chip 🔥 de la barra de arriba (al tocarlo
  muestra la mejor racha, el total y el acceso a "Mis domingos"); en Telegram sale desde 2 domingos.
  Al lado va el ícono de Telegram: conectado (punto verde) abre el chat del bot; si no, la hoja para
  conectarlo.
- **Clima del domingo** (`backend/app/clima.py`): el pronóstico por horas de Open-Meteo (gratis, sin
  API key) para el centro de Cali, a la hora del parche: temperatura, probabilidad de lluvia y un
  consejo (impermeable, agua, bloqueador). Se pide una vez por hora y se guarda en memoria; si no hay
  red, la app no lo muestra. También va en el aviso del sábado y en `/parche` de Telegram. Se apaga
  con `CLIMA=0`.
- **Compartir mi parche** (`app/lib/widgets/compartir.dart`): una imagen 4:5 con el logo, el parche,
  la hora, la actividad y la estación, lista para WhatsApp o Instagram con la hoja de compartir del
  teléfono (`share_plus`). No lleva los nombres del grupo: esa imagen puede terminar en cualquier red.

## Diseño: la CicloVida como una vía

**Regla de oro: la interfaz es siempre clara.** No hay modo oscuro ni fondos oscuros; los tonos oscuros
solo van en texto y detalles pequeños.

**Los colores no cambian.** Son los cuatro de las letras V, I, D, A del logo (rojo, coral, verde, teal)
y el gris tinta de "CICLO". Todos salen de tokens en `app/lib/theme.dart` (clase `Cv`), cada uno en
cuatro tonos:

| Tono | Para qué | Ejemplo (teal) |
|---|---|---|
| `marca` | Solo decoración: la cinta, el confeti, los íconos grandes. Nunca texto (da 3:1 sobre blanco). | `#0B9BC4` |
| `Ink` | Texto e íconos con significado, y fondos con texto blanco (AA). | `#06708F` |
| `Soft` | Chips, sellos, tu burbuja del chat. | `#DBF2FA` |
| `brisa` | Bloques de color grandes (5-7 % del color). | `#F0F9FB` |

- **Fondos y bordes.** El fondo de las pantallas es crema: `#FFFAF7`, el coral al 3,5 %. Las tarjetas son
  blancas con sombra suave. Los bordes de los controles son `#85878E`, que da 3,6:1 sobre blanco.
- **Botón principal.** Una píldora con el degradado rojo → coral en tonos `Ink`. Si un botón necesita
  otro color, se usa `botonDeColor()`.

**Tipografía.** Los títulos van en Bricolage Grotesque, en tamaño óptico 96 pt y pesos 700 y 800. El
cuerpo va en Barlow, hasta 700. Los números grandes (horas, días, cifras) también van en Bricolage.

**Medidas.**
- Radios: 12, 16, 24 y 32, y píldora para botones y chips.
- Espaciado: de 4 en 4.
- Sombras: `sombra` (suave), `sombraAlta` y `brillo(color)` para lo protagonista.

**Diseño adaptable.** La app está pensada primero para 375 px:
- En tablet y escritorio, el contenido de lectura se centra con un ancho máximo de 640 px
  (`rellenoAncho`, `MarcoAncho`), y el scroll sigue funcionando en todo el ancho.
- El mapa ocupa toda la pantalla.
- La barra de navegación se centra (máximo 460 px).

**Piezas en `app/lib/widgets/diseno.dart`:**

- **La cinta es un carril.** `FondoCarril` es un fondo claro con la cinta de cuatro colores entrando por
  la derecha y curvándose como una vía, más una línea de carril punteada. Lo usan la bienvenida, el
  cartel del domingo, "Todavía no tienes parche" y la cabecera del parche.
- **El parche es un pase de abordar.**
  - La tarjeta del grupo tiene una cabecera clara en el color de su actividad, con la hora en grande.
  - Debajo va un corte perforado (`Perforacion`), y luego el punto de encuentro y las caras del grupo
    apiladas (`AvatarPila`, solo con el grupo ya armado).
  - Las boletas de la lista llevan su corte con muescas.
- **Cuenta regresiva.** `AnilloCuenta` muestra los días que faltan para el domingo en un anillo con los
  cuatro colores, que se va llenando durante la semana.
- **Momentos que se celebran.** Cuando el match te encuentra parche aparece "¡Match!" con un estallido y
  confeti en los colores de la cinta (`celebrar`). La lista de espera muestra un radar que busca
  (`Radar`).
- **Estados con personalidad.**
  - Al cargar se ve la forma de lo que viene (`Esqueleto`).
  - Los vacíos y los errores llevan un emoji en un círculo suave y un mensaje claro (`EstadoVacio`,
    `TarjetaError`).
- **Toques y movimiento.**
  - Las tarjetas y opciones rebotan un poco al tocarlas (`Rebote`).
  - Los bloques entran escalonados (`Aparecer`).
  - Si el teléfono tiene "reducir movimiento" activado, no hay animaciones.
- **Piezas pequeñas.**
  - `Rotulo`: rótulo en mayúsculas con un trazo de color, como la señalización de la vía.
  - `Sello`: pastillas como "Para ti" o "Va".
  - `IconoBurbuja`: ícono en un círculo suave.
  - `BloqueColor`: bloque de color claro.
  - `BarraInferior`: barra fija abajo (botón de un formulario, redactor del chat o del foro).
  - `RutaPasos`: paradas unidas por una línea punteada.
- **Barra flotante.** La navegación es una píldora blanca. La pestaña activa se tiñe del color de su
  sección: coral para Mi parche, teal para Mapa y verde para Foro.

## Ajustes por la evaluación del mentor

- **Mayoría de edad.** En el registro hay una casilla obligatoria "Declaro que tengo 18 años o más";
  sin marcarla no se puede crear la cuenta, y queda constancia (`declara_mayor`, `declara_mayor_en`)
  de que se preguntó y cuándo se aceptó, igual que con el aviso de privacidad.
- **Menores de edad.** El piloto es para jóvenes de 18 a 28 años (`PERMITIR_MENORES=0`). Si se activa, los de 14 a 17 necesitan el nombre y la autorización de su acudiente, y nunca quedan en un grupo con adultos.
- **Hábeas data (Ley 1581 de 2012).** Aviso de privacidad completo en el registro (`backend/app/privacidad.py`). Se guardan la versión del aviso y la fecha de cada autorización. La pregunta de bienestar es opcional porque puede ser un dato sensible. Cada joven puede borrar sus datos desde Ajustes. El aviso es un borrador: hay que completar los datos entre corchetes y hacerlo revisar antes de un piloto real.
- **Marca.** Ni la app ni el tablero usan el escudo de la Alcaldía. Los dos dicen que son un prototipo y no un canal oficial, y el tablero se presenta como insumo, no como decisión. Tampoco usan el logo de CicloVida (también es de la Alcaldía): llevan uno propio, los tres anillos de bici, patines y trote. Está en `app/assets/img/` (`parche-logo.png` completo, `parche-icono.png` solo los anillos) y en `backend/static/tablero/img/`.
- **Riesgo de encuentros entre desconocidos.** Solo se encuentran en estaciones públicas y en horario de CicloVida. El grupo ve el primer nombre, la actividad y si confirmaste, nada más. Hay un botón "Reportar un problema" con la línea 123 visible. Con 2 reportes de personas distintas, la persona sale del emparejamiento hasta que moderación la revise (`GET /api/admin/reportes`).
- **Filtro de confianza.** Solo entran estudiantes de universidades de Cali, verificados con un código de 6 dígitos enviado a su correo institucional (`@usbcali.edu.co`, `@uao.edu.co`, `@correounivalle.edu.co`, `@javerianacali.edu.co`, `@icesi.edu.co`, `@usc.edu.co` y otros en `backend/app/catalog.py`; se aceptan subdominios). El correo no se guarda: solo su huella HMAC, para que no abra dos cuentas, y el nombre de la universidad, que el grupo ve junto al primer nombre. Sin servidor de correo (`SMTP_HOST` vacío), la API devuelve el código en la respuesta para la demo; en un piloto, `CORREO_DEMO=0`.
- **"Si usa IA, expliquen sus variables."** El agrupamiento usa k-means con ritmo, rango de edad, experiencia y, si la persona lo respondió, su estilo de parche, cada uno con su peso, explicados dentro de la app en Ajustes > Cómo armamos los grupos. `python -m app.reporte` muestra, grupo por grupo, por qué quedaron juntos.

## Cómo se arman los grupos

1. **El sistema abre los parches.** Uno por estación, hora y actividad para cada grupo de edad (132 por domingo). El joven elige; la app le recomienda los de su estación y actividad favoritas.
2. **Nadie queda solo.** El sábado a las 5:00 p. m., quien está en un parche de menos de 3 personas se suma al parche compatible más parecido. Reglas que nunca se relajan: misma estación, menores nunca con mayores, a pie (caminar, trotar) nunca con sobre ruedas (bici, patines), máximo 90 minutos de diferencia. Quien tuvo que ceder algo lo ve escrito en su grupo.
3. **K-means.** Cada parche se parte en grupos de 3 a 6, idealmente 5, con k-means de tamaño balanceado y determinista sobre ritmo (peso 1,0), rango de edad (0,6), experiencia, es decir, domingos que ya fue (0,4), y las cinco respuestas del quiz de estilo (0,2 cada una). Ojo: k-means solo tiene algo que decidir cuando un parche tiene 7 personas o más; con 3 a 6 queda un solo grupo.
4. **Quien llega tarde** se suma al grupo con cupo cuyo centroide está más cerca, o se abre uno nuevo.

Con los 1.500 jóvenes simulados, en el último domingo de la demo hay 1.217 personas en 257 grupos: todas en grupos de 3 a 6, nadie solo, y solo 22 tuvieron que cambiar de hora o actividad. En el domingo abierto, al armar los grupos, quedan 757 personas en 168 grupos, también sin nadie solo. Con los 260 simulados de antes, en ese domingo el 9 % quedaba solo o en pareja y el 35 % tenía que cambiar de hora o actividad.

## Datos simulados y reporte del emparejamiento

- **Los simulados están en un JSON a la vista:** `backend/app/datos/sinteticos.json`, 1.500 jóvenes,
  uno por línea: universidad, edad, comuna, estación, hora, actividad, ritmo, semana en que llegan y
  sus respuestas del quiz tal cual (`{"1": "a", …}`, o `null` si no lo respondieron, como el 30 %).
  Se regenera igualito con `python -m app.sinteticos`, porque usa una semilla fija, y
  `python -m app.seed --reset` lo carga en la base.
- **Cuatro perfiles coherentes:** Parchadito social, Madrugador cumplido, Deportista y Contemplativo.
  Cada perfil tiene sus respuestas típicas del quiz, su ritmo, su hora y sus actividades, con ruido:
  cada respuesta coincide con la típica el 80 % de las veces. El perfil existe solo en los simulados,
  para poder comprobar si k-means junta a gente parecida. Las personas reales nunca tienen perfil.
- **Reporte:** `python -m app.reporte --md reporte.md --json reporte.json`, o `GET /api/admin/emparejamiento`
  con la clave de administración. Muestra cada grupo con sus integrantes, por qué quedaron juntos
  (mismo parche, ritmo, edad, experiencia y respuestas en común) y la distancia de cada persona al
  centro del grupo. De las personas reales no sale ni el nombre ni el quiz. Hay un ejemplo generado
  en [`docs/reporte_emparejamiento.md`](docs/reporte_emparejamiento.md).
- **¿Sirve el quiz?** El reporte rearma los parches que k-means divide, con el quiz, sin el quiz y al
  azar. Con los 1.500 simulados (78 parches, 1.035 personas):

  | Grupos armados… | Afinidad de estilo | Mismo ritmo |
  |---|---|---|
  | al azar | 61,2 % | 60,9 % |
  | sin el quiz | 64,1 % | 81,2 % |
  | con el quiz, `PESO_QUIZ=0.2` (el actual) | 66,0 % | 81,4 % |
  | con el quiz, `PESO_QUIZ=0.5` | 69,0 % | 78,5 % |

  Con el peso actual, el quiz le cambia el grupo a 288 de esas 1.035 personas, pero la afinidad de
  estilo sube apenas 2 puntos: sigue siendo un desempate, como pidió el equipo. Con 0,5 sube 5
  puntos a cambio de 3 puntos menos de grupos con el mismo ritmo. Es una decisión de diseño: se cambia con
  `PESO_QUIZ` y se mide con el mismo reporte.

## Correr la demo

### 1. Backend y tablero (Python 3.10 o más)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # en Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m app.seed --reset         # 1.500 jóvenes simulados (app/datos/sinteticos.json) y 4 domingos pasados, ~15 s
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- Tablero: http://localhost:8000/tablero/ (muestra un aviso de "datos sintéticos" mientras existan)
- API documentada: http://localhost:8000/docs
- Reporte del emparejamiento: `python -m app.reporte` (ver "Datos simulados y reporte del emparejamiento")
- Pruebas: `pytest` (64 pruebas: k-means, correo institucional, flujo completo, anonimato, reportes, permisos, match, bot de Telegram, datos simulados, reporte y chat del parche)

Variables útiles: `ADMIN_KEY` (por defecto `dedsec-demo`), `SECRETO`, `SEMBRAR_AL_INICIAR` (carga los simulados si la base arranca vacía), `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `CORREO_DEMO`, `PERMITIR_MENORES`, `REPORTES_PARA_SUSPENDER`, `K_CONTEO`, `GRUPO_MIN`, `GRUPO_MAX`, `PESO_QUIZ`, `DATABASE_URL`, `ESPERA_MINUTOS`, `TELEGRAM_TOKEN`, `TELEGRAM_BOT`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `FORO_MAX`, `CHAT_MAX_SIMULADOS`, `CHAT_PAUSA_SEG`, `CHAT_CHARLA_SEG`, `CHAT_CHARLA_MAX`, `CLIMA`.

### 2. App Flutter (Flutter 3.38.1 o más)

La carpeta `app/` trae el código, los logos y las fuentes, pero no las carpetas `android/` e `ios/`: se generan con tu versión de Flutter.

```bash
cd app
flutter --version                  # 3.38.1 o más; si no: flutter upgrade
flutter create . --project-name parches_ciclovida --org co.dedsec --platforms android,ios,web
python tool/configurar_plataformas.py
flutter pub get
flutter test
```

`configurar_plataformas.py` agrega los permisos, los receivers de notificaciones programadas y el desugaring que pide `flutter_local_notifications`, y permite `http://` en la red local. Se puede correr varias veces.

Para correrla:

```bash
# Emulador de Android: el computador se ve como 10.0.2.2 y ya viene configurado
flutter run

# Celular físico en la misma Wi-Fi que el computador
flutter run --dart-define=API_URL=http://192.168.1.20:8000

# Navegador, para proyectar (las notificaciones se simulan dentro de la app)
flutter run -d chrome
```

La IP también se puede cambiar dentro de la app: botón "Servidor" en la bienvenida o Ajustes > Dirección del servidor.

Probado con Flutter 3.38.9: `flutter analyze` sin problemas, `flutter test` pasa y la versión web completa el flujo de registro, elección de parche y grupos del sábado contra el backend. Android e iOS no se han probado en un dispositivo.

### 3. Desplegar todo en Vercel

`vercel.json`, en la raíz del repositorio (un nivel arriba de esta carpeta), configura la app Flutter
Web, la API FastAPI, el Cron semanal y el webhook de Telegram en un solo proyecto de Vercel:

| Servicio | Tipo | Qué es | Dirección por defecto |
|---|---|---|---|
| `parches-app` | Sitio estático en Vercel | La app Flutter compilada para web | URL asignada por Vercel |
| `/api/*` | Función Python en Vercel | API FastAPI | La misma URL de la app |
| `/tablero/` | Sitio estático servido por FastAPI | Tablero de la Secretaría | La misma URL de la app |

Pasos:

1. Crea una base PostgreSQL en [Neon](https://neon.tech/) y copia su cadena de conexión.
2. En Vercel: **Add New > Project**, importa el repositorio y deja como raíz la carpeta que contiene
   `vercel.json`. Vercel detectará el build de Flutter y la función Python.
3. En **Settings > Environment Variables**, agrega:
   - `DATABASE_URL`: cadena de conexión de Neon.
   - `SEMBRAR_AL_INICIAR=1`: carga los datos simulados y la cuenta demo.
   - `CRON_SECRET`: secreto aleatorio para proteger el endpoint del Cron.
   - `ADMIN_KEY`: opcional; vacía queda `dedsec-demo`.
   - `TELEGRAM_TOKEN` y `GEMINI_API_KEY`: opcionales.
   - `TELEGRAM_WEBHOOK_SECRET`: opcional, pero recomendado si activas Telegram.
   - `FLUTTER_VERSION=3.38.9`: opcional.
4. Pulsa **Deploy**. La app usará automáticamente la misma URL de Vercel para llamar a `/api`.
   El primer build descarga el SDK de Flutter y puede tardar varios minutos.
5. Si usas Telegram, registra el webhook una sola vez (reemplaza los valores):

   ```text
   https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<PROYECTO>.vercel.app/api/telegram/webhook&secret_token=<SECRETO>
   ```

Cómo queda cada uno:

- **Backend.** Vercel ejecuta FastAPI como función serverless. Los datos viven en PostgreSQL de Neon,
  no en el almacenamiento temporal de Vercel. `vercel.json` ejecuta `/api/cron` cada cinco minutos
  para reemplazar el scheduler permanente.
- **Cuenta demo** para recorrer la app sin registrarse: en la app, "Ya tengo cuenta" con
  `demo@usbcali.edu.co`, "Enviarme el código" y el código que sale en pantalla. Está inscrita en el
  parche con más gente de este domingo y trae cuatro domingos pasados con grupo y encuesta (historial
  y racha con datos). El backend la crea al arrancar (y `python -m app.seed --reset` también), así
  que no hace falta subir `parches.db` al repositorio.
- **Tablero para el reto.** Además de la operación, el tablero muestra lo que pide el reto (recuperar
  el tejido social y subir la participación universitaria): reparto modal (bici, patines, trotar,
  caminar), viajes de ocio de la comuna donde vive cada joven a la estación (matriz origen-destino,
  solo pares con K o más jóvenes), participación por universidad, grupos que mezclan universidades,
  línea base de nuevos y recurrentes, y frases listas para la Secretaría. En el registro hay una
  pregunta opcional, "¿habías ido antes a la CicloVida?", para medir cuántos llegan por primera vez.
  El problema, su tamaño y el valor público se editan en `backend/static/tablero/contexto.js`; una
  cifra solo se muestra si trae su fuente.
- **Match de una.** Si cualquier persona nueva pide un parche sin gente, el backend le suma
  simulados de su misma actividad (los más cercanos en estación, hora y ritmo) y queda inscrita al
  instante; el sábado (o "Armar los grupos" en la app) le sale su grupo. Aplica a todas las
  cuentas y actividades; se apaga con `RELLENAR_CON_SIMULADOS=0`.
- **Telegram.** En Vercel no se usa polling permanente: Telegram envía cada mensaje al webhook
  `/api/telegram/webhook`. El Cron se ocupa del reloj y las notificaciones periódicas.
- **App.** Vercel ejecuta `app/tool/vercel_build.sh`, descarga Flutter 3.38.9 y compila con
  `--dart-define=API_URL=…`. El primer despliegue tarda varios minutos. Con HTTPS, "Cómo llego" sí
  puede pedir la ubicación en el celular. Se puede agregar a la pantalla de inicio como una app.
- **Tablero.** Es la misma carpeta `backend/static/tablero`, servida por FastAPI en `/tablero/`.
  En local también se puede abrir desde el backend en esa ruta.

## Guion de demo (3 minutos)

1. **Registro.** Correo `@usbcali.edu.co` y el código (en la demo aparece en pantalla). Luego nombre, edad, comuna 19, bici, ritmo moderado. Mostrar el aviso de privacidad y la autorización.
2. **Match automático.** Al entrar, la app busca sola un parche con gente y esas mismas características. Con los datos sintéticos hay gente inscrita, así que el match une de una; si se quiere mostrar la espera, registrarse con una actividad y estación sin gente, ver la tarjeta "Buscando tu parche…" (y "Conectar Telegram"), inscribir a otra persona compatible desde otro navegador y ver llegar el aviso. También se puede "Elegir yo mismo": filtrar por estación, hora y actividad, y "Unirme".
2b. **Mapa y foro.** Pestaña Mapa: pines con la gente de cada estación y ficha con sus parches. Pestaña Foro: publicar un mensaje en "Mis parches".
3. **El sábado.** En Mi parche, el chip **Demo** (arriba, junto al historial) abre "Adelanta la semana": tocar "Armar los grupos". Aparece el grupo con punto de encuentro, hora, nombres y universidades. Para mostrar la notificación: Ajustes > Herramientas de demo > "Ver el aviso del sábado".
4. **Confirmar.** "Confirmo, voy". Mostrar "Reportar un problema" y "Cómo armamos los grupos".
5. **El domingo.** De nuevo el chip **Demo**: "Terminar el domingo". Se abre la encuesta de satisfacción de una vez; si se cierra sin responder, queda la tarjeta "¿Cómo te fue…?" arriba en Mi parche y el paso "Responder la encuesta" en la misma hoja.
6. **Tablero.** Recargar http://localhost:8000/tablero/ y elegir la jornada: la respuesta ya está en las cifras, sin ningún nombre.

Si preguntan por qué app y no web: la notificación del sábado en la noche llega justo cuando el joven decide si sale el domingo. Una página web no puede avisarle en ese momento.

## Fuentes de datos

Las 11 estaciones de la CicloVida 2026 salen de El Tiempo y de los boletines de la Alcaldía de Cali: la CicloVida central (Panamericana, El Ingenio, Dorada, La Luna y Metropolitana) y las seis comunitarias (Ciudad de Cali, Sol de Oriente, San Carlos, Las Américas, Torres de Comfandi y Brisas de los Álamos). El horario, de 8:00 a. m. a 1:00 p. m., también es de la Alcaldía. Los puntos de encuentro salen de El País (mayo de 2025) y, para Dorada (Calle 9 con Carrera 66), La Luna (Calle 13 con Autopista Suroriental), Metropolitana (Cementerio Metropolitano del Norte) y Ciudad de Cali (avenida Ciudad de Cali, Carrera 29 con Calle 55), de publicaciones de la Alcaldía. Las coordenadas del mapa son aproximadas (OpenStreetMap) y hay que validarlas con la Secretaría del Deporte.

- https://www.cali.gov.co/boletines/publicaciones/191401/la-sexta-ciclovida-de-2026-llega-el-domingo-para-el-disfrute-de-calenos-y-visitantes/
- https://www.cali.gov.co/boletines/publicaciones/191512/con-58-kilometros-de-bienestar-cali-vivio-una-nueva-jornada-masiva-de-la-ciclovida/
- https://www.elpais.com.co/cali/este-domingo-18-de-mayo-del-2025-hay-ciclovida-en-cali-esto-es-lo-que-debe-saber-1701.html

## Siguiente paso (TRL 4)

- Notificaciones push desde el servidor con Firebase Cloud Messaging, para avisar también cuando alguien se suma tarde a un parche.
- Validar estaciones, coordenadas y horarios con la Secretaría del Deporte y la Recreación.
- Postgres en lugar de SQLite, autenticación real para el tablero y la moderación.
- Revisión legal del aviso de privacidad y definición del responsable del tratamiento.

Fuentes Barlow, Barlow Condensed y Bricolage Grotesque bajo licencia SIL Open Font License. Chart.js y Leaflet bajo licencia MIT.
