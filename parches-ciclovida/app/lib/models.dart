typedef Json = Map<String, dynamic>;

class Opcion {
  const Opcion({required this.id, required this.nombre, this.detalle});

  factory Opcion.fromJson(Json j) => Opcion(
        id: j['id'].toString(),
        nombre: j['nombre'] as String,
        detalle: j['detalle'] as String?,
      );

  final String id;
  final String nombre;
  final String? detalle;
}

/// Quiz "Tu estilo de parche": corto, opcional y sin etiquetas.
/// La app nunca recibe puntajes ni perfiles: solo envía las respuestas una vez.
class QuizOpcion {
  const QuizOpcion({required this.id, required this.texto});

  factory QuizOpcion.fromJson(Json j) => QuizOpcion(id: j['id'] as String, texto: j['texto'] as String);

  final String id;
  final String texto;
}

class QuizPregunta {
  const QuizPregunta({required this.id, required this.texto, required this.opciones});

  factory QuizPregunta.fromJson(Json j) => QuizPregunta(
        id: j['id'] as int,
        texto: j['texto'] as String,
        opciones: (j['opciones'] as List).map((e) => QuizOpcion.fromJson(e as Json)).toList(),
      );

  final int id;
  final String texto;
  final List<QuizOpcion> opciones;
}

class QuizInfo {
  const QuizInfo({required this.titulo, required this.detalle, required this.preguntas});

  factory QuizInfo.fromJson(Json j) => QuizInfo(
        titulo: j['titulo'] as String,
        detalle: j['detalle'] as String,
        preguntas: (j['preguntas'] as List).map((e) => QuizPregunta.fromJson(e as Json)).toList(),
      );

  final String titulo;
  final String detalle;
  final List<QuizPregunta> preguntas;
}

class Comuna {
  const Comuna({required this.id, required this.nombre, this.barrios = const []});

  factory Comuna.fromJson(Json j) => Comuna(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        barrios: j['barrios'] == null ? const [] : (j['barrios'] as List).map((e) => e.toString()).toList(),
      );

  final int id;
  final String nombre;

  /// Barrios de referencia, para que la persona se ubique al elegir.
  final List<String> barrios;

  /// "El Refugio, San Fernando y El Lido", recortado a [maximo] barrios.
  String barriosResumen({int maximo = 3}) {
    if (barrios.isEmpty) return '';
    final lista = barrios.take(maximo).toList();
    final resto = barrios.length - lista.length;
    final base = lista.length == 1 ? lista.first : '${lista.sublist(0, lista.length - 1).join(', ')} y ${lista.last}';
    return resto > 0 ? '$base, entre otros' : base;
  }
}

class Tramo {
  const Tramo({
    required this.id,
    required this.nombre,
    required this.comuna,
    required this.punto,
    required this.referencia,
    this.lat = 0,
    this.lng = 0,
  });

  factory Tramo.fromJson(Json j) => Tramo(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        comuna: j['comuna'] as int,
        punto: j['punto'] as String,
        referencia: j['referencia'] as String,
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String nombre;
  final int comuna;
  final String punto;
  final String referencia;

  /// Coordenadas aproximadas de la estación, para el mapa.
  final double lat;
  final double lng;
}

class Universidad {
  const Universidad({required this.id, required this.nombre, required this.corto, required this.dominios});

  factory Universidad.fromJson(Json j) => Universidad(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        corto: j['corto'] as String,
        dominios: (j['dominios'] as List).map((e) => e.toString()).toList(),
      );

  final String id;
  final String nombre;
  final String corto;
  final List<String> dominios;
}

class Catalogo {
  const Catalogo({
    required this.comunas,
    required this.tramos,
    required this.actividades,
    required this.ritmos,
    required this.franjas,
    required this.rangosEdad,
    required this.inicio,
    required this.fin,
    required this.proximaJornada,
    required this.permiteMenores,
    required this.motivosReporte,
    this.universidades = const [],
    this.foroCategorias = const [],
    this.esperaMinutos = 10,
    this.quiz,
  });

  factory Catalogo.fromJson(Json j) {
    List<Opcion> opciones(String k) =>
        (j[k] as List).map((e) => Opcion.fromJson(e as Json)).toList();
    final jornada = j['jornada'] as Json;
    return Catalogo(
      comunas: (j['comunas'] as List).map((e) => Comuna.fromJson(e as Json)).toList(),
      tramos: (j['tramos'] as List).map((e) => Tramo.fromJson(e as Json)).toList(),
      actividades: opciones('actividades'),
      ritmos: opciones('ritmos'),
      franjas: opciones('franjas'),
      rangosEdad: opciones('rangos_edad'),
      inicio: jornada['inicio'] as String,
      fin: jornada['fin'] as String,
      proximaJornada: j['proxima_jornada'] as String,
      permiteMenores: j['permite_menores'] as bool? ?? false,
      motivosReporte: j['motivos_reporte'] == null ? const <Opcion>[] : opciones('motivos_reporte'),
      universidades: j['universidades'] == null
          ? const <Universidad>[]
          : (j['universidades'] as List).map((e) => Universidad.fromJson(e as Json)).toList(),
      foroCategorias: j['foro_categorias'] == null ? const <Opcion>[] : opciones('foro_categorias'),
      esperaMinutos: j['espera_minutos'] as int? ?? 10,
      quiz: j['quiz'] == null ? null : QuizInfo.fromJson(j['quiz'] as Json),
    );
  }

  final List<Comuna> comunas;
  final List<Tramo> tramos;
  final List<Opcion> actividades;
  final List<Opcion> ritmos;
  final List<Opcion> franjas;
  final List<Opcion> rangosEdad;
  final String inicio;
  final String fin;
  final String proximaJornada;
  final bool permiteMenores;
  final List<Opcion> motivosReporte;
  final List<Universidad> universidades;
  final List<Opcion> foroCategorias;

  /// Minutos en espera antes de que la app muestre parches parecidos.
  final int esperaMinutos;
  final QuizInfo? quiz;

  Tramo? tramo(String id) {
    for (final t in tramos) {
      if (t.id == id) return t;
    }
    return null;
  }

  Comuna? comuna(int id) {
    for (final c in comunas) {
      if (c.id == id) return c;
    }
    return null;
  }

  String nombreDe(List<Opcion> lista, String id) {
    for (final o in lista) {
      if (o.id == id) return o.nombre;
    }
    return id;
  }
}

class Perfil {
  const Perfil({
    required this.id,
    required this.nombre,
    required this.rangoEdad,
    required this.comuna,
    required this.actividad,
    required this.ritmo,
    this.universidad = '',
    this.tramoId,
    this.franja,
    this.pausaFecha,
    this.quizRespondido = false,
  });

  factory Perfil.fromJson(Json j) => Perfil(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        universidad: j['universidad'] as String? ?? '',
        rangoEdad: j['rango_edad'] as String,
        comuna: j['comuna'] as int,
        tramoId: j['tramo_id'] as String?,
        franja: j['franja'] as String?,
        actividad: j['actividad'] as String,
        ritmo: j['ritmo'] as String,
        pausaFecha: j['pausa_fecha'] as String?,
        quizRespondido: j['quiz_respondido'] as bool? ?? false,
      );

  final String id;
  final String nombre;

  /// Verificada con el correo institucional.
  final String universidad;
  final String rangoEdad;
  final int comuna;

  /// Estación favorita: solo sirve para recomendar parches.
  final String? tramoId;

  /// Hora preferida (null = cualquiera). El match la usa como característica.
  final String? franja;
  final String actividad;
  final String ritmo;
  final String? pausaFecha;

  /// Solo si ya respondió el quiz de estilo; las respuestas nunca llegan a la app.
  final bool quizRespondido;
}

/// Un parche de la lista que genera el sistema. Solo cifras, nunca nombres.
class ParcheOpcion {
  const ParcheOpcion({
    required this.id,
    required this.nombre,
    required this.tramoId,
    required this.tramoNombre,
    required this.puntoEncuentro,
    required this.horaEncuentro,
    required this.horaNombre,
    required this.actividad,
    required this.actividadNombre,
    required this.inscritos,
    required this.esMio,
    required this.paraTi,
    this.referencia = '',
    this.universidades = 0,
    this.ritmoNombre,
  });

  factory ParcheOpcion.fromJson(Json j) {
    final tramo = j['tramo'] as Json;
    return ParcheOpcion(
      id: j['id'] as int,
      nombre: j['nombre'] as String,
      tramoId: tramo['id'] as String,
      tramoNombre: tramo['nombre'] as String,
      puntoEncuentro: j['punto_encuentro'] as String,
      referencia: j['referencia'] as String? ?? '',
      horaEncuentro: j['hora_encuentro'] as String,
      horaNombre: j['hora_nombre'] as String,
      actividad: j['actividad'] as String,
      actividadNombre: j['actividad_nombre'] as String,
      inscritos: j['inscritos'] as int,
      universidades: j['universidades'] as int? ?? 0,
      esMio: j['es_mio'] as bool,
      paraTi: j['para_ti'] as bool,
      ritmoNombre: j['ritmo_nombre'] as String?,
    );
  }

  final int id;
  final String nombre;
  final String tramoId;
  final String tramoNombre;
  final String puntoEncuentro;

  /// Referencia del punto de encuentro ("Canchas Panamericanas").
  final String referencia;
  final String horaEncuentro;
  final String horaNombre;
  final String actividad;
  final String actividadNombre;
  final int inscritos;

  /// De cuántas universidades distintas es la gente inscrita.
  final int universidades;
  final bool esMio;
  final bool paraTi;

  /// El ritmo más común entre quienes ya se unieron, si hay alguien.
  final String? ritmoNombre;
}

class Miembro {
  const Miembro({
    required this.ref,
    required this.nombre,
    required this.actividad,
    required this.estado,
    required this.soyYo,
    this.universidad = '',
  });

  factory Miembro.fromJson(Json j) => Miembro(
        ref: j['ref'] as int,
        nombre: j['nombre'] as String,
        universidad: j['universidad'] as String? ?? '',
        actividad: j['actividad'] as String,
        estado: j['estado'] as String,
        soyYo: j['soy_yo'] as bool,
      );

  /// Referencia opaca para reportar. No identifica a la persona fuera del parche.
  final int ref;
  final String nombre;

  /// Nombre corto de su universidad (estudiante verificado).
  final String universidad;
  final String actividad;

  /// pendiente | confirmado | declinado
  final String estado;
  final bool soyYo;
}

class Grupo {
  const Grupo({
    required this.id,
    required this.nombre,
    required this.tramoNombre,
    required this.tramoComuna,
    required this.puntoEncuentro,
    required this.referencia,
    required this.horaEncuentro,
    required this.horaNombre,
    required this.actividad,
    required this.actividadNombre,
    required this.ritmo,
    required this.ritmoNombre,
    required this.miembros,
    required this.confirmados,
  });

  factory Grupo.fromJson(Json j) {
    final tramo = j['tramo'] as Json;
    return Grupo(
      id: j['id'] as int,
      nombre: j['nombre'] as String,
      tramoNombre: tramo['nombre'] as String,
      tramoComuna: tramo['comuna'] as int,
      puntoEncuentro: j['punto_encuentro'] as String,
      referencia: j['referencia'] as String,
      horaEncuentro: j['hora_encuentro'] as String,
      horaNombre: j['hora_nombre'] as String,
      actividad: j['actividad'] as String,
      actividadNombre: j['actividad_nombre'] as String,
      ritmo: j['ritmo'] as String,
      ritmoNombre: j['ritmo_nombre'] as String,
      miembros: (j['miembros'] as List).map((e) => Miembro.fromJson(e as Json)).toList(),
      confirmados: j['confirmados'] as int,
    );
  }

  final int id;
  final String nombre;
  final String tramoNombre;
  final int tramoComuna;
  final String puntoEncuentro;
  final String referencia;
  final String horaEncuentro;
  final String horaNombre;
  final String actividad;
  final String actividadNombre;
  final String ritmo;
  final String ritmoNombre;
  final List<Miembro> miembros;
  final int confirmados;
}

/// Un domingo pasado: a qué parche fue y con quién.
class HistorialItem {
  const HistorialItem({
    required this.fecha,
    required this.miRespuesta,
    required this.grupo,
    this.asistio,
    this.volveria,
  });

  factory HistorialItem.fromJson(Json j) => HistorialItem(
        fecha: j['fecha'] as String,
        miRespuesta: j['mi_respuesta'] as String? ?? 'pendiente',
        asistio: j['asistio'] as bool?,
        volveria: j['volveria'] as bool?,
        grupo: Grupo.fromJson(j['grupo'] as Json),
      );

  final String fecha;
  final String miRespuesta;

  /// null = no respondió la encuesta de esa semana.
  final bool? asistio;
  final bool? volveria;
  final Grupo grupo;
}

class EncuestaInfo {
  const EncuestaInfo({required this.jornadaFecha, required this.respondida, this.grupoNombre});

  factory EncuestaInfo.fromJson(Json j) => EncuestaInfo(
        jornadaFecha: j['jornada_fecha'] as String,
        grupoNombre: j['grupo_nombre'] as String?,
        respondida: j['respondida'] as bool,
      );

  final String jornadaFecha;
  final String? grupoNombre;
  final bool respondida;
}

/// Lista de espera del emparejamiento automático: aún no hay parche con gente compatible.
class EsperaInfo {
  const EsperaInfo._({
    required this.desde,
    required this.minutos,
    required this.minutosParaSugerencias,
    required this.sugerencias,
    this.masParecido,
  });

  factory EsperaInfo.fromJson(Json j) => EsperaInfo._(
        desde: j['desde'] as String,
        minutos: j['minutos'] as int,
        minutosParaSugerencias: j['minutos_para_sugerencias'] as int? ?? 10,
        masParecido: j['mas_parecido'] == null ? null : ParcheOpcion.fromJson(j['mas_parecido'] as Json),
        sugerencias: j['sugerencias'] == null
            ? const <ParcheOpcion>[]
            : (j['sugerencias'] as List).map((e) => ParcheOpcion.fromJson(e as Json)).toList(),
      );

  final String desde;
  final int minutos;
  final int minutosParaSugerencias;

  /// El parche más parecido aunque no tenga gente: para quien toma la iniciativa.
  final ParcheOpcion? masParecido;

  /// Parches parecidos, solo después del lapso de espera.
  final List<ParcheOpcion> sugerencias;
}

class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.leida,
    required this.creadoEn,
  });

  factory NotificacionApp.fromJson(Json j) => NotificacionApp(
        id: j['id'] as int,
        titulo: j['titulo'] as String,
        cuerpo: j['cuerpo'] as String,
        leida: j['leida'] as bool,
        creadoEn: j['creado_en'] as String,
      );

  final int id;
  final String titulo;
  final String cuerpo;
  final bool leida;
  final String creadoEn;
}

/// Mensaje del foro comunal: primer nombre y universidad, igual que en el grupo.
class MensajeForo {
  const MensajeForo({
    required this.id,
    required this.nombre,
    required this.universidad,
    required this.categoria,
    required this.texto,
    required this.creadoEn,
    required this.esMio,
  });

  factory MensajeForo.fromJson(Json j) => MensajeForo(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        universidad: j['universidad'] as String,
        categoria: j['categoria'] as String,
        texto: j['texto'] as String,
        creadoEn: j['creado_en'] as String,
        esMio: j['es_mio'] as bool? ?? false,
      );

  final int id;
  final String nombre;
  final String universidad;
  final String categoria;
  final String texto;
  final String creadoEn;
  final bool esMio;
}

/// Mensaje del chat del parche. `simulado`: lo escribió un estudiante simulado de la demo (IA).
class ChatMensaje {
  const ChatMensaje({
    required this.id,
    required this.nombre,
    required this.universidad,
    required this.simulado,
    required this.texto,
    required this.creadoEn,
    required this.esMio,
    this.respondeA,
  });

  factory ChatMensaje.fromJson(Json j) => ChatMensaje(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        universidad: j['universidad'] as String? ?? '',
        simulado: j['simulado'] as bool? ?? false,
        respondeA: j['responde_a'] as String?,
        texto: j['texto'] as String,
        creadoEn: j['creado_en'] as String,
        esMio: j['es_mio'] as bool? ?? false,
      );

  final int id;
  final String nombre;
  final String universidad;
  final bool simulado;

  /// Primer nombre de a quién le contesta (otra persona del chat), si le habla a alguien en particular.
  final String? respondeA;
  final String texto;
  final String creadoEn;
  final bool esMio;
}

class ChatMiembro {
  const ChatMiembro({required this.nombre, required this.universidad, required this.simulado, required this.soyYo});

  factory ChatMiembro.fromJson(Json j) => ChatMiembro(
        nombre: j['nombre'] as String,
        universidad: j['universidad'] as String? ?? '',
        simulado: j['simulado'] as bool? ?? false,
        soyYo: j['soy_yo'] as bool? ?? false,
      );

  final String nombre;
  final String universidad;
  final bool simulado;
  final bool soyYo;
}

/// El chat del parche. Sin unirse, el servidor solo dice cuántos hay: ni nombres ni mensajes.
class ChatEstado {
  const ChatEstado({
    required this.disponible,
    required this.unido,
    this.parcheId,
    this.parcheNombre = '',
    this.estacion = '',
    this.hora = '',
    this.actividad = '',
    this.enElChat = 0,
    this.miembros = const [],
    this.mensajes = const [],
    this.escribiendo = const [],
    this.simuladosConversan = false,
  });

  factory ChatEstado.fromJson(Json j) {
    final p = j['parche'] as Json?;
    return ChatEstado(
      disponible: j['disponible'] as bool? ?? false,
      unido: j['unido'] as bool? ?? false,
      parcheId: p?['id'] as int?,
      parcheNombre: p?['nombre'] as String? ?? '',
      estacion: p?['estacion'] as String? ?? '',
      hora: p?['hora'] as String? ?? '',
      actividad: p?['actividad'] as String? ?? '',
      enElChat: j['en_el_chat'] as int? ?? 0,
      miembros: (j['miembros'] as List? ?? const []).map((e) => ChatMiembro.fromJson(e as Json)).toList(),
      mensajes: (j['mensajes'] as List? ?? const []).map((e) => ChatMensaje.fromJson(e as Json)).toList(),
      escribiendo: (j['escribiendo'] as List? ?? const []).map((e) => e.toString()).toList(),
      simuladosConversan: j['simulados_conversan'] as bool? ?? false,
    );
  }

  final bool disponible;
  final bool unido;
  final int? parcheId;
  final String parcheNombre;
  final String estacion;
  final String hora;
  final String actividad;
  final int enElChat;
  final List<ChatMiembro> miembros;
  final List<ChatMensaje> mensajes;

  /// Quién está escribiendo ("Alguien" mientras los simulados piensan su respuesta).
  final List<String> escribiendo;

  /// Si los simulados conversan con Gemini (si no, solo saludan).
  final bool simuladosConversan;
}

/// Vínculo con el bot de Telegram para recibir el aviso del match.
class TelegramInfo {
  const TelegramInfo({
    required this.disponible,
    required this.vinculado,
    this.enlace,
    this.enlaceWeb,
    this.codigo,
    this.bot,
  });

  factory TelegramInfo.fromJson(Json j) => TelegramInfo(
        disponible: j['disponible'] as bool,
        vinculado: j['vinculado'] as bool,
        enlace: j['enlace'] as String?,
        enlaceWeb: j['enlace_web'] as String?,
        codigo: j['codigo'] as String?,
        bot: j['bot'] as String?,
      );

  final bool disponible;
  final bool vinculado;

  /// t.me: abre la app de Telegram.
  final String? enlace;

  /// Telegram Web con el código incluido: para cuando la app corre en el navegador.
  final String? enlaceWeb;

  /// Respaldo: se le envía al bot a mano como "/start <código>".
  final String? codigo;
  final String? bot;
}

class EstadoParche {
  const EstadoParche({
    required this.jornadaFecha,
    required this.jornadaEstado,
    required this.inicio,
    required this.fin,
    required this.estado,
    required this.ajustes,
    required this.tarde,
    this.miRespuesta,
    this.salida,
    this.grupo,
    this.encuesta,
    this.espera,
    this.clima,
    this.racha = Racha.vacia,
  });

  factory EstadoParche.fromJson(Json j) {
    final jornada = j['jornada'] as Json;
    return EstadoParche(
      jornadaFecha: jornada['fecha'] as String,
      jornadaEstado: jornada['estado'] as String,
      inicio: jornada['inicio'] as String,
      fin: jornada['fin'] as String,
      estado: j['estado'] as String,
      miRespuesta: j['mi_respuesta'] as String?,
      ajustes: (j['ajustes'] as List).map((e) => e.toString()).toList(),
      tarde: j['tarde'] as bool? ?? false,
      salida: j['salida'] == null ? null : ParcheOpcion.fromJson(j['salida'] as Json),
      grupo: j['grupo'] == null ? null : Grupo.fromJson(j['grupo'] as Json),
      encuesta: j['encuesta'] == null ? null : EncuestaInfo.fromJson(j['encuesta'] as Json),
      espera: j['espera'] == null ? null : EsperaInfo.fromJson(j['espera'] as Json),
      clima: j['clima'] == null ? null : Clima.fromJson(j['clima'] as Json),
      racha: j['racha'] == null ? Racha.vacia : Racha.fromJson(j['racha'] as Json),
    );
  }

  final String jornadaFecha;
  final String jornadaEstado;
  final String inicio;
  final String fin;

  /// sin_parche | en_espera (el match busca por él) | inscrito (el grupo se arma el sábado) |
  /// asignado | pausado | suspendido
  final String estado;

  /// pendiente | confirmado | declinado (solo si está asignado)
  final String? miRespuesta;
  final List<String> ajustes;
  final bool tarde;

  /// El parche que eligió de la lista.
  final ParcheOpcion? salida;

  /// Su grupo de 3 a 6 dentro del parche, desde el sábado.
  final Grupo? grupo;
  final EncuestaInfo? encuesta;

  /// Solo cuando el estado es en_espera.
  final EsperaInfo? espera;

  /// Pronóstico del domingo a la hora del parche (o al abrir la CicloVida). Null si no hay.
  final Clima? clima;
  final Racha racha;

  bool get encuestaPendiente => encuesta != null && !encuesta!.respondida;
}

/// El clima del domingo a una hora, de Open-Meteo.
class Clima {
  const Clima({
    required this.hora,
    required this.temperatura,
    required this.lluvia,
    required this.cielo,
    required this.icono,
    required this.consejo,
  });

  factory Clima.fromJson(Json j) => Clima(
        hora: j['hora'] as String,
        temperatura: (j['temperatura'] as num).round(),
        lluvia: (j['lluvia'] as num).round(),
        cielo: j['cielo'] as String,
        icono: j['icono'] as String,
        consejo: j['consejo'] as String,
      );

  final String hora;
  final int temperatura;

  /// Probabilidad de lluvia, de 0 a 100.
  final int lluvia;
  final String cielo;

  /// sol | nubes_sol | nubes | lluvia | tormenta
  final String icono;
  final String consejo;
}

/// Domingos seguidos que ha ido a su parche.
class Racha {
  const Racha({required this.actual, required this.mejor, required this.total});

  factory Racha.fromJson(Json j) =>
      Racha(actual: j['actual'] as int, mejor: j['mejor'] as int, total: j['total'] as int);

  static const vacia = Racha(actual: 0, mejor: 0, total: 0);

  final int actual;
  final int mejor;
  final int total;
}

class SeccionAviso {
  const SeccionAviso(this.titulo, this.texto);

  final String titulo;
  final String texto;
}

class AvisoPrivacidad {
  const AvisoPrivacidad({required this.version, required this.titulo, required this.secciones});

  factory AvisoPrivacidad.fromJson(Json j) => AvisoPrivacidad(
        version: j['version'] as String,
        titulo: j['titulo'] as String,
        secciones: (j['secciones'] as List).map((e) {
          final m = e as Json;
          return SeccionAviso(m['titulo'] as String, m['texto'] as String);
        }).toList(),
      );

  final String version;
  final String titulo;
  final List<SeccionAviso> secciones;
}
