import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/diseno.dart';

/// Chat del parche: opcional, solo entre quienes se unieron. Se actualiza solo cada pocos segundos.
/// Los estudiantes simulados de la demo van marcados con ✨ IA: conversan con Gemini según su
/// personalidad (perfil y quiz del JSON de simulados).
/// Devuelve un mensaje para mostrar al volver, si hay algo que contar (salió, cambió de parche).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.estado});

  /// El estado con el que se abrió (ya unido).
  final ChatEstado estado;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _cadaCuanto = Duration(milliseconds: 2500);

  final _texto = TextEditingController();
  final _scroll = ScrollController();
  late List<ChatMensaje> _mensajes = [...widget.estado.mensajes];
  late List<ChatMiembro> _miembros = widget.estado.miembros;
  late List<String> _escribiendo = widget.estado.escribiendo;
  late bool _simuladosConversan = widget.estado.simuladosConversan;
  Timer? _timer;
  late final AppLifecycleListener _ciclo;
  bool _enviando = false;
  bool _consultando = false;

  Api get _api => Sesion.actual.api;

  int? get _ultimoId => _mensajes.isEmpty ? null : _mensajes.last.id;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onResume: _nuevos);
    _timer = Timer.periodic(_cadaCuanto, (_) => _nuevos());
    WidgetsBinding.instance.addPostFrameCallback((_) => _alFinal(animado: false));
    _nuevos();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ciclo.dispose();
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _cercaDelFinal =>
      !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 140;

  void _alFinal({bool animado = true}) {
    if (!_scroll.hasClients) return;
    final fin = _scroll.position.maxScrollExtent;
    if (animado) {
      _scroll.animateTo(fin, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(fin);
    }
  }

  /// Trae solo lo nuevo; si quien lee está abajo, baja con los mensajes.
  Future<void> _nuevos() async {
    if (_consultando || !mounted) return;
    _consultando = true;
    try {
      final e = await _api.chat(despuesDe: _ultimoId);
      if (!mounted) return;
      if (!e.unido) {
        // se cambió de parche o salió del chat desde otro lado (por ejemplo, Telegram)
        Navigator.of(context).pop('Ya no estás en ese chat: tu parche cambió.');
        return;
      }
      final cerca = _cercaDelFinal;
      final ids = _mensajes.map((m) => m.id).toSet();
      final nuevos = e.mensajes.where((m) => !ids.contains(m.id)).toList();
      setState(() {
        _mensajes = [..._mensajes, ...nuevos];
        _miembros = e.miembros;
        _escribiendo = e.escribiendo;
        _simuladosConversan = e.simuladosConversan;
      });
      if ((nuevos.isNotEmpty || e.escribiendo.isNotEmpty) && cerca) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _alFinal());
      }
    } on ApiException {
      // sin conexión: se reintenta en la próxima vuelta
    } finally {
      _consultando = false;
    }
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final m = await _api.chatEscribir(texto);
      _texto.clear();
      if (!mounted) return;
      setState(() {
        if (!_mensajes.any((x) => x.id == m.id)) _mensajes = [..._mensajes, m];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _alFinal());
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _salir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir del chat?'),
        content: const Text('Dejas de ver los mensajes y la gente del chat deja de verte. Puedes volver cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.chatSalir();
      if (mounted) Navigator.of(context).pop('Saliste del chat del parche.');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  void _verMiembros() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Cv.surfaceRaised,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('En el chat (${_miembros.length})', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Solo ven primer nombre y universidad.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final m in _miembros)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _Avatar(nombre: m.nombre),
              title: Text(m.soyYo ? '${m.nombre} (tú)' : m.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(m.universidad),
              trailing: m.simulado ? const _SelloIA() : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = widget.estado;
    final haySimulados = _miembros.any((m) => m.simulado);
    final conEscribiendo = _escribiendo.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat del ${e.parcheNombre}',
                style: const TextStyle(fontFamily: Cv.display, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Cv.ink)),
            Text('${e.estacion} · ${e.hora} · ${_miembros.length} en el chat', style: t.bodySmall),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.groups_outlined), tooltip: 'Quiénes están', onPressed: _verMiembros),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (_) => _salir(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'salir', child: Text('Salir del chat'))],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: rellenoAncho(context, maximo: 720, arriba: 8, abajo: 12),
              itemCount: _mensajes.length + 1 + (conEscribiendo ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return _Aviso(
                    haySimulados: haySimulados,
                    simuladosConversan: _simuladosConversan,
                    vacio: _mensajes.isEmpty && !conEscribiendo,
                  );
                }
                final k = i - 1;
                if (k == _mensajes.length) return _Escribiendo(nombres: _escribiendo);
                final m = _mensajes[k];
                final anterior = k > 0 ? _mensajes[k - 1] : null;
                final mismoAutor = anterior != null &&
                    anterior.nombre == m.nombre &&
                    anterior.simulado == m.simulado &&
                    anterior.esMio == m.esMio;
                return _Burbuja(mensaje: m, conEncabezado: !mismoAutor);
              },
            ),
          ),
          _Redactor(controller: _texto, enviando: _enviando, onEnviar: _enviar),
        ],
      ),
    );
  }
}

/// Color fijo por persona, de la paleta de la marca, para distinguir quién habla.
Color _colorDe(String nombre) {
  const colores = [Cv.tealInk, Cv.coralInk, Cv.verdeInk, Cv.rojoInk];
  return colores[nombre.codeUnits.fold<int>(0, (a, b) => a + b) % colores.length];
}

String _hora(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : horaBonita('${d.hour}:${d.minute.toString().padLeft(2, '0')}');
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final color = _colorDe(nombre);
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text(
        nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
        style: const TextStyle(fontFamily: Cv.display, fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

/// Marca de estudiante simulado: siempre visible, para que nadie crea que habla con una persona real.
class _SelloIA extends StatelessWidget {
  const _SelloIA();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Estudiante simulado para la demo (IA con Gemini)',
      child: Semantics(
        label: 'simulado con IA',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Cv.tealSoft, borderRadius: BorderRadius.circular(999)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 11, color: Cv.tealInk),
              SizedBox(width: 3),
              Text('IA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Cv.tealInk)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.haySimulados, required this.simuladosConversan, required this.vacio});

  final bool haySimulados;
  final bool simuladosConversan;
  final bool vacio;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Cv.tealSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, color: Cv.tealInk, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aquí solo se ve tu primer nombre y tu universidad. No compartas tu teléfono ni tu dirección: '
                    'el encuentro es en la estación.',
                    style: t.bodySmall?.copyWith(color: Cv.ink),
                  ),
                  if (haySimulados) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Las personas con ✨ IA son estudiantes simulados para la demo, con la personalidad de su perfil'
                      '${simuladosConversan ? '.' : '. Sin Gemini configurado, solo saludan.'}',
                      style: t.bodySmall?.copyWith(color: Cv.tealInk, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (vacio) ...[
                    const SizedBox(height: 4),
                    Text('Todavía no hay mensajes: ¡saluda!', style: t.bodySmall?.copyWith(color: Cv.ink)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.conEncabezado});

  /// En pantallas anchas un mensaje largo no se vuelve una sola línea de lado a lado.
  static const _anchoBurbuja = 520.0;

  final ChatMensaje mensaje;
  final bool conEncabezado;

  @override
  Widget build(BuildContext context) {
    final m = mensaje;
    final arriba = conEncabezado ? 10.0 : 3.0;
    if (m.esMio) {
      return Padding(
        padding: EdgeInsets.only(top: arriba, left: 56),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _anchoBurbuja),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
              decoration: const BoxDecoration(
                color: Cv.coralSoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.texto, style: const TextStyle(fontSize: 15.5, height: 1.35, color: Cv.ink)),
                  const SizedBox(height: 2),
                  Text(_hora(m.creadoEn), style: const TextStyle(fontSize: 11, color: Cv.inkMuted)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: arriba, right: 56),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 34, child: conEncabezado ? _Avatar(nombre: m.nombre) : null),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (conEncabezado)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(m.nombre, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _colorDe(m.nombre))),
                        Text(m.universidad, style: const TextStyle(fontSize: 12, color: Cv.inkMuted)),
                        if (m.simulado) const _SelloIA(),
                      ],
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: _anchoBurbuja),
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
                  decoration: BoxDecoration(
                    color: Cv.surfaceRaised,
                    border: Border.all(color: Cv.line),
                    boxShadow: Cv.sombra,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.respondeA != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.subdirectory_arrow_right, size: 13, color: _colorDe(m.respondeA!)),
                              const SizedBox(width: 2),
                              Text(
                                'a ${m.respondeA}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _colorDe(m.respondeA!)),
                              ),
                            ],
                          ),
                        ),
                      Text(m.texto, style: const TextStyle(fontSize: 15.5, height: 1.35, color: Cv.ink)),
                      const SizedBox(height: 2),
                      Text(_hora(m.creadoEn), style: const TextStyle(fontSize: 11, color: Cv.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Laura está escribiendo…" con tres puntos que se mueven.
class _Escribiendo extends StatefulWidget {
  const _Escribiendo({required this.nombres});

  final List<String> nombres;

  @override
  State<_Escribiendo> createState() => _EscribiendoState();
}

class _EscribiendoState extends State<_Escribiendo> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quien = widget.nombres.join(' y ');
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 40),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: Cv.inkMuted.withValues(alpha: ((_anim.value * 3 - i) % 3) < 1 ? 0.9 : 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text('$quien está escribiendo…', style: const TextStyle(fontSize: 13, color: Cv.inkMuted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _Redactor extends StatelessWidget {
  const _Redactor({required this.controller, required this.enviando, required this.onEnviar});

  final TextEditingController controller;
  final bool enviando;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return BarraInferior(
      maximo: 720,
      relleno: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onEnviar(),
              decoration: const InputDecoration(
                hintText: 'Escribe a tu parche…',
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enviando ? null : onEnviar,
            style: IconButton.styleFrom(
              backgroundColor: Cv.coralInk,
              disabledBackgroundColor: Cv.line,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.send, size: 20, color: Colors.white),
            tooltip: 'Enviar',
          ),
        ],
      ),
    );
  }
}
