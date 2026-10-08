import 'package:flutter/material.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';

/// Historial: los domingos pasados, a qué parche fue y la gente que lo acompañó.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  List<HistorialItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final items = await Sesion.actual.api.historial();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis domingos')),
      body: items == null
          ? ListView(
              padding: rellenoAncho(context, arriba: 8, abajo: 24),
              children: _error == null
                  ? const [
                      Esqueleto(alto: 120),
                      SizedBox(height: 12),
                      Esqueleto(alto: 190),
                      SizedBox(height: 12),
                      Esqueleto(alto: 190),
                    ]
                  : [TarjetaError(mensaje: _error!, reintentar: _cargar)],
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: rellenoAncho(context, arriba: 24, abajo: 24),
                      children: const [
                        EstadoVacio(
                          emoji: '🚲',
                          fondo: Cv.brisaCoral,
                          titulo: 'Todavía no tienes domingos en tu historia.',
                          texto: 'Elige un parche y estrénala este fin de semana.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: rellenoAncho(context, arriba: 8, abajo: 32),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final idas = items.where((x) => x.asistio == true).length;
                          // el resumen en grande, como una tarjeta para compartir
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: BloqueColor(
                              color: Cv.brisaCoral,
                              borde: Cv.coralSoft,
                              relleno: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                              child: Row(
                                children: [
                                  Text(
                                    idas == 0 ? '${items.length}' : '$idas',
                                    style: Theme.of(context).textTheme.displayMedium?.copyWith(color: Cv.coralInk),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      idas == 0
                                          ? '${items.length} ${items.length == 1 ? 'domingo' : 'domingos'} con parche'
                                          : 'Has ido $idas de ${items.length} ${items.length == 1 ? 'domingo' : 'domingos'} con parche',
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return _TarjetaDomingo(item: items[i - 1]);
                      },
                    ),
            ),
    );
  }
}

class _TarjetaDomingo extends StatelessWidget {
  const _TarjetaDomingo({required this.item});

  final HistorialItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final g = item.grupo;
    final col = coloresDe(g.actividad);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 6, color: col.marca),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(capitalizar(fechaLarga(item.fecha)), style: t.titleMedium)),
                    _SelloAsistencia(asistio: item.asistio),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconoBurbuja(iconoDe(g.actividad), color: col.tinta, fondo: col.suave, tamano: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.nombre, style: t.headlineSmall),
                          Text(
                            '${g.actividadNombre} · ${g.horaNombre} · Estación ${g.tramoNombre}',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Saliste con', style: t.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in g.miembros)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: m.soyYo ? col.tinta : col.suave,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          m.soyYo ? 'Tú' : '${m.nombre} · ${m.universidad}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: m.soyYo ? Colors.white : col.tinta,
                          ),
                        ),
                      ),
                  ],
                ),
                if (item.volveria == true) ...[
                  const SizedBox(height: 8),
                  Text('Dijiste que volverías 💪', style: t.bodySmall?.copyWith(color: Cv.verdeInk)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fuiste / No fuiste / Sin responder: siempre con palabra, nunca solo color.
class _SelloAsistencia extends StatelessWidget {
  const _SelloAsistencia({required this.asistio});

  final bool? asistio;

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, tinta) = switch (asistio) {
      true => ('Fuiste', Cv.verdeSoft, Cv.verdeInk),
      false => ('No fuiste', Cv.rojoSoft, Cv.rojoInk),
      null => ('Sin responder', Cv.line, Cv.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tinta)),
    );
  }
}
