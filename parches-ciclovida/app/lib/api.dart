import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.mensaje, {this.status});

  final String mensaje;
  final int? status;

  bool get sesionInvalida => status == 401;

  @override
  String toString() => mensaje;
}

class RegistroResultado {
  const RegistroResultado(this.token, this.perfil);

  final String token;
  final Perfil perfil;
}

/// Cliente del backend FastAPI (ver backend/app/main.py).
class Api {
  Api({required this.baseUrl, this.token});

  String baseUrl;
  String? token;

  final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path, Map<String, String>? query) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    Map<String, String>? query,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      // Siempre UTF-8 explícito: así las tildes y las eñes llegan bien al backend
      // sin depender de la codificación por defecto del cliente HTTP.
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final t = token;
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    if (headers != null) req.headers.addAll(headers);

    final http.Response res;
    try {
      final streamed = await _client.send(req).timeout(_timeout);
      res = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('El servidor no respondió a tiempo. Revisa tu conexión.');
    } catch (_) {
      throw ApiException('No pudimos conectarnos con el servidor ($baseUrl).');
    }

    dynamic data;
    final texto = utf8.decode(res.bodyBytes);
    if (texto.isNotEmpty) {
      try {
        data = jsonDecode(texto);
      } on FormatException {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw ApiException(_mensajeError(data, res.statusCode), status: res.statusCode);
  }

  static String _mensajeError(dynamic data, int status) {
    if (data is Map && data['detail'] != null) {
      final detalle = data['detail'];
      if (detalle is String) return detalle;
      if (detalle is List && detalle.isNotEmpty && detalle.first is Map) {
        final msg = (detalle.first as Map)['msg']?.toString() ?? '';
        if (msg.isNotEmpty) return msg.replaceFirst('Value error, ', '');
      }
    }
    if (status == 401) return 'Tu sesión ya no es válida. Vuelve a registrarte.';
    return 'Algo salió mal (error $status).';
  }

  Future<Json> _json(String method, String path, {Object? body, Map<String, String>? headers, Map<String, String>? query}) async {
    final data = await _send(method, path, body: body, headers: headers, query: query);
    return data as Json;
  }

  // ------------------------------------------------------------ joven

  Future<Catalogo> catalogo() async => Catalogo.fromJson(await _json('GET', '/api/catalogo'));

  Future<RegistroResultado> registrar(Json datos) async {
    final j = await _json('POST', '/api/jovenes', body: datos);
    return RegistroResultado(j['token'] as String, Perfil.fromJson(j['joven'] as Json));
  }

  Future<Perfil> yo() async => Perfil.fromJson(await _json('GET', '/api/yo'));

  Future<Perfil> cambiar(Json cambios) async => Perfil.fromJson(await _json('PATCH', '/api/yo', body: cambios));

  Future<EstadoParche> miParche() async => EstadoParche.fromJson(await _json('GET', '/api/yo/parche'));

  /// Los domingos pasados: a qué parche fue y con quién.
  Future<List<HistorialItem>> historial() async {
    final data = await _send('GET', '/api/yo/historial');
    return (data as List).map((e) => HistorialItem.fromJson(e as Json)).toList();
  }

  Future<List<ParcheOpcion>> parches({String? tramo, String? franja, String? actividad}) async {
    final query = <String, String>{
      'tramo': ?tramo,
      'franja': ?franja,
      'actividad': ?actividad,
    };
    final j = await _json('GET', '/api/parches', query: query.isEmpty ? null : query);
    return (j['parches'] as List).map((e) => ParcheOpcion.fromJson(e as Json)).toList();
  }

  Future<EstadoParche> unirme(int parcheId) async =>
      EstadoParche.fromJson(await _json('POST', '/api/yo/parche', body: {'parche_id': parcheId}));

  /// Pide el código al correo institucional. En la demo, sin servidor de correo, lo devuelve.
  /// [para] es 'registro' (cuenta nueva) o 'ingreso' (volver a entrar).
  Future<({String universidad, String? codigoDemo})> pedirCodigo(String correo, {String para = 'registro'}) async {
    final j = await _json('POST', '/api/verificacion', body: {'correo': correo, 'para': para});
    return (universidad: j['universidad'] as String, codigoDemo: j['codigo_demo'] as String?);
  }

  /// Volver a entrar con el mismo correo institucional y un código nuevo.
  Future<RegistroResultado> ingresar({required String correo, required String codigo}) async {
    final j = await _json('POST', '/api/sesiones', body: {'correo': correo, 'codigo': codigo});
    return RegistroResultado(j['token'] as String, Perfil.fromJson(j['joven'] as Json));
  }

  Future<EstadoParche> salirme() async => EstadoParche.fromJson(await _json('DELETE', '/api/yo/parche'));

  /// Emparejamiento automático: une al parche con gente y mis mismas características,
  /// o me deja en lista de espera.
  Future<EstadoParche> buscarMatch() async => EstadoParche.fromJson(await _json('POST', '/api/yo/match'));

  Future<EstadoParche> cancelarEspera() async => EstadoParche.fromJson(await _json('DELETE', '/api/yo/espera'));

  Future<List<NotificacionApp>> notificaciones() async {
    final data = await _send('GET', '/api/yo/notificaciones');
    return (data as List).map((e) => NotificacionApp.fromJson(e as Json)).toList();
  }

  Future<void> marcarNotificacionesLeidas() async {
    await _send('POST', '/api/yo/notificaciones/leidas');
  }

  Future<TelegramInfo> telegram() async => TelegramInfo.fromJson(await _json('GET', '/api/yo/telegram'));

  /// Suelta el chat de Telegram de esta cuenta (para conectarlo a otra, por ejemplo en la demo).
  Future<void> desconectarTelegram() async {
    await _send('DELETE', '/api/yo/telegram');
  }

  /// Envía el quiz "Tu estilo de parche". El servidor no devuelve puntajes ni etiquetas.
  Future<String> responderQuiz(Map<int, String> respuestas) async {
    final j = await _json('POST', '/api/yo/quiz', body: {
      'respuestas': respuestas.map((k, v) => MapEntry(k.toString(), v)),
    });
    return j['mensaje'] as String? ?? '¡Listo!';
  }

  // ------------------------------------------------------------ chat del parche (opcional)

  /// Con [despuesDe], solo los mensajes nuevos (para consultar cada pocos segundos).
  Future<ChatEstado> chat({int? despuesDe}) async => ChatEstado.fromJson(
      await _json('GET', '/api/yo/chat', query: despuesDe == null ? null : {'despues_de': '$despuesDe'}));

  Future<ChatEstado> chatUnirme() async => ChatEstado.fromJson(await _json('POST', '/api/yo/chat/unirme'));

  Future<ChatEstado> chatSalir() async => ChatEstado.fromJson(await _json('DELETE', '/api/yo/chat'));

  Future<ChatMensaje> chatEscribir(String texto) async =>
      ChatMensaje.fromJson(await _json('POST', '/api/yo/chat/mensajes', body: {'texto': texto}));

  // ------------------------------------------------------------ foro comunal

  Future<List<MensajeForo>> foro({String? categoria}) async {
    final data = await _send('GET', '/api/foro', query: categoria == null ? null : {'categoria': categoria});
    return (data as List).map((e) => MensajeForo.fromJson(e as Json)).toList();
  }

  Future<MensajeForo> foroPublicar({required String categoria, required String texto}) async =>
      MensajeForo.fromJson(await _json('POST', '/api/foro', body: {'categoria': categoria, 'texto': texto}));

  Future<void> foroBorrar(int id) async {
    await _send('DELETE', '/api/foro/$id');
  }

  Future<EstadoParche> responder({required bool va}) async =>
      EstadoParche.fromJson(await _json('POST', '/api/yo/parche/respuesta', body: {'va': va}));

  Future<EstadoParche> enviarEncuesta({required bool asistio, required bool volveria, int? bienestar}) async =>
      EstadoParche.fromJson(await _json('POST', '/api/yo/encuesta', body: {
        'asistio': asistio,
        'volveria': volveria,
        'bienestar': bienestar,
      }));

  Future<AvisoPrivacidad> avisoPrivacidad() async => AvisoPrivacidad.fromJson(await _json('GET', '/api/aviso-privacidad'));

  Future<String> reportar({required int grupoId, required String motivo, int? ref, String detalle = ''}) async {
    final j = await _json('POST', '/api/yo/reportes', body: {
      'grupo_id': grupoId,
      'motivo': motivo,
      'ref': ref,
      'detalle': detalle,
    });
    return j['mensaje'] as String? ?? 'Recibimos tu reporte.';
  }

  Future<void> borrarMisDatos() async {
    await _send('DELETE', '/api/yo');
  }

  // ------------------------------------------------------------ demo

  Future<Json> adminArmarGrupos(String clave) =>
      _json('POST', '/api/admin/armar-grupos', headers: {'X-Admin-Key': clave});

  Future<Json> adminFinalizar(String clave) => _json('POST', '/api/admin/finalizar', headers: {'X-Admin-Key': clave});
}
