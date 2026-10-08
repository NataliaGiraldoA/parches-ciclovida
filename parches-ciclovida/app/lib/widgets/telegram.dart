import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import 'diseno.dart';

/// El ícono de Telegram de la barra de arriba. Conectado (punto verde), abre el chat del bot; sin
/// conectar, abre la hoja para vincularlo. Si el backend no tiene bot, no aparece.
class BotonTelegram extends StatefulWidget {
  const BotonTelegram({super.key});

  @override
  State<BotonTelegram> createState() => _BotonTelegramState();
}

class _BotonTelegramState extends State<BotonTelegram> {
  TelegramInfo? _info;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<TelegramInfo?> _cargar() async {
    try {
      final info = await Sesion.actual.api.telegram();
      if (mounted) setState(() => _info = info);
    } on ApiException {
      // sin conexión: se queda con lo último que supo
    }
    return _info;
  }

  Future<void> _tocar() async {
    final info = await _cargar(); // fresco: pudo conectarse o desconectarse desde otro lado
    if (info == null || !mounted) return;
    final bot = info.bot;
    if (info.vinculado && bot != null) {
      final enlace = kIsWeb ? 'https://web.telegram.org/k/#@$bot' : 'https://t.me/$bot';
      final ok = await launchUrl(
        Uri.parse(enlace),
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pude abrir Telegram. Búscanos como @$bot.')));
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: TarjetaTelegram(),
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || !info.disponible) return const SizedBox.shrink();
    return IconButton(
      tooltip: info.vinculado ? 'Abrir el chat de Telegram' : 'Conectar Telegram',
      onPressed: _tocar,
      icon: Badge(
        isLabelVisible: info.vinculado,
        backgroundColor: Cv.verde,
        smallSize: 9,
        child: Icon(Icons.telegram, color: info.vinculado ? Cv.tealInk : null),
      ),
    );
  }
}

/// Tarjeta para vincular el bot de Telegram: por ahí llegan los avisos y desde el chat
/// se puede elegir parche, confirmar y publicar en el foro. Si el backend no tiene bot, no se muestra.
///
/// En el navegador abre Telegram Web con el código incluido (t.me intenta abrir la app instalada
/// y, al pasar a la web, suele perder el código). Siempre muestra el código como respaldo.
class TarjetaTelegram extends StatefulWidget {
  const TarjetaTelegram({super.key});

  @override
  State<TarjetaTelegram> createState() => _TarjetaTelegramState();
}

class _TarjetaTelegramState extends State<TarjetaTelegram> {
  TelegramInfo? _info;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final info = await Sesion.actual.api.telegram();
      if (mounted) setState(() => _info = info);
    } on ApiException {
      // sin conexión o sin bot: la tarjeta simplemente no aparece
    }
  }

  Future<void> _abrir(String? enlace) async {
    if (enlace == null) return;
    final ok = await launchUrl(
      Uri.parse(enlace),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude abrir Telegram. Escríbele al bot: /start ${_info?.codigo ?? ''}')),
      );
    }
    // al volver de Telegram, refresca varias veces para mostrar el vínculo apenas llegue
    for (final s in const [4, 10, 20]) {
      Future<void>.delayed(Duration(seconds: s), () {
        if (mounted && !(_info?.vinculado ?? true)) _cargar();
      });
    }
  }

  /// Suelta el chat de esta cuenta: así se puede conectar el mismo Telegram a otra (útil en la demo).
  Future<void> _desconectar() async {
    try {
      await Sesion.actual.api.desconectarTelegram();
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telegram desconectado de esta cuenta.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _copiarCodigo() async {
    final codigo = _info?.codigo;
    if (codigo == null) return;
    await Clipboard.setData(ClipboardData(text: '/start $codigo'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copiado. Pégalo en el chat del bot y envíalo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || !info.disponible) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    // en el navegador, Telegram Web; en el celular, la app de Telegram
    final principal = kIsWeb ? (info.enlaceWeb ?? info.enlace) : info.enlace;
    return Card(
      color: Cv.brisaTeal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Cv.radioLg),
        side: const BorderSide(color: Cv.tealSoft, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconoBurbuja(Icons.telegram, color: Cv.tealInk, fondo: Colors.white, tamano: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.vinculado ? 'Telegram conectado' : 'Conecta Telegram',
                        style: t.titleMedium?.copyWith(color: Cv.tealInk),
                      ),
                      Text(
                        info.vinculado
                            ? 'Desde el chat puedes elegir parche, confirmar y publicar en el foro.'
                            : 'Te avisamos por ahí, y desde el chat eliges parche, confirmas y publicas en el foro.',
                        style: t.bodySmall?.copyWith(color: Cv.ink),
                      ),
                    ],
                  ),
                ),
                if (info.vinculado) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: Cv.verdeInk, size: 28),
                ],
              ],
            ),
            if (info.vinculado)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _desconectar,
                  style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                  child: const Text('Desconectar'),
                ),
              ),
            if (!info.vinculado) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: principal == null ? null : () => _abrir(principal),
                style: botonDeColor(Cv.tealInk, minimo: const Size.fromHeight(46)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(kIsWeb ? 'Abrir en Telegram Web' : 'Conectar'),
              ),
              if (kIsWeb && info.enlace != null)
                TextButton(
                  onPressed: () => _abrir(info.enlace),
                  child: const Text('Prefiero la app de Telegram'),
                ),
              if (info.codigo != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Si al tocar Start no pasa nada, envíale este mensaje al bot'
                  '${info.bot == null ? '' : ' @${info.bot}'}:',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 6),
                Material(
                  color: Cv.surfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Cv.radioMd),
                    side: const BorderSide(color: Cv.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Cv.radioMd),
                    onTap: _copiarCodigo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              '/start ${info.codigo}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Icon(Icons.copy, size: 18, color: Cv.tealInk, semanticLabel: 'Copiar'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
