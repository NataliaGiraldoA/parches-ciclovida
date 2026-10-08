import 'package:flutter/material.dart';

import '../formato.dart';
import '../models.dart';
import '../theme.dart';
import 'diseno.dart';

/// El clima del domingo a la hora del parche, a lo ancho: la cifra a la izquierda, el consejo al lado.
class TarjetaClima extends StatelessWidget {
  const TarjetaClima({super.key, required this.clima});

  final Clima clima;

  static IconData _icono(String icono) => switch (icono) {
    'sol' => Icons.wb_sunny_outlined,
    'nubes_sol' => Icons.wb_cloudy_outlined,
    'lluvia' => Icons.umbrella_outlined,
    'tormenta' => Icons.thunderstorm_outlined,
    _ => Icons.cloud_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label:
          'Clima del domingo a las ${horaBonita(clima.hora)}: ${clima.cielo}, ${clima.temperatura} grados, '
          '${clima.lluvia} por ciento de lluvia. ${clima.consejo}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(color: Cv.tealSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
        child: Row(
          children: [
            Icon(_icono(clima.icono), color: Cv.tealInk, size: 30),
            const SizedBox(width: 6),
            Text(
              '${clima.temperatura}°',
              style: const TextStyle(
                fontFamily: Cv.display,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1,
                color: Cv.tealInk,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${clima.cielo} · ${clima.lluvia} % de lluvia a las ${horaBonita(clima.hora)}',
                    style: t.titleSmall?.copyWith(color: Cv.ink, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(clima.consejo, style: t.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El chip de la racha en la barra de arriba: la llama y el número. Abre el detalle.
class BotonRacha extends StatelessWidget {
  const BotonRacha({super.key, required this.racha, required this.onTap});

  final Racha racha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = racha.actual;
    final viva = n > 0;
    return Center(
      child: Tooltip(
        message: 'Tu racha de domingos',
        child: Semantics(
          button: true,
          label: 'Tu racha: $n ${n == 1 ? 'domingo seguido' : 'domingos seguidos'}',
          child: ExcludeSemantics(
            child: Rebote(
              child: Material(
                color: viva ? Cv.coralSoft : Cv.line.withValues(alpha: 0.6),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department, size: 20, color: viva ? Cv.coralInk : Cv.inkMuted),
                        const SizedBox(width: 2),
                        Text(
                          '$n',
                          style: TextStyle(
                            fontFamily: Cv.display,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: viva ? Cv.coralInk : Cv.inkMuted,
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
      ),
    );
  }
}

/// El detalle de la racha. Devuelve true si la persona quiere ver sus domingos.
Future<bool?> abrirRacha(BuildContext context, Racha racha) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaRacha(racha: racha),
  );
}

class _HojaRacha extends StatelessWidget {
  const _HojaRacha({required this.racha});

  final Racha racha;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = racha.actual;
    final String titulo;
    final String detalle;
    if (n > 0) {
      titulo = n == 1 ? '1 domingo seguido' : '$n domingos seguidos';
      detalle = racha.mejor > n
          ? 'Tu mejor racha fue de ${racha.mejor}. ¡Ve por ella!'
          : 'Si vas este domingo, llegas a ${n + 1}.';
    } else if (racha.total > 0) {
      titulo = 'Retoma tu racha';
      detalle = 'Tu mejor racha fue de ${racha.mejor}. Arranca otra este domingo.';
    } else {
      titulo = 'Empieza tu racha';
      detalle = 'Cada domingo que vayas a tu parche suma uno.';
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            IconoBurbuja(
              Icons.local_fire_department,
              color: n > 0 ? Cv.coralInk : Cv.inkMuted,
              fondo: n > 0 ? Cv.coralSoft : Cv.line,
              tamano: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Rotulo('Tu racha', color: Cv.coral),
                  const SizedBox(height: 4),
                  Text(titulo, style: t.headlineMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(detalle, style: t.bodyLarge),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Cifra(numero: racha.mejor, texto: 'mejor racha'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Cifra(numero: racha.total, texto: racha.total == 1 ? 'domingo en total' : 'domingos en total'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Cuenta cada domingo que vas a tu parche: lo que respondes en la encuesta o, si no la respondes, '
          'si habías confirmado. Si faltas un domingo, la racha vuelve a empezar.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.history, size: 20),
          label: const Text('Ver mis domingos'),
        ),
      ],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: Cv.brisaCoral, borderRadius: BorderRadius.circular(Cv.radioMd)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$numero',
            style: const TextStyle(
              fontFamily: Cv.display,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: Cv.coralInk,
            ),
          ),
          Text(
            texto,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Cv.inkMuted),
          ),
        ],
      ),
    );
  }
}
