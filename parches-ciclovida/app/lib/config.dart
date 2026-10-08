import 'package:flutter/foundation.dart';

/// Dirección del backend. Se puede fijar al compilar:
///   flutter run --dart-define=API_URL=http://192.168.1.20:8000
/// o cambiar dentro de la app en Ajustes > Herramientas de demo.
const String kApiUrlCompilada = String.fromEnvironment('API_URL');

String apiUrlPorDefecto() {
  if (kApiUrlCompilada.isNotEmpty) return kApiUrlCompilada;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000'; // el computador visto desde el emulador de Android
  }
  return 'http://localhost:8000';
}

/// Muestra el chip "Demo" en Mi parche para adelantar la semana (armar grupos, terminar el domingo y
/// abrir la encuesta). Para una versión sin atajos: flutter run --dart-define=DEMO=false
const bool kModoDemo = bool.fromEnvironment('DEMO', defaultValue: true);

/// Cuenta pública para recorrer la app sin registrarse. La crea el backend al arrancar
/// (backend/app/seed.py, DEMO_CORREO): este correo tiene que ser el mismo.
const String kCorreoDemo = 'demo@usbcali.edu.co';

/// Clave de las acciones de demo (armar parches, cerrar jornada). Debe coincidir con ADMIN_KEY del backend.
const String kClaveAdminPorDefecto = 'dedsec-demo';

/// Horarios de los avisos semanales (hora de Cali).
const int kAvisoSabadoHora = 19;
const int kAvisoSabadoMinuto = 0;
const int kAvisoDomingoHora = 13;
const int kAvisoDomingoMinuto = 30;
