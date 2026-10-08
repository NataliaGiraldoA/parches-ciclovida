import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'comunes.dart';
import 'diseno.dart';

/// La tarjeta central de la app: con quién vas, dónde y a qué hora.
class ParcheCard extends StatelessWidget {
  const ParcheCard({
    super.key,
    required this.grupo,
    required this.miRespuesta,
    required this.ajustes,
    required this.ocupado,
    required this.onResponder,
    required this.onReportar,
    this.onCambiar,
    this.onSalir,
  });

  final Grupo grupo;
  final String? miRespuesta;
  final List<String> ajustes;
  final bool ocupado;
  final ValueChanged<bool> onResponder;
  final VoidCallback onReportar;
  final VoidCallback? onCambiar;
  final VoidCallback? onSalir;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final col = coloresDe(grupo.actividad);
    final notas = <String>[
      if (ajustes.contains('franja'))
        'Tu parche no alcanzó a 3 personas, así que te sumamos al más parecido: sale a las ${grupo.horaNombre}.',
      if (ajustes.contains('actividad') && !ajustes.contains('franja'))
        'Tu parche no alcanzó a 3 personas, así que te sumamos al más parecido: va a ${grupo.actividadNombre.toLowerCase()}.',
      if (grupo.miembros.length == 1)
        'Esta vez nadie más eligió un parche compatible. Si alguien se une antes del domingo, te avisamos.',
    ];
    final partesHora = grupo.horaNombre.split(' ');
    final hora = partesHora.first;
    final sufijo = partesHora.skip(1).join(' ');

    // Un pase de abordar: cabecera oscura con la cinta, corte perforado y el grupo abajo.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Cv.radioLg), boxShadow: Cv.sombra),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Cv.radioLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FondoCarril(
              borde: BorderRadius.zero,
              colores: [col.brisa, col.suave],
              intensidad: 0.9,
              sombra: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Rotulo('Tu grupo del domingo', color: col.marca)),
                        IconoBurbuja(iconoDe(grupo.actividad), color: col.tinta, fondo: Colors.white, tamano: 46),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 56),
                      child: Text(grupo.nombre, style: t.displaySmall),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          hora,
                          style: TextStyle(
                            fontFamily: Cv.display,
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            height: 0.9,
                            color: col.tinta,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(sufijo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: col.tinta)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(Cv.radioMd),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  grupo.actividadNombre.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: col.tinta),
                                ),
                                Text(
                                  'Estación ${grupo.tramoNombre}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Cv.ink, height: 1.25),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Perforacion(),
            Container(
              color: Cv.surfaceRaised,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Dato(
                    icono: Icons.place,
                    color: col.tinta,
                    titulo: grupo.puntoEncuentro,
                    detalle: grupo.referencia.isEmpty
                        ? 'Comuna ${grupo.tramoComuna}'
                        : '${grupo.referencia} · comuna ${grupo.tramoComuna}',
                  ),
                  const SizedBox(height: 14),
                  _Dato(
                    icono: Icons.schedule,
                    color: col.tinta,
                    titulo: 'Llega unos minutos antes',
                    detalle: 'Busca a tu parche en la estación. Van a ritmo ${grupo.ritmoNombre.toLowerCase()}.',
                  ),
                  for (final n in notas) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: col.suave, borderRadius: BorderRadius.circular(Cv.radioMd)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 20, color: col.tinta),
                          const SizedBox(width: 10),
                          Expanded(child: Text(n, style: t.bodyMedium)),
                        ],
                      ),
                    ),
                  ],
                  const Divider(),
                  Row(
                    children: [
                      AvatarPila(
                        nombres: [for (final m in grupo.miembros) m.nombre],
                        colores: [for (final m in grupo.miembros) coloresDe(m.actividad).tinta],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Van ${grupo.miembros.length}', style: t.titleMedium),
                            Text('${grupo.confirmados} ya confirmaron', style: t.bodySmall),
                          ],
                        ),
                      ),
                      const Icon(Icons.verified, size: 18, color: Cv.verdeInk, semanticLabel: 'Todos verificados'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Todos verificaron su correo universitario.', style: t.bodySmall),
                  const SizedBox(height: 8),
                  for (final m in grupo.miembros) _FilaMiembro(miembro: m),
                  const SizedBox(height: 8),
                  _Respuesta(miRespuesta: miRespuesta, ocupado: ocupado, onResponder: onResponder),
                  if (onCambiar != null || onSalir != null)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        if (onCambiar != null)
                          TextButton.icon(
                            onPressed: ocupado ? null : onCambiar,
                            icon: const Icon(Icons.swap_horiz, size: 20),
                            label: const Text('Cambiar de parche'),
                          ),
                        if (onSalir != null)
                          TextButton(
                            onPressed: ocupado ? null : onSalir,
                            style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                            child: const Text('Salirme'),
                          ),
                      ],
                    ),
                  const Divider(),
                  _Seguridad(onReportar: onReportar),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.color, required this.titulo, required this.detalle});

  final IconData icono;
  final Color color;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: t.titleMedium),
              const SizedBox(height: 2),
              Text(detalle, style: t.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaMiembro extends StatelessWidget {
  const _FilaMiembro({required this.miembro});

  final Miembro miembro;

  @override
  Widget build(BuildContext context) {
    final col = coloresDe(miembro.actividad);
    final inicial = miembro.nombre.isEmpty ? '?' : miembro.nombre.substring(0, 1).toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: col.tinta,
            child: Text(inicial, style: const TextStyle(fontFamily: Cv.display, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  miembro.soyYo ? '${miembro.nombre} (tú)' : miembro.nombre,
                  style: TextStyle(fontSize: 16, fontWeight: miembro.soyYo ? FontWeight.w700 : FontWeight.w500, color: Cv.ink),
                ),
                if (miembro.universidad.isNotEmpty)
                  Text(miembro.universidad, style: const TextStyle(fontSize: 13, color: Cv.inkMuted)),
              ],
            ),
          ),
          EtiquetaEstado(miembro.estado),
        ],
      ),
    );
  }
}

class _Respuesta extends StatelessWidget {
  const _Respuesta({required this.miRespuesta, required this.ocupado, required this.onResponder});

  final String? miRespuesta;
  final bool ocupado;
  final ValueChanged<bool> onResponder;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (miRespuesta) {
      case 'confirmado':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Cv.verdeSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Cv.verdeInk),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Confirmaste. Nos vemos el domingo.', style: t.titleMedium?.copyWith(color: Cv.verdeInk))),
                ],
              ),
            ),
            TextButton(onPressed: ocupado ? null : () => onResponder(false), child: const Text('Ya no puedo ir')),
          ],
        );
      case 'declinado':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Avisaste que esta vez no vas. Tu parche ya lo sabe.', style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: ocupado ? null : () => onResponder(true), child: const Text('Cambié de opinión, sí voy')),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Vas el domingo? Confirma para que tu parche te espere.', style: t.titleMedium),
            const SizedBox(height: 10),
            FilledButton(onPressed: ocupado ? null : () => onResponder(true), child: const Text('Confirmo, voy')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: ocupado ? null : () => onResponder(false), child: const Text('Esta vez no puedo')),
          ],
        );
    }
  }
}

/// Mitigación del riesgo principal: encuentros entre desconocidos.
class _Seguridad extends StatelessWidget {
  const _Seguridad({required this.onReportar});

  final VoidCallback onReportar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, size: 20, color: Cv.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Se encuentran solo en la estación y en horario de CicloVida. '
                'No compartas tu dirección ni tu número. En una emergencia llama al 123.',
                style: t.bodySmall,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onReportar,
            icon: const Icon(Icons.flag_outlined, size: 20),
            label: const Text('Reportar un problema'),
            style: TextButton.styleFrom(foregroundColor: Cv.rojoInk),
          ),
        ),
      ],
    );
  }
}
