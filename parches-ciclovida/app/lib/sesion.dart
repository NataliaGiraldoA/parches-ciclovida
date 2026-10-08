import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';

/// Guarda el token del joven y la dirección del servidor en el teléfono.
class Sesion {
  Sesion._(this._prefs)
      : api = Api(
          baseUrl: _prefs.getString(_kUrl) ?? apiUrlPorDefecto(),
          token: _prefs.getString(_kToken),
        );

  static const _kToken = 'token';
  static const _kUrl = 'api_url';
  static const _kClave = 'clave_admin';
  static const _kChatDescartado = 'chat_descartado';

  static late Sesion actual;

  final SharedPreferences _prefs;
  final Api api;

  static Future<Sesion> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    actual = Sesion._(prefs);
    return actual;
  }

  bool get registrado => api.token != null;

  /// Recién registrado: al llegar al inicio, el match automático lo une a un parche. Solo esa vez
  /// (en memoria): al terminar un domingo o al volver a abrir la app, la persona decide con los botones.
  bool matchPendiente = false;

  String get apiUrl => api.baseUrl;

  String get claveAdmin => _prefs.getString(_kClave) ?? kClaveAdminPorDefecto;

  Future<void> guardarToken(String token) async {
    api.token = token;
    await _prefs.setString(_kToken, token);
  }

  Future<void> cerrar() async {
    api.token = null;
    await _prefs.remove(_kToken);
  }

  Future<void> cambiarUrl(String url) async {
    api.baseUrl = url.trim();
    await _prefs.setString(_kUrl, api.baseUrl);
  }

  Future<void> guardarClave(String clave) async {
    await _prefs.setString(_kClave, clave.trim());
  }

  /// "Ahora no" a la invitación al chat de un parche: no se vuelve a insistir en ese parche.
  bool chatDescartado(int parcheId) => _prefs.getInt(_kChatDescartado) == parcheId;

  Future<void> descartarChat(int parcheId) async {
    await _prefs.setInt(_kChatDescartado, parcheId);
  }
}
