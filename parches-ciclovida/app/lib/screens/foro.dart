import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';

/// Foro comunal: comentarios sobre los parches, la app o cómo se sienten.
/// Cada mensaje muestra solo el primer nombre y la universidad, igual que en el grupo.
class ForoScreen extends StatefulWidget {
  const ForoScreen({super.key, this.activo = true});

  /// Cuando la pestaña vuelve a quedar activa, la lista se refresca sola.
  final bool activo;

  @override
  State<ForoScreen> createState() => _ForoScreenState();
}

class _ForoScreenState extends State<ForoScreen> {
  final TextEditingController _texto = TextEditingController();

  Catalogo? _cat;
  List<MensajeForo> _mensajes = const [];
  String? _filtro; // null = todas las categorías
  String _categoria = 'parches';
  String? _error;
  bool _ocupado = false;

  Api get _api => Sesion.actual.api;

  /// Al volver a la app (por ejemplo, tras publicar desde Telegram) se recarga si esta pestaña está abierta.
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
  void didUpdateWidget(ForoScreen viejo) {
    super.didUpdateWidget(viejo);
    if (widget.activo && !viejo.activo) _cargar();
  }

  @override
  void dispose() {
    _ciclo.dispose();
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final cat = _cat ?? await _api.catalogo();
      final mensajes = await _api.foro(categoria: _filtro);
      if (!mounted) return;
      setState(() {
        _cat = cat;
        _mensajes = mensajes;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  Future<void> _publicar() async {
    final texto = _texto.text.trim();
    if (texto.length < 2 || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await _api.foroPublicar(categoria: _categoria, texto: texto);
      _texto.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        // que el mensaje recién publicado siempre quede a la vista, aunque haya otro filtro puesto
        if (_filtro != null && _filtro != _categoria) setState(() => _filtro = null);
      }
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _borrar(MensajeForo m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar tu mensaje?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Cv.rojoInk),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.foroBorrar(m.id);
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return Scaffold(
      appBar: AppBar(title: const Text('Foro del parche')),
      body: cat == null
          ? ListView(
              padding: rellenoAncho(context, arriba: 12, abajo: 24),
              children: _error == null
                  ? [
                      const Esqueleto(alto: 40, ancho: 280, radio: 999),
                      for (var i = 0; i < 4; i++) ...[const SizedBox(height: 12), const Esqueleto(alto: 104)],
                    ]
                  : [TarjetaError(mensaje: _error!, reintentar: _cargar)],
            )
          : Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: rellenoAncho(context, arriba: 4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Todo'),
                          selected: _filtro == null,
                          selectedColor: Cv.verdeSoft,
                          side: BorderSide(color: _filtro == null ? Cv.verdeInk : Cv.line, width: _filtro == null ? 1.5 : 1),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _filtro == null ? Cv.verdeInk : Cv.ink,
                          ),
                          onSelected: (_) {
                            setState(() => _filtro = null);
                            _cargar();
                          },
                        ),
                      ),
                      for (final c in cat.foroCategorias)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(_iconoCategoria(c.id), size: 18, color: _colorCategoria(c.id).tinta),
                            label: Text(c.nombre),
                            selected: _filtro == c.id,
                            selectedColor: _colorCategoria(c.id).suave,
                            side: BorderSide(
                              color: _filtro == c.id ? _colorCategoria(c.id).tinta : Cv.line,
                              width: _filtro == c.id ? 1.5 : 1,
                            ),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _filtro == c.id ? _colorCategoria(c.id).tinta : Cv.ink,
                            ),
                            onSelected: (_) {
                              setState(() => _filtro = c.id);
                              _cargar();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _cargar,
                    child: _mensajes.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: rellenoAncho(context, arriba: 24, abajo: 24),
                            children: const [
                              EstadoVacio(
                                emoji: '💬',
                                fondo: Cv.brisaVerde,
                                titulo: 'Estrena el foro',
                                texto: 'Nadie ha escrito todavía. Cuenta cómo te fue en tu parche o qué mejorarías de la app.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: rellenoAncho(context, arriba: 8, abajo: 12),
                            itemCount: _mensajes.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _Mensaje(
                              mensaje: _mensajes[i],
                              nombreCategoria: cat.nombreDe(cat.foroCategorias, _mensajes[i].categoria),
                              onBorrar: _mensajes[i].esMio ? () => _borrar(_mensajes[i]) : null,
                            ),
                          ),
                  ),
                ),
                _Redactor(
                  categorias: cat.foroCategorias,
                  categoria: _categoria,
                  controller: _texto,
                  ocupado: _ocupado,
                  onCategoria: (id) => setState(() => _categoria = id),
                  onEnviar: _publicar,
                ),
              ],
            ),
    );
  }
}

ColoresActividad _colorCategoria(String id) {
  switch (id) {
    case 'parches':
      return const ColoresActividad(Cv.verde, Cv.verdeInk, Cv.verdeSoft);
    case 'app':
      return const ColoresActividad(Cv.teal, Cv.tealInk, Cv.tealSoft);
    default: // animo
      return const ColoresActividad(Cv.coral, Cv.coralInk, Cv.coralSoft);
  }
}

IconData _iconoCategoria(String id) {
  switch (id) {
    case 'parches':
      return Icons.groups;
    case 'app':
      return Icons.smartphone;
    default: // animo
      return Icons.favorite;
  }
}

String _haceCuanto(String iso) {
  final fecha = DateTime.tryParse(iso);
  if (fecha == null) return '';
  final d = DateTime.now().difference(fecha);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.mensaje, required this.nombreCategoria, this.onBorrar});

  final MensajeForo mensaje;
  final String nombreCategoria;
  final VoidCallback? onBorrar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final col = _colorCategoria(mensaje.categoria);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: col.tinta,
              child: Text(
                mensaje.nombre.isEmpty ? '?' : mensaje.nombre[0].toUpperCase(),
                style: const TextStyle(fontFamily: Cv.display, fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${mensaje.nombre} · ${mensaje.universidad}',
                          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_haceCuanto(mensaje.creadoEn), style: t.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(mensaje.texto, style: t.bodyMedium),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: col.suave, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_iconoCategoria(mensaje.categoria), size: 13, color: col.tinta),
                        const SizedBox(width: 4),
                        Text(nombreCategoria, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: col.tinta)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (onBorrar != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Cv.inkMuted),
                tooltip: 'Borrar mi mensaje',
                onPressed: onBorrar,
              ),
          ],
        ),
      ),
    );
  }
}

class _Redactor extends StatelessWidget {
  const _Redactor({
    required this.categorias,
    required this.categoria,
    required this.controller,
    required this.ocupado,
    required this.onCategoria,
    required this.onEnviar,
  });

  final List<Opcion> categorias;
  final String categoria;
  final TextEditingController controller;
  final bool ocupado;
  final ValueChanged<String> onCategoria;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return BarraInferior(
      relleno: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final c in categorias)
                ChoiceChip(
                  avatar: Icon(_iconoCategoria(c.id), size: 16, color: _colorCategoria(c.id).tinta),
                  label: Text(c.nombre),
                  selected: categoria == c.id,
                  selectedColor: _colorCategoria(c.id).suave,
                  side: BorderSide(
                    color: categoria == c.id ? _colorCategoria(c.id).tinta : Cv.line,
                    width: categoria == c.id ? 1.5 : 1,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: categoria == c.id ? _colorCategoria(c.id).tinta : Cv.ink,
                  ),
                  onSelected: (_) => onCategoria(c.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '¿Cómo te fue? ¿Qué mejorarías?',
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: ocupado ? null : onEnviar,
                style: IconButton.styleFrom(
                  backgroundColor: Cv.verdeInk,
                  disabledBackgroundColor: Cv.line,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.send, size: 20, color: Colors.white),
                tooltip: 'Publicar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
