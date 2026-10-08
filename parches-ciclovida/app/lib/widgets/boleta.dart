import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'diseno.dart';

/// Un parche de la lista, como una boleta: la hora en el talón de color y el resto al lado.
class BoletaParche extends StatelessWidget {
  const BoletaParche({super.key, required this.parche, required this.onUnirme, this.ocupado = false});

  final ParcheOpcion parche;
  final VoidCallback onUnirme;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final col = coloresDe(parche.actividad);
    final partes = parche.horaNombre.split(' ');
    final hora = partes.first;
    final sufijo = partes.skip(1).join(' ');
    final mio = parche.esMio;

    return Semantics(
      container: true,
      label: '${parche.nombre}, ${parche.actividadNombre} a las ${parche.horaNombre} en ${parche.tramoNombre}',
      child: Rebote(
        child: Material(
          color: Cv.surfaceRaised,
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shadowColor: Cv.ink.withValues(alpha: 0.18),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Cv.radioLg),
            side: mio ? BorderSide(color: col.marca, width: 3) : BorderSide.none,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 92,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [col.suave, col.brisa],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        hora,
                        style: TextStyle(
                          fontFamily: Cv.display,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: col.tinta,
                          height: 1,
                        ),
                      ),
                      Text(sufijo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: col.tinta)),
                      const SizedBox(height: 12),
                      IconoBurbuja(iconoDe(parche.actividad), color: col.tinta, fondo: Colors.white, tamano: 42),
                    ],
                  ),
                ),
                const _CorteVertical(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                parche.actividadNombre.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: col.tinta),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (mio)
                              Sello('Estás aquí', fondo: col.suave, color: col.tinta, icono: Icons.check_circle)
                            else if (parche.paraTi)
                              const Sello('Para ti', fondo: Cv.coralSoft, color: Cv.coralInk, icono: Icons.auto_awesome),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(parche.nombre, style: t.headlineSmall),
                        const SizedBox(height: 4),
                        Text('Estación ${parche.tramoNombre}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Cv.ink)),
                        Text(
                          parche.referencia.isEmpty ? parche.puntoEncuentro : '${parche.puntoEncuentro} · ${parche.referencia}',
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (parche.inscritos > 0) ...[
                          PuntosGente(cantidad: parche.inscritos, color: col.marca, colorTexto: col.tinta),
                          const SizedBox(height: 6),
                        ],
                        Text(_textoGente(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Cv.inkMuted)),
                        if (!mio) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: ocupado ? null : onUnirme,
                              style: botonDeColor(col.tinta, minimo: const Size(132, 46)),
                              child: const Text('Unirme'),
                            ),
                          ),
                        ],
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

  String _textoGente() {
    final n = parche.inscritos;
    if (n == 0) return 'Nadie todavía: estrena este parche';
    final unis = parche.universidades;
    final de = unis <= 1 ? '' : ' de $unis universidades';
    final ritmo = parche.ritmoNombre == null ? '' : ', la mayoría a ritmo ${parche.ritmoNombre!.toLowerCase()}';
    return '${n == 1 ? '1 estudiante va' : '$n estudiantes van'}$de$ritmo';
  }
}

/// El corte de la boleta: muescas arriba y abajo (del color de la página) y una línea punteada.
class _CorteVertical extends StatelessWidget {
  const _CorteVertical();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Column(
        children: [
          Container(
            width: 14,
            height: 7,
            decoration: const BoxDecoration(
              color: Cv.surface,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
          ),
          const Expanded(child: Center(child: LineaPunteada(vertical: true))),
          Container(
            width: 14,
            height: 7,
            decoration: const BoxDecoration(
              color: Cv.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un punto por persona inscrita, hasta ocho; el resto se cuenta al final. Solo cifras: antes
/// del sábado nadie ve quién va.
class PuntosGente extends StatelessWidget {
  const PuntosGente({super.key, required this.cantidad, required this.color, this.colorTexto = Cv.inkMuted});

  static const _maximo = 8;

  final int cantidad;

  /// Color de los puntos (decorativo, puede ser el tono marca).
  final Color color;

  /// Color del "+N" (un tono Ink o gris tinta, para que se lea).
  final Color colorTexto;

  @override
  Widget build(BuildContext context) {
    final visibles = cantidad > _maximo ? _maximo : cantidad;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < visibles; i++)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 2)),
            ),
          if (cantidad > _maximo)
            Text('+${cantidad - _maximo}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorTexto)),
        ],
      ),
    );
  }
}
