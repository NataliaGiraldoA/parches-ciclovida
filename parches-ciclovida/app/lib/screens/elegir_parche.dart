import 'package:flutter/material.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/boleta.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';

/// La lista de parches que generó el sistema para el domingo. El joven filtra y se une a uno.
/// Devuelve el mensaje para mostrar si se unió.
class ElegirParcheScreen extends StatefulWidget {
  const ElegirParcheScreen({super.key, required this.catalogo, this.tramoInicial, this.actualId});

  final Catalogo catalogo;
  final String? tramoInicial;

  /// El parche en el que ya está, para confirmar antes de cambiarse.
  final int? actualId;

  @override
  State<ElegirParcheScreen> createState() => _ElegirParcheScreenState();
}

class _ElegirParcheScreenState extends State<ElegirParcheScreen> {
  late String? _tramo = widget.tramoInicial;
  String? _franja;
  String? _actividad;
  List<ParcheOpcion>? _parches;
  String? _error;
  bool _ocupado = false;

  Catalogo get _cat => widget.catalogo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _parches = null;
      _error = null;
    });
    try {
      final lista = await Sesion.actual.api.parches(tramo: _tramo, franja: _franja, actividad: _actividad);
      if (!mounted) return;
      setState(() => _parches = lista);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  void _filtrar(VoidCallback cambio) {
    setState(cambio);
    _cargar();
  }

  Future<void> _unirme(ParcheOpcion p) async {
    if (widget.actualId != null && widget.actualId != p.id) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Te cambias al ${p.nombre}?'),
          content: const Text('Sales del parche en el que estás ahora y tu lugar queda libre para alguien más.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cambiarme')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupado = true);
    try {
      await Sesion.actual.api.unirme(p.id);
      if (!mounted) return;
      Navigator.of(context).pop('¡Listo! Te uniste al ${p.nombre}.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      await _cargar();
    }
  }

  Future<void> _elegirEstacion() async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Cv.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Cv.radioLg))),
      builder: (ctx) => _HojaEstaciones(catalogo: _cat, actual: _tramo),
    );
    if (elegido == null) return;
    _filtrar(() => _tramo = elegido.isEmpty ? null : elegido);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Elige tu parche')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarcoAncho(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Para el ${fechaLarga(_cat.proximaJornada)}. El sistema abre parches en todas las estaciones; '
                'tú escoges hora, actividad y lugar.',
                style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
              ),
            ),
          ),
          MarcoAncho(child: _filtros()),
          Expanded(child: _lista()),
        ],
      ),
    );
  }

  Widget _filtros() {
    final tramo = _tramo == null ? null : _cat.tramo(_tramo!);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Rebote(
              child: Material(
                color: Cv.surfaceRaised,
                elevation: 2,
                shadowColor: Cv.velo,
                shape: const StadiumBorder(side: BorderSide(color: Cv.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _elegirEstacion,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                    child: Row(
                      children: [
                        const IconoBurbuja(Icons.place, color: Cv.tealInk, fondo: Cv.tealSoft, tamano: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tramo == null ? 'Todas las estaciones' : 'Estación ${tramo.nombre}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Cv.ink),
                          ),
                        ),
                        const Text('Cambiar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Cv.tealInk)),
                        const Icon(Icons.expand_more, color: Cv.tealInk),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FilaChips(
            children: [
              _chip('Todas las horas', _franja == null, () => _filtrar(() => _franja = null)),
              for (final f in _cat.franjas) _chip(f.nombre, _franja == f.id, () => _filtrar(() => _franja = f.id)),
            ],
          ),
          const SizedBox(height: 8),
          _FilaChips(
            children: [
              _chip('Todo', _actividad == null, () => _filtrar(() => _actividad = null)),
              for (final a in _cat.actividades)
                _chip(a.nombre, _actividad == a.id, () => _filtrar(() => _actividad = a.id), actividad: a.id),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, bool sel, VoidCallback onTap, {String? actividad}) {
    final col = actividad == null ? null : coloresDe(actividad);
    final fondo = sel ? (col?.suave ?? Cv.tealSoft) : Cv.surfaceRaised;
    final tinta = col?.tinta ?? (sel ? Cv.tealInk : Cv.ink);
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => onTap(),
      avatar: actividad == null ? null : Icon(iconoDe(actividad), size: 20, color: tinta),
      label: Text(texto),
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tinta),
      color: WidgetStatePropertyAll(fondo),
      side: BorderSide(color: sel ? tinta : Cv.line, width: sel ? 1.5 : 1),
    );
  }

  Widget _lista() {
    final parches = _parches;
    if (_error != null) {
      return ListView(
        padding: rellenoAncho(context, arriba: 16, abajo: 16),
        children: [TarjetaError(mensaje: _error!, reintentar: _cargar)],
      );
    }
    if (parches == null) {
      // la forma de las boletas mientras llegan
      return ListView(
        padding: rellenoAncho(context, arriba: 18, abajo: 32),
        children: const [
          Esqueleto(alto: 28, ancho: 200, radio: Cv.radioSm),
          SizedBox(height: 14),
          Esqueleto(alto: 180),
          SizedBox(height: 12),
          Esqueleto(alto: 180),
          SizedBox(height: 12),
          Esqueleto(alto: 180),
        ],
      );
    }
    if (parches.isEmpty) {
      return ListView(
        padding: rellenoAncho(context, arriba: 16, abajo: 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: EstadoVacio(
                emoji: '🔎',
                fondo: Cv.brisaCoral,
                titulo: 'Sin parches con esos filtros',
                texto: 'Prueba otra hora, otra actividad o todas las estaciones.',
                accion: FilledButton(
                  onPressed: () => _filtrar(() {
                    _tramo = null;
                    _franja = null;
                    _actividad = null;
                  }),
                  child: const Text('Quitar filtros'),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final hijos = <Widget>[];
    String? horaActual;
    for (final p in parches) {
      if (!p.esMio && p.horaEncuentro != horaActual) {
        horaActual = p.horaEncuentro;
        hijos.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 20, 4, 12),
          child: Row(
            children: [
              const IconoBurbuja(Icons.schedule, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 36),
              const SizedBox(width: 10),
              Expanded(child: Text('Salen a las ${p.horaNombre}', style: Theme.of(context).textTheme.headlineSmall)),
            ],
          ),
        ));
      }
      hijos.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: BoletaParche(parche: p, ocupado: _ocupado, onUnirme: () => _unirme(p)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(padding: rellenoAncho(context, abajo: 32), children: hijos),
    );
  }
}

class _FilaChips extends StatelessWidget {
  const _FilaChips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
        ],
      ),
    );
  }
}

/// Devuelve el id de la estación, o '' para "todas".
class _HojaEstaciones extends StatelessWidget {
  const _HojaEstaciones({required this.catalogo, required this.actual});

  final Catalogo catalogo;
  final String? actual;

  @override
  Widget build(BuildContext context) {
    final tramos = [...catalogo.tramos]..sort((a, b) => a.nombre.compareTo(b.nombre));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('¿Desde qué estación sales?', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _fila(context, '', 'Todas las estaciones', null),
          for (final t in tramos) _fila(context, t.id, t.nombre, '${t.punto} · ${t.referencia}\nComuna ${t.comuna}${_barrios(t)}'),
        ],
      ),
    );
  }

  /// Barrios de referencia de la comuna de la estación, para ubicarse rápido.
  String _barrios(Tramo t) {
    final c = catalogo.comuna(t.comuna);
    return c == null || c.barrios.isEmpty ? '' : ' · ${c.barrios.take(2).join(', ')}…';
  }

  Widget _fila(BuildContext context, String id, String titulo, String? detalle) {
    final sel = (actual ?? '') == id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Cv.radioMd)),
      tileColor: sel ? Cv.tealSoft : null,
      leading: Icon(id.isEmpty ? Icons.map_outlined : Icons.place_outlined, color: Cv.tealInk),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: detalle == null ? null : Text(detalle),
      isThreeLine: detalle != null && detalle.contains('\n'),
      trailing: sel ? const Icon(Icons.check_circle, color: Cv.tealInk) : null,
      onTap: () => Navigator.of(context).pop(id),
    );
  }
}
