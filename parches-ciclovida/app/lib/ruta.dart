import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Ubicación del joven y ruta hasta la estación de su parche.
///
/// La ubicación se usa solo en el teléfono para trazar la ruta: nunca se envía al backend de
/// Parches ni se guarda. Para calcular la ruta se le pasan el origen y el destino al servicio
/// público de rutas de OpenStreetMap (OSRM, servidores de FOSSGIS), con perfil de bici o a pie
/// según la actividad del parche. Para un piloto con muchas personas conviene montar un OSRM propio.

class UbicacionException implements Exception {
  const UbicacionException(this.mensaje, {this.abrirAjustes = false});

  final String mensaje;

  /// El permiso quedó negado para siempre: solo se arregla desde los ajustes del teléfono.
  final bool abrirAjustes;

  @override
  String toString() => mensaje;
}

class Ruta {
  const Ruta({required this.puntos, required this.metros, required this.segundos, required this.aPie});

  final List<LatLng> puntos;
  final double metros;

  /// Ya ajustado a la actividad (patinar es un poco más lento que la bici, trotar más rápido que caminar).
  final double segundos;
  final bool aPie;

  String get distanciaTexto =>
      metros < 1000 ? '${metros.round()} m' : '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  String get duracionTexto {
    final min = (segundos / 60).ceil();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final resto = min % 60;
    return resto == 0 ? '$h h' : '$h h $resto min';
  }
}

/// Bici y patines van por el perfil de bici; trotar y caminar, por el de a pie.
bool esAPie(String actividad) => actividad == 'trotar' || actividad == 'caminar';

/// Ajuste sobre la velocidad del perfil de OSRM (bici ≈ 13 km/h, a pie ≈ 4,5 km/h).
double _factorTiempo(String actividad) => switch (actividad) {
      'patines' => 1.15,
      'trotar' => 0.55,
      _ => 1.0,
    };

Future<LatLng> ubicacionActual() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const UbicacionException('Activa la ubicación (GPS) de tu teléfono para trazar la ruta.');
  }
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied || permiso == LocationPermission.unableToDetermine) {
    permiso = await Geolocator.requestPermission();
  }
  if (permiso == LocationPermission.deniedForever) {
    throw const UbicacionException(
      'Bloqueaste el permiso de ubicación. Actívalo en los ajustes para ver la ruta.',
      abrirAjustes: true,
    );
  }
  if (permiso == LocationPermission.denied) {
    throw const UbicacionException('Sin permiso de ubicación no podemos trazar la ruta hasta tu parche.');
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    return LatLng(p.latitude, p.longitude);
  } on TimeoutException {
    throw const UbicacionException('No logramos ubicarte a tiempo. Intenta de nuevo al aire libre.');
  } catch (_) {
    throw const UbicacionException('No pudimos leer tu ubicación. Revisa el permiso e intenta de nuevo.');
  }
}

Future<Ruta> calcularRuta(LatLng desde, LatLng hasta, String actividad) async {
  final aPie = esAPie(actividad);
  final perfil = aPie ? 'routed-foot' : 'routed-bike';
  final uri = Uri.parse(
    'https://routing.openstreetmap.de/$perfil/route/v1/driving/'
    '${desde.longitude},${desde.latitude};${hasta.longitude},${hasta.latitude}'
    '?overview=full&geometries=geojson',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('rutas ${res.statusCode}');
  final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final rutas = data['routes'] as List? ?? const [];
  if (data['code'] != 'Ok' || rutas.isEmpty) throw Exception('sin ruta');
  final r = rutas.first as Map<String, dynamic>;
  final coords = (r['geometry'] as Map<String, dynamic>)['coordinates'] as List;
  return Ruta(
    puntos: [for (final c in coords) LatLng((c as List)[1].toDouble(), c[0].toDouble())],
    metros: (r['distance'] as num).toDouble(),
    segundos: (r['duration'] as num).toDouble() * _factorTiempo(actividad),
    aPie: aPie,
  );
}

/// Navegación paso a paso en Google Maps. Sin origen, Maps usa la ubicación del teléfono.
Uri enlaceNavegacion(LatLng hasta, {LatLng? desde, required String actividad}) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (desde != null) 'origin': '${desde.latitude},${desde.longitude}',
      'destination': '${hasta.latitude},${hasta.longitude}',
      'travelmode': esAPie(actividad) ? 'walking' : 'bicycling',
    });
