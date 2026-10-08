import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'config.dart';
import 'theme.dart';
import 'widgets/diseno.dart';

/// Qué abrir cuando alguien toca una notificación.
class Toque {
  const Toque(this.payload);

  /// 'confirmar' (aviso del sábado) o 'encuesta' (aviso del domingo)
  final String payload;
}

class Aviso {
  const Aviso({required this.id, required this.titulo, required this.cuerpo, required this.payload});

  final int id;
  final String titulo;
  final String cuerpo;
  final String payload;
}

const avisoSabado = Aviso(
  id: 1,
  titulo: 'Tu grupo para mañana está listo',
  cuerpo: 'Mira quiénes van contigo a la CicloVida y confirma si vas.',
  payload: 'confirmar',
);

const avisoDomingo = Aviso(
  id: 2,
  titulo: '¿Cómo te fue en la CicloVida?',
  cuerpo: 'Son tres preguntas. Nos ayudan a armar mejores parches.',
  payload: 'encuesta',
);

/// Notificaciones locales programadas cada semana en el teléfono.
///
/// El sábado a las 7:00 p. m. (el momento en que se decide si se sale el
/// domingo) y el domingo a la 1:30 p. m., cuando termina la jornada.
/// En web no hay notificaciones programadas: la app muestra un aviso simulado.
class Notificaciones {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static final ValueNotifier<Toque?> tocada = ValueNotifier<Toque?>(null);
  static bool _listo = false;

  static bool get soportadas =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static const NotificationDetails _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'parche_semanal',
      'Tu parche del domingo',
      channelDescription: 'Aviso del sábado con tu parche y encuesta del domingo',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> iniciar() async {
    if (!soportadas) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Bogota'));
      const ajustes = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings: ajustes,
        onDidReceiveNotificationResponse: (respuesta) {
          final p = respuesta.payload;
          if (p != null) tocada.value = Toque(p);
        },
      );
      final lanzamiento = await _plugin.getNotificationAppLaunchDetails();
      final p = lanzamiento?.notificationResponse?.payload;
      if ((lanzamiento?.didNotificationLaunchApp ?? false) && p != null) {
        tocada.value = Toque(p);
      }
      _listo = true;
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  static Future<bool> pedirPermiso() async {
    if (!_listo) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('No se pudo pedir permiso: $e');
      return false;
    }
  }

  /// Próxima fecha con ese día de la semana y hora, en hora de Cali.
  static tz.TZDateTime proxima(int diaSemana, int hora, int minuto) {
    final ahora = tz.TZDateTime.now(tz.local);
    var fecha = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day, hora, minuto);
    while (fecha.weekday != diaSemana || !fecha.isAfter(ahora)) {
      fecha = fecha.add(const Duration(days: 1));
    }
    return fecha;
  }

  static Future<void> programarSemana() async {
    if (!_listo) return;
    try {
      await _programar(avisoSabado, DateTime.saturday, kAvisoSabadoHora, kAvisoSabadoMinuto);
      await _programar(avisoDomingo, DateTime.sunday, kAvisoDomingoHora, kAvisoDomingoMinuto);
    } catch (e) {
      debugPrint('No se pudieron programar los avisos: $e');
    }
  }

  static Future<void> _programar(Aviso a, int dia, int hora, int minuto) {
    return _plugin.zonedSchedule(
      id: a.id,
      title: a.titulo,
      body: a.cuerpo,
      payload: a.payload,
      scheduledDate: proxima(dia, hora, minuto),
      notificationDetails: _detalles,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> cancelarTodas() async {
    if (!_listo) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('No se pudieron cancelar: $e');
    }
  }

  /// Muestra el aviso ya mismo: para la demo con jurados.
  /// En el teléfono sale como notificación real; en web, como tarjeta dentro de la app.
  static Future<void> probar(BuildContext context, Aviso a) async {
    if (_listo) {
      try {
        await _plugin.show(id: 100 + a.id, title: a.titulo, body: a.cuerpo, notificationDetails: _detalles, payload: a.payload);
        return;
      } catch (e) {
        debugPrint('Falló la notificación real, se simula: $e');
      }
    }
    if (context.mounted) simular(context, a);
  }

  static void simular(BuildContext context, Aviso a) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entrada;
    var quitada = false;
    void quitar() {
      if (quitada) return;
      quitada = true;
      entrada.remove();
    }

    entrada = OverlayEntry(
      builder: (_) => _TarjetaAviso(
        aviso: a,
        alTocar: () {
          quitar();
          tocada.value = Toque(a.payload);
        },
      ),
    );
    overlay.insert(entrada);
    Timer(const Duration(seconds: 6), quitar);
  }
}

class _TarjetaAviso extends StatelessWidget {
  const _TarjetaAviso({required this.aviso, required this.alTocar});

  final Aviso aviso;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: MarcoAncho(
            maximo: 480,
            child: Material(
              color: Cv.surfaceRaised,
              elevation: 8,
              shadowColor: Cv.velo,
              borderRadius: BorderRadius.circular(Cv.radioLg),
              child: InkWell(
                borderRadius: BorderRadius.circular(Cv.radioLg),
                onTap: alTocar,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/img/parche-icono.png', width: 40, height: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Parches CicloVida · ahora', style: TextStyle(fontSize: 12, color: Cv.inkMuted)),
                            const SizedBox(height: 2),
                            Text(aviso.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Cv.ink)),
                            const SizedBox(height: 2),
                            Text(aviso.cuerpo, style: const TextStyle(fontSize: 14, color: Cv.ink)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
