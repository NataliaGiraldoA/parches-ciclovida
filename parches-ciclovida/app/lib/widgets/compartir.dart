import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../formato.dart';
import '../theme.dart';

/// Lo que se comparte de un parche. Nada de la gente del grupo: la imagen puede terminar en
/// cualquier red social, y el grupo solo se conoce dentro de la app.
class ParcheParaCompartir {
  const ParcheParaCompartir({
    required this.nombre,
    required this.fecha,
    required this.horaNombre,
    required this.actividad,
    required this.actividadNombre,
    required this.tramoNombre,
  });

  final String nombre;
  final String fecha;
  final String horaNombre;
  final String actividad;
  final String actividadNombre;
  final String tramoNombre;

  String get texto =>
      'Este domingo voy a la CicloVida con el $nombre: ${actividadNombre.toLowerCase()} a las '
      '$horaNombre en la estación $tramoNombre. ¿Te le mides? Búscanos en Parches CicloVida 🚲';
}

/// Muestra la imagen del parche y la comparte (WhatsApp, Instagram…) con la hoja del sistema.
Future<void> abrirCompartir(BuildContext context, ParcheParaCompartir parche) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Cv.surface,
    builder: (_) => _HojaCompartir(parche: parche),
  );
}

class _HojaCompartir extends StatefulWidget {
  const _HojaCompartir({required this.parche});

  final ParcheParaCompartir parche;

  @override
  State<_HojaCompartir> createState() => _HojaCompartirState();
}

class _HojaCompartirState extends State<_HojaCompartir> {
  final _llave = GlobalKey();
  bool _ocupado = false;

  Future<void> _compartir() async {
    setState(() => _ocupado = true);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final boundary = _llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 3.2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      imagen.dispose();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png', name: 'mi-parche.png')],
          fileNameOverrides: const ['mi-parche.png'],
          text: widget.parche.texto,
        ),
      );
    } catch (_) {
      // Sin hoja para compartir archivos (algunos navegadores): al menos el texto.
      try {
        await SharePlus.instance.share(ShareParams(text: widget.parche.texto));
      } catch (_) {
        mensajero.showSnackBar(const SnackBar(content: Text('No pudimos abrir las opciones para compartir.')));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comparte tu parche', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('Invita a tus amigos. La imagen no muestra quiénes van en tu grupo.', style: t.bodySmall),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: FittedBox(
                child: DecoratedBox(
                  decoration: const BoxDecoration(boxShadow: Cv.sombra),
                  child: RepaintBoundary(
                    key: _llave,
                    child: _Postal(parche: widget.parche),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _ocupado ? null : _compartir,
              icon: _ocupado
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              label: const Text('Compartir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// La imagen: 4:5, el formato que se ve completo en Instagram y en los estados de WhatsApp.
class _Postal extends StatelessWidget {
  const _Postal({required this.parche});

  final ParcheParaCompartir parche;

  static const _crema = Color(0xFFF7F3E5);
  static const _verdeLogo = Color(0xFF0E3D2D);

  @override
  Widget build(BuildContext context) {
    final col = coloresDe(parche.actividad);
    final partesHora = parche.horaNombre.split(' ');
    return Container(
      width: 340,
      height: 425,
      color: _crema,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/img/parche-logo.png', height: 46),
          const Spacer(),
          const Text(
            'Este domingo\nvoy en parche',
            style: TextStyle(
              fontFamily: Cv.display,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: -0.5,
              color: _verdeLogo,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(Cv.radioLg),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: col.marca, width: 6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(iconoDe(parche.actividad), color: col.tinta, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        parche.actividadNombre.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                          color: col.tinta,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    parche.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Cv.display,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Cv.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        partesHora.first,
                        style: TextStyle(
                          fontFamily: Cv.display,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          height: 0.9,
                          letterSpacing: -1.5,
                          color: col.tinta,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          partesHora.skip(1).join(' '),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.tinta),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              capitalizar(fechaLarga(parche.fecha)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Cv.inkMuted),
                            ),
                            Text(
                              'Estación ${parche.tramoNombre}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Cv.ink,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text(
            '¿Te le mides? Búscanos en Parches CicloVida.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _verdeLogo),
          ),
          const SizedBox(height: 2),
          const Text(
            'Solo estudiantes de universidades de Cali, verificados.',
            style: TextStyle(fontSize: 12, color: Cv.inkMuted),
          ),
        ],
      ),
    );
  }
}
