import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../ruta.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';
import 'elegir_parche.dart';

/// OpenStreetMap en gris claro con un toque frío, como el fondo de la app: las calles se siguen
/// leyendo y los colores de las actividades resaltan. (Los mapas base claros gratuitos, como CARTO,
/// ahora piden API key.) Última columna: desplazamiento en 0..255.
const _filtroMapaBase = ColorFilter.matrix(<double>[
  0.2050, 0.3769, 0.0381, 0, 97, //
  0.1120, 0.4699, 0.0381, 0, 97, //
  0.1120, 0.3769, 0.1311, 0, 100, //
  0, 0, 0, 1, 0,
]);

/// Contorno blanco para que la figura de la actividad se lea sobre el mapa sin fondo de círculo.
const _contorno = <Shadow>[
  Shadow(color: Colors.white, offset: Offset(1.4, 0)),
  Shadow(color: Colors.white, offset: Offset(-1.4, 0)),
  Shadow(color: Colors.white, offset: Offset(0, 1.4)),
  Shadow(color: Colors.white, offset: Offset(0, -1.4)),
  Shadow(color: Colors.white, offset: Offset(1, 1)),
  Shadow(color: Colors.white, offset: Offset(-1, -1)),
  Shadow(color: Colors.white, offset: Offset(1, -1)),
  Shadow(color: Colors.white, offset: Offset(-1, 1)),
  Shadow(color: Cv.velo, offset: Offset(0, 2), blurRadius: 4),
];

/// A partir de este zoom se ven los nombres de las estaciones.
const _zoomNombres = 13.4;

/// Mapa de las 11 estaciones de la CicloVida: qué actividad se mueve en cada una este domingo,
/// tu ubicación y la ruta hasta la estación de tu parche.
class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key, this.activo = true});

  /// Cuando la pestaña vuelve a quedar activa, los conteos se refrescan solos.
  final bool activo;

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  static const _margenLlegada = Duration(minutes: 10);

  final MapController _mapa = MapController();

  Catalogo? _cat;
  EstadoParche? _estado;
  Map<String, _ResumenEstacion> _resumen = const {};
  Tramo? _elegido;
  String? _error;

  /// Actividad con la que se filtra el mapa; null = todas.
  String? _filtro;
  bool _nombres = false;

  LatLng? _yo;
  Ruta? _ruta;
  bool _verRuta = false;
  bool _buscandoRuta = false;
  bool _rutaFallo = false;

  Api get _api => Sesion.actual.api;

  /// El parche que eligió (sigue ahí aunque el sábado ya tenga grupo).
  ParcheOpcion? get _miParche => _estado?.salida;

  Tramo? get _tramoDeMiParche {
    final p = _miParche;
    return p == null ? null : _cat?.tramo(p.tramoId);
  }

  List<String> get _ordenActividades => [for (final a in _cat?.actividades ?? const <Opcion>[]) a.id];

  /// Al volver a la app (por ejemplo, desde Telegram) se recarga si esta pestaña está abierta.
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onResume: () {
      if (widget.activo) _cargar();
    });
    _cargar();
  }

  @override
  void didUpdateWidget(MapaScreen viejo) {
    super.didUpdateWidget(viejo);
    if (widget.activo && !viejo.activo) _cargar();
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final cat = _cat ?? await _api.catalogo();
      final parches = await _api.parches();
      final estado = await _api.miParche();
      final resumen = <String, _ResumenEstacion>{};
      for (final p in parches) {
        final r = resumen.putIfAbsent(p.tramoId, _ResumenEstacion.new);
        r.porActividad[p.actividad] = (r.porActividad[p.actividad] ?? 0) + p.inscritos;
        r.porHora[p.horaEncuentro] = (r.porHora[p.horaEncuentro] ?? 0) + p.inscritos;
        r.nombreHora[p.horaEncuentro] = p.horaNombre;
        if (p.inscritos > 0) r.parchesConGente += 1;
        if (p.esMio) r.miActividad = p.actividad;
      }
      if (!mounted) return;
      final cambioDeParche = estado.salida?.id != _miParche?.id;
      setState(() {
        _cat = cat;
        _resumen = resumen;
        _estado = estado;
        _error = null;
        if (cambioDeParche) {
          // la ruta vieja llevaba a otro parche
          _ruta = null;
          _verRuta = false;
          _rutaFallo = false;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  void _alMoverMapa(MapCamera camara, bool _) {
    final nombres = camara.zoom >= _zoomNombres;
    if (nombres == _nombres) return;
    // puede llegar en medio de un frame: se aplica al terminar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _nombres = nombres);
    });
  }

  Future<void> _verParches(Tramo t) async {
    final cat = _cat;
    if (cat == null) return;
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => ElegirParcheScreen(catalogo: cat, tramoInicial: t.id)),
    );
    await _cargar();
  }

  void _avisoUbicacion(UbicacionException e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.mensaje),
        action: e.abrirAjustes ? SnackBarAction(label: 'Ajustes', onPressed: Geolocator.openAppSettings) : null,
      ),
    );
  }

  Future<void> _centrarEnMi() async {
    try {
      final yo = await ubicacionActual();
      if (!mounted) return;
      setState(() => _yo = yo);
      _mapa.move(yo, 15);
    } on UbicacionException catch (e) {
      _avisoUbicacion(e);
    }
  }

  Future<void> _trazarRuta() async {
    final parche = _miParche;
    final tramo = _tramoDeMiParche;
    if (parche == null || tramo == null) return;
    final destino = LatLng(tramo.lat, tramo.lng);
    setState(() => _buscandoRuta = true);
    try {
      final yo = await ubicacionActual();
      Ruta? ruta;
      try {
        ruta = await calcularRuta(yo, destino, parche.actividad);
      } catch (_) {
        ruta = null; // sin ruta por calles: se muestra la línea directa y el botón de Google Maps
      }
      if (!mounted) return;
      setState(() {
        _yo = yo;
        _ruta = ruta;
        _rutaFallo = ruta == null;
        _verRuta = true;
        _elegido = null;
      });
      _mapa.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(ruta?.puntos ?? [yo, destino]),
        padding: const EdgeInsets.fromLTRB(48, 140, 48, 340),
        maxZoom: 16,
      ));
    } on UbicacionException catch (e) {
      _avisoUbicacion(e);
    } finally {
      if (mounted) setState(() => _buscandoRuta = false);
    }
  }

  void _cerrarRuta() => setState(() {
        _verRuta = false;
        _ruta = null;
        _rutaFallo = false;
      });

  Future<void> _navegar() async {
    final parche = _miParche;
    final tramo = _tramoDeMiParche;
    if (parche == null || tramo == null) return;
    await launchUrl(
      enlaceNavegacion(LatLng(tramo.lat, tramo.lng), desde: _yo, actividad: parche.actividad),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  /// "Para llegar a las 8:00 a. m., sal a las 7:36 a. m." (con 10 minutos de margen).
  String? _salirA(Ruta ruta) {
    final parche = _miParche;
    final fecha = _estado?.jornadaFecha;
    if (parche == null || fecha == null) return null;
    final encuentro = DateTime.tryParse('${fecha}T${parche.horaEncuentro}:00');
    if (encuentro == null) return null;
    final salir = encuentro.subtract(Duration(seconds: ruta.segundos.ceil()) + _margenLlegada);
    return horaBonita('${salir.hour}:${salir.minute.toString().padLeft(2, '0')}');
  }

  /// Estaciones cercanas (San Carlos y Ciudad de Cali, El Ingenio y Dorada) se pisan con poco zoom. Como en los mapas de
  /// siempre, las del sur van encima para que no tapen el número de la vecina; la elegida y la de
  /// tu parche, siempre al frente.
  List<Tramo> _enOrdenDeDibujo(List<Tramo> tramos) {
    int prioridad(Tramo t) => t.id == _elegido?.id ? 2 : (t.id == _miParche?.tramoId ? 1 : 0);
    return [...tramos]
      ..sort((a, b) {
        final p = prioridad(a).compareTo(prioridad(b));
        return p != 0 ? p : b.lat.compareTo(a.lat);
      });
  }

  Marker _marcador(Catalogo cat, Tramo t) {
    final r = _resumen[t.id];
    final esMia = r?.miActividad != null;
    // con filtro, la figura de esa actividad; sin filtro, la de tu parche o la que más gente tiene
    final actividad = _filtro ?? (esMia ? r!.miActividad : r?.dominante(_ordenActividades));
    final elegido = _elegido?.id == t.id;
    return Marker(
      point: LatLng(t.lat, t.lng),
      width: 132,
      height: 110,
      child: _MarcadorEstacion(
        nombre: t.nombre,
        actividad: actividad,
        nombreActividad: actividad == null ? null : cat.nombreDe(cat.actividades, actividad),
        gente: r?.de(_filtro) ?? 0,
        esMia: esMia,
        elegido: elegido,
        mostrarNombre: _nombres || elegido,
        atenuado: _verRuta && t.id != _miParche?.tramoId,
        onTap: () => setState(() => _elegido = t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    final tramoMio = _tramoDeMiParche;
    final colorRuta = _miParche == null ? Cv.tealInk : coloresDe(_miParche!.actividad).tinta;
    final mostrarTarjetaRuta = _verRuta && _elegido == null && _miParche != null && tramoMio != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Zonas de la CicloVida')),
      body: cat == null
          ? ListView(
              padding: rellenoAncho(context, arriba: 12, abajo: 24),
              children: _error == null
                  ? const [
                      Esqueleto(alto: 96),
                      SizedBox(height: 16),
                      Esqueleto(alto: 380, radio: Cv.radioXl),
                    ]
                  : [TarjetaError(mensaje: _error!, reintentar: _cargar)],
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([for (final t in cat.tramos) LatLng(t.lat, t.lng)]),
                      padding: const EdgeInsets.fromLTRB(40, 150, 40, 110),
                    ),
                    minZoom: 10,
                    maxZoom: 18,
                    // sin rotar con dos dedos: el norte siempre arriba, como en un plano de la ciudad
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onPositionChanged: _alMoverMapa,
                    onTap: (_, __) => setState(() => _elegido = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'co.dedsec.parches_ciclovida',
                      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _filtroMapaBase, child: tile),
                    ),
                    if (_verRuta && _ruta != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _ruta!.puntos,
                            strokeWidth: 5,
                            color: colorRuta,
                            borderStrokeWidth: 2.5,
                            borderColor: Colors.white,
                          ),
                        ],
                      )
                    else if (_verRuta && _yo != null && tramoMio != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [_yo!, LatLng(tramoMio.lat, tramoMio.lng)],
                            strokeWidth: 4,
                            color: colorRuta,
                            pattern: StrokePattern.dotted(),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final t in _enOrdenDeDibujo(cat.tramos)) _marcador(cat, t),
                        if (_yo != null) Marker(point: _yo!, width: 28, height: 28, child: const _PuntoYo()),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          _verRuta ? '© OpenStreetMap · rutas OSRM (FOSSGIS)' : '© OpenStreetMap',
                          style: const TextStyle(fontSize: 10, color: Cv.inkMuted),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: MarcoAncho(
                      maximo: 560,
                      child: _BarraFiltros(
                        actividades: cat.actividades,
                        filtro: _filtro,
                        onFiltro: (a) => setState(() => _filtro = a),
                      ),
                    ),
                  ),
                ),
                // botón de "mi ubicación", siempre a mano
                Align(
                  alignment: const Alignment(1, 0.05),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FloatingActionButton.small(
                      heroTag: 'mi-ubicacion',
                      onPressed: _centrarEnMi,
                      backgroundColor: Cv.surfaceRaised,
                      foregroundColor: Cv.tealInk,
                      tooltip: 'Mi ubicación',
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ),
                if (_elegido != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: MarcoAncho(
                        maximo: 560,
                        child: _TarjetaEstacion(
                        tramo: _elegido!,
                        comuna: cat.comuna(_elegido!.comuna),
                        resumen: _resumen[_elegido!.id],
                        actividades: cat.actividades,
                        onVerParches: () => _verParches(_elegido!),
                        onComoLlego: _elegido!.id == _miParche?.tramoId ? _trazarRuta : null,
                        ),
                      ),
                    ),
                  )
                else if (mostrarTarjetaRuta)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: MarcoAncho(
                        maximo: 560,
                        child: _TarjetaRuta(
                        parche: _miParche!,
                        tramo: tramoMio!,
                        ruta: _ruta,
                        fallo: _rutaFallo,
                        salirA: _ruta == null ? null : _salirA(_ruta!),
                        ocupado: _buscandoRuta,
                        onNavegar: _navegar,
                        onActualizar: _trazarRuta,
                        onCerrar: _cerrarRuta,
                        ),
                      ),
                    ),
                  )
                else if (_miParche != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: FloatingActionButton.extended(
                        heroTag: 'como-llego',
                        onPressed: _buscandoRuta ? null : _trazarRuta,
                        backgroundColor: coloresDe(_miParche!.actividad).tinta,
                        foregroundColor: Colors.white,
                        icon: _buscandoRuta
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Icon(iconoDe(_miParche!.actividad)),
                        label: Text(_buscandoRuta ? 'Buscando tu ubicación…' : 'Cómo llego a mi parche'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ResumenEstacion {
  final Map<String, int> porActividad = {};
  final Map<String, int> porHora = {};
  final Map<String, String> nombreHora = {};
  int parchesConGente = 0;

  /// La actividad de tu parche, si tu parche sale de esta estación.
  String? miActividad;

  int get total => porActividad.values.fold(0, (a, b) => a + b);

  /// Gente de una actividad, o de todas si es null.
  int de(String? actividad) => actividad == null ? total : (porActividad[actividad] ?? 0);

  /// La actividad con más gente; con empate gana la que va primero en el catálogo. Null si no hay nadie.
  String? dominante(List<String> orden) {
    String? mejor;
    var max = 0;
    for (final a in orden) {
      final n = porActividad[a] ?? 0;
      if (n > max) {
        max = n;
        mejor = a;
      }
    }
    return mejor;
  }

  /// "8:00 a. m.": la hora con más gente en la estación.
  String? get horaPico {
    String? mejor;
    var max = 0;
    for (final e in porHora.entries) {
      if (e.value > max) {
        max = e.value;
        mejor = e.key;
      }
    }
    return mejor == null ? null : nombreHora[mejor];
  }
}

/// Filtro por actividad, con los mismos colores e íconos de toda la app. Hace de leyenda del mapa.
class _BarraFiltros extends StatelessWidget {
  const _BarraFiltros({required this.actividades, required this.filtro, required this.onFiltro});

  final List<Opcion> actividades;
  final String? filtro;
  final ValueChanged<String?> onFiltro;

  @override
  Widget build(BuildContext context) {
    String? nombre;
    for (final a in actividades) {
      if (a.id == filtro) nombre = a.nombre.toLowerCase();
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 6,
      shadowColor: Cv.velo,
      borderRadius: BorderRadius.circular(Cv.radioLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _chip(null, 'Todas'),
                  for (final a in actividades) ...[const SizedBox(width: 6), _chip(a.id, a.nombre)],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(
                nombre == null
                    ? 'La figura es la actividad con más gente; el número, cuántos van el domingo.'
                    : 'Parches de $nombre: el número es cuánta gente va; figura clara, aún nadie.',
                style: const TextStyle(fontSize: 12, height: 1.3, color: Cv.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String? actividad, String texto) {
    final sel = filtro == actividad;
    final col = actividad == null ? null : coloresDe(actividad);
    final fondo = sel ? (col?.suave ?? Cv.tealSoft) : Cv.surfaceRaised;
    final tinta = col?.tinta ?? (sel ? Cv.tealInk : Cv.ink);
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => onFiltro(actividad),
      avatar: actividad == null ? null : Icon(iconoDe(actividad), size: 18, color: tinta),
      label: Text(texto),
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tinta),
      color: WidgetStatePropertyAll(fondo),
      side: BorderSide(color: sel ? tinta : Cv.line, width: sel ? 1.5 : 1),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Marcador de estación: la figura de la actividad, sin círculo, con contorno blanco para leerse
/// sobre el mapa. Un número pequeño dice cuánta gente va; la figura clara, que aún no hay nadie.
class _MarcadorEstacion extends StatelessWidget {
  const _MarcadorEstacion({
    required this.nombre,
    required this.actividad,
    required this.nombreActividad,
    required this.gente,
    required this.esMia,
    required this.elegido,
    required this.mostrarNombre,
    required this.atenuado,
    required this.onTap,
  });

  final String nombre;
  final String? actividad;
  final String? nombreActividad;
  final int gente;
  final bool esMia;
  final bool elegido;
  final bool mostrarNombre;
  final bool atenuado;
  final VoidCallback onTap;

  static const _ancho = 132.0;
  static const _alto = 110.0;

  @override
  Widget build(BuildContext context) {
    final tinta = actividad == null ? Cv.inkMuted : coloresDe(actividad!).tinta;
    final tam = esMia ? 30.0 : 26.0;
    final vacio = gente == 0;
    final quien = vacio ? 'nadie todavía' : '$gente ${gente == 1 ? 'estudiante' : 'estudiantes'}';
    return Semantics(
      button: true,
      onTap: onTap,
      label: 'Estación $nombre${esMia ? ', tu parche' : ''}'
          '${nombreActividad == null ? '' : ', ${nombreActividad!.toLowerCase()}'}: $quien',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: atenuado ? 0.35 : 1,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: _ancho,
            height: _alto,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // zona de toque de 44 px alrededor de la figura (accesible), el resto deja pasar al mapa
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedScale(
                        scale: elegido ? 1.25 : 1,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutBack,
                        child: Opacity(
                          opacity: vacio ? 0.45 : 1,
                          child: Icon(
                            actividad == null ? Icons.location_on : iconoDe(actividad!),
                            size: tam,
                            color: tinta,
                            shadows: _contorno,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // el número siempre se ve: sin gente, un 0 en gris (no solo la figura más clara)
                Positioned(
                  left: _ancho / 2 + tam * 0.22,
                  top: _alto / 2 - tam / 2 - 9,
                  child: IgnorePointer(child: _Insignia(gente: gente, color: tinta)),
                ),
                if (esMia || mostrarNombre)
                  Positioned(
                    top: _alto / 2 + tam / 2 + 2,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: onTap,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (esMia)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Cv.coralInk,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Text(
                                'Tu parche',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
                              ),
                            ),
                          if (mostrarNombre)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Cv.ink,
                                  height: 1.2,
                                  shadows: _contorno,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El número de estudiantes: una etiqueta pequeña en el color de la actividad.
class _Insignia extends StatelessWidget {
  const _Insignia({required this.gente, required this.color});

  final int gente;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final vacio = gente == 0;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: vacio ? Colors.white : color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: vacio ? Cv.lineStrong : Colors.white, width: 1.5),
      ),
      child: Text(
        gente > 99 ? '99+' : '$gente',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: vacio ? Cv.inkMuted : Colors.white, height: 1.25),
      ),
    );
  }
}

/// Tu ubicación: punto teal con borde blanco y halo suave.
class _PuntoYo extends StatelessWidget {
  const _PuntoYo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tu ubicación',
      child: Container(
        decoration: BoxDecoration(color: Cv.tealInk.withValues(alpha: 0.16), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Cv.tealInk,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: Cv.sombra,
          ),
        ),
      ),
    );
  }
}

/// La ruta hasta tu parche: distancia, tiempo, a qué hora salir y navegación paso a paso.
class _TarjetaRuta extends StatelessWidget {
  const _TarjetaRuta({
    required this.parche,
    required this.tramo,
    required this.ruta,
    required this.fallo,
    required this.salirA,
    required this.ocupado,
    required this.onNavegar,
    required this.onActualizar,
    required this.onCerrar,
  });

  final ParcheOpcion parche;
  final Tramo tramo;
  final Ruta? ruta;
  final bool fallo;
  final String? salirA;
  final bool ocupado;
  final VoidCallback onNavegar;
  final VoidCallback onActualizar;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final col = coloresDe(parche.actividad);
    final r = ruta;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 6, color: col.marca),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Ruta a tu parche', style: t.headlineSmall)),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Actualizar desde donde estoy',
                      onPressed: ocupado ? null : onActualizar,
                    ),
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar ruta', onPressed: onCerrar),
                  ],
                ),
                Text('${parche.nombre} · Estación ${tramo.nombre}', style: t.titleMedium),
                Text('${tramo.punto} · ${tramo.referencia}', style: t.bodySmall),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: r == null
                      ? Text(
                          fallo
                              ? 'No pudimos calcular la ruta por calles ahora. La línea punteada va directo a la '
                                  'estación; para ir paso a paso, abre la navegación.'
                              : 'Buscando la ruta…',
                          style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(iconoDe(parche.actividad), color: col.tinta, size: 22),
                                const SizedBox(width: 8),
                                Text(r.duracionTexto,
                                    style: TextStyle(
                                        fontFamily: Cv.display, fontSize: 26, fontWeight: FontWeight.w800, color: col.tinta)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '· ${r.distanciaTexto} ${r.aPie ? 'a pie' : 'en ${parche.actividadNombre.toLowerCase()}'}',
                                    style: t.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            if (salirA != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Para llegar a las ${parche.horaNombre}, sal a las $salirA (con 10 min de margen).',
                                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FilledButton.icon(
                    onPressed: onNavegar,
                    style: botonDeColor(col.tinta),
                    icon: const Icon(Icons.navigation_outlined, size: 20),
                    label: const Text('Navegar paso a paso'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'El domingo hay vías cerradas a los carros: sigue la señalización de la CicloVida. '
                  'Tu ubicación no se guarda ni se envía a Parches.',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaEstacion extends StatelessWidget {
  const _TarjetaEstacion({
    required this.tramo,
    required this.comuna,
    required this.resumen,
    required this.actividades,
    required this.onVerParches,
    this.onComoLlego,
  });

  final Tramo tramo;
  final Comuna? comuna;
  final _ResumenEstacion? resumen;
  final List<Opcion> actividades;
  final VoidCallback onVerParches;

  /// Solo en la estación de tu parche.
  final VoidCallback? onComoLlego;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = resumen?.total ?? 0;
    final conGente = resumen?.parchesConGente ?? 0;
    final pico = resumen?.horaPico;
    final esMia = resumen?.miActividad != null;
    final quienes = total == 0
        ? 'Nadie todavía este domingo: estrena esta estación'
        : '$total ${total == 1 ? 'estudiante' : 'estudiantes'} en $conGente ${conGente == 1 ? 'parche' : 'parches'}'
            '${pico == null ? '' : ' · más gente a las $pico'}';
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Cinta(alto: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Estación ${tramo.nombre}', style: t.headlineSmall)),
                    if (esMia) const Sello('Tu parche', fondo: Cv.coralSoft, color: Cv.coralInk, icono: Icons.groups),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${tramo.punto} · ${tramo.referencia}', style: t.bodyMedium),
                Text(
                  comuna == null || comuna!.barrios.isEmpty
                      ? 'Comuna ${tramo.comuna}'
                      : 'Comuna ${tramo.comuna} · cerca de ${comuna!.barriosResumen()}',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < actividades.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: _CeldaActividad(actividad: actividades[i], gente: resumen?.de(actividades[i].id) ?? 0)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(quienes, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (onComoLlego != null) ...[
                  FilledButton.icon(
                    onPressed: onComoLlego,
                    icon: const Icon(Icons.directions, size: 20),
                    label: const Text('Cómo llego'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onVerParches, child: const Text('Ver parches de esta estación')),
                ] else
                  FilledButton(onPressed: onVerParches, child: const Text('Ver parches de esta estación')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuánta gente va en cada actividad desde la estación, con su figura y su color.
class _CeldaActividad extends StatelessWidget {
  const _CeldaActividad({required this.actividad, required this.gente});

  final Opcion actividad;
  final int gente;

  @override
  Widget build(BuildContext context) {
    final col = coloresDe(actividad.id);
    final hay = gente > 0;
    final tinta = hay ? col.tinta : Cv.inkMuted;
    return Semantics(
      label: '${actividad.nombre}: ${hay ? '$gente' : 'nadie todavía'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: hay ? col.suave : Cv.surface,
            borderRadius: BorderRadius.circular(Cv.radioMd),
            border: Border.all(color: hay ? col.suave : Cv.line),
          ),
          child: Column(
            children: [
              Icon(iconoDe(actividad.id), size: 22, color: hay ? col.tinta : Cv.lineStrong),
              Text(
                '$gente',
                style: TextStyle(fontFamily: Cv.display, fontSize: 20, fontWeight: FontWeight.w800, color: tinta, height: 1.1),
              ),
              Text(actividad.nombre, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tinta)),
            ],
          ),
        ),
      ),
    );
  }
}
