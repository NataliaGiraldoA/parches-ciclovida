import 'package:flutter/material.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import 'diseno.dart';

/// Atajos de la demo: lo que en la vida real pasa solo durante la semana (el sábado se arman los
/// grupos; el domingo, al terminar la CicloVida, se abre la encuesta), adelantado con un toque.
/// Usan las acciones de administración, así que mueven la semana para todo el servidor.

Future<String> demoArmarGrupos(String clave) async {
  final r = await Sesion.actual.api.adminArmarGrupos(clave);
  return 'K-means armó ${r['grupos']} grupos con ${r['emparejados']} estudiantes. '
      '${r['movidos']} se sumaron a otro parche y ${r['solos']} quedaron sin compañía.';
}

Future<String> demoTerminarDomingo(String clave) async {
  final r = await Sesion.actual.api.adminFinalizar(clave);
  return 'Jornada del ${r['finalizada']} terminada. Ya se puede responder la encuesta.';
}

enum PasoDemo { armarGrupos, terminarDomingo, responderEncuesta }

/// Lo que se hizo en la hoja: el paso y, si el servidor respondió algo, su mensaje.
class ResultadoDemo {
  const ResultadoDemo(this.paso, [this.mensaje]);

  final PasoDemo paso;
  final String? mensaje;
}

/// Hoja "Adelanta la semana": los tres momentos de la semana en orden, y solo se puede tocar el que
/// toca según el estado de la persona (sin grupo no se termina el domingo, por ejemplo).
Future<ResultadoDemo?> abrirHojaDemo(BuildContext context, {required EstadoParche estado}) {
  return showModalBottomSheet<ResultadoDemo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaDemo(estado: estado),
  );
}

/// El chip "Demo" de la barra de arriba, que abre la hoja.
class BotonDemo extends StatelessWidget {
  const BotonDemo({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: 'Adelantar la semana (demo)',
        child: Semantics(
          button: true,
          label: 'Modo demo: adelantar la semana',
          child: ExcludeSemantics(
            child: Rebote(
              child: Material(
                color: Cv.coralSoft,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(10, 8, 14, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fast_forward_rounded, size: 18, color: Cv.coralInk),
                        SizedBox(width: 4),
                        Text('Demo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Cv.coralInk)),
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

enum _Fase { lista, activa, bloqueada }

class _DefPaso {
  const _DefPaso(this.paso, this.titulo, this.texto, this.accion, this.bloqueo, this.icono);

  final PasoDemo paso;
  final String titulo;
  final String texto;
  final String accion;

  /// Qué falta para poder tocarlo.
  final String bloqueo;
  final IconData icono;
}

class _HojaDemo extends StatefulWidget {
  const _HojaDemo({required this.estado});

  final EstadoParche estado;

  @override
  State<_HojaDemo> createState() => _HojaDemoState();
}

class _HojaDemoState extends State<_HojaDemo> {
  PasoDemo? _corriendo;
  String? _error;

  EstadoParche get _e => widget.estado;

  /// La semana en curso: ya eligió parche (antes o después de armarse los grupos).
  bool get _enSemana => _e.estado == 'inscrito' || _e.estado == 'asignado';

  _Fase _fase(PasoDemo p) {
    switch (p) {
      case PasoDemo.armarGrupos:
        if (_e.estado == 'asignado') return _Fase.lista;
        if (_e.estado == 'inscrito') return _Fase.activa;
        return _e.encuesta != null ? _Fase.lista : _Fase.bloqueada;
      case PasoDemo.terminarDomingo:
        if (_e.estado == 'asignado') return _Fase.activa;
        if (_enSemana) return _Fase.bloqueada;
        return _e.encuesta != null ? _Fase.lista : _Fase.bloqueada;
      case PasoDemo.responderEncuesta:
        if (_e.encuestaPendiente) return _Fase.activa;
        if (_enSemana) return _Fase.bloqueada;
        return (_e.encuesta?.respondida ?? false) ? _Fase.lista : _Fase.bloqueada;
    }
  }

  Future<void> _hacer(PasoDemo p) async {
    if (p == PasoDemo.responderEncuesta) {
      Navigator.of(context).pop(const ResultadoDemo(PasoDemo.responderEncuesta));
      return;
    }
    setState(() {
      _corriendo = p;
      _error = null;
    });
    try {
      final clave = Sesion.actual.claveAdmin;
      final msg = p == PasoDemo.armarGrupos ? await demoArmarGrupos(clave) : await demoTerminarDomingo(clave);
      if (mounted) Navigator.of(context).pop(ResultadoDemo(p, msg));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _corriendo = null;
        _error = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pasos = [
      const _DefPaso(PasoDemo.armarGrupos, 'Sábado, 5:00 p. m.', 'Se arman los grupos de 3 a 6 con k-means.',
          'Armar los grupos', 'Primero únete a un parche.', Icons.diversity_3),
      _DefPaso(PasoDemo.terminarDomingo, 'Domingo, ${horaBonita(_e.fin)}', 'Termina la CicloVida y se abre la encuesta.',
          'Terminar el domingo', 'Primero se arma tu grupo.', Icons.flag),
      const _DefPaso(PasoDemo.responderEncuesta, 'Encuesta de satisfacción', 'Tres preguntas, menos de un minuto.',
          'Responder la encuesta', 'Se abre al terminar el domingo.', Icons.rate_review_outlined),
    ];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            const IconoBurbuja(Icons.fast_forward_rounded, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Rotulo('Modo demo', color: Cv.coral),
                  const SizedBox(height: 4),
                  Text('Adelanta la semana', style: t.headlineMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'En la vida real esto pasa solo: el sábado se arman los grupos y el domingo, al terminar la '
          'CicloVida, se abre la encuesta. Aquí lo adelantas con un toque.',
          style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < pasos.length; i++)
          _Paso(
            def: pasos[i],
            fase: _fase(pasos[i].paso),
            corriendo: _corriendo == pasos[i].paso,
            ocupado: _corriendo != null,
            ultimo: i == pasos.length - 1,
            onTap: () => _hacer(pasos[i].paso),
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          BloqueColor(
            color: Cv.brisaRojo,
            borde: Cv.rojoSoft,
            relleno: const EdgeInsets.all(14),
            radio: Cv.radioMd,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 20, color: Cv.rojoInk),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: t.bodyMedium)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline, size: 16, color: Cv.inkMuted),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Mueve la semana para todos los que usan este servidor. La clave de demo se cambia en Ajustes.',
                style: t.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Un momento de la semana: nodo (listo, el que sigue o bloqueado), texto y su acción.
class _Paso extends StatelessWidget {
  const _Paso({
    required this.def,
    required this.fase,
    required this.corriendo,
    required this.ocupado,
    required this.ultimo,
    required this.onTap,
  });

  final _DefPaso def;
  final _Fase fase;
  final bool corriendo;
  final bool ocupado;
  final bool ultimo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (color, fondo) = switch (fase) {
      _Fase.lista => (Cv.verdeInk, Cv.verdeSoft),
      _Fase.activa => (Cv.coralInk, Cv.coralSoft),
      _Fase.bloqueada => (Cv.inkMuted, Cv.line),
    };
    final activa = fase == _Fase.activa;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: activa ? color : fondo,
                    shape: BoxShape.circle,
                    boxShadow: activa ? Cv.brillo(color) : null,
                  ),
                  child: Icon(
                    fase == _Fase.lista ? Icons.check : def.icono,
                    color: activa ? Colors.white : color,
                    size: 22,
                  ),
                ),
                if (!ultimo)
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Center(child: LineaPunteada(vertical: true, grosor: 2)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: ultimo ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(def.titulo, style: t.titleMedium)),
                      if (fase == _Fase.lista) const Sello('Listo', fondo: Cv.verdeSoft, color: Cv.verdeInk, icono: Icons.check),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(def.texto, style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
                  if (activa) ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: ocupado ? null : onTap,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: corriendo
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cv.tealInk))
                          : Text(def.accion),
                    ),
                  ] else if (fase == _Fase.bloqueada) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 15, color: Cv.inkMuted),
                        const SizedBox(width: 4),
                        Flexible(child: Text(def.bloqueo, style: t.bodySmall)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
