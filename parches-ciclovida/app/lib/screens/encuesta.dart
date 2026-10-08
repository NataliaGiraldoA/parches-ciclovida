import 'package:flutter/material.dart';

import '../api.dart';
import '../formato.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';

/// Después del domingo: ¿fuiste?, ¿cómo te sentiste del 1 al 5?, ¿volverías?
/// Con la misma estética del quiz: una tarjeta numerada por pregunta, cada una con su color.
class EncuestaScreen extends StatefulWidget {
  const EncuestaScreen({super.key, required this.info});

  final EncuestaInfo info;

  @override
  State<EncuestaScreen> createState() => _EncuestaScreenState();
}

/// Cada pregunta toma un color de la cinta, en su tono Ink (el número blanco encima cumple AA).
const _colores = [Cv.rojoInk, Cv.coralInk, Cv.verdeInk, Cv.tealInk];
const _brisas = [Cv.brisaRojo, Cv.brisaCoral, Cv.brisaVerde, Cv.brisaTeal];

class _EncuestaScreenState extends State<EncuestaScreen> {
  bool? _asistio;
  int? _bienestar;
  bool? _volveria;
  bool _enviando = false;

  bool get _valida => _asistio != null && _volveria != null;

  /// Las obligatorias que faltan (la de cómo te sentiste es opcional y no cuenta).
  int get _faltan => (_asistio == null ? 1 : 0) + (_volveria == null ? 1 : 0);

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      await Sesion.actual.api.enviarEncuesta(
        asistio: _asistio!,
        volveria: _volveria!,
        bienestar: _asistio! ? _bienestar : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final grupo = widget.info.grupoNombre ?? 'tu parche';
    final numeroVolveria = _asistio == true ? 3 : 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Encuesta del domingo')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: '${2 - _faltan} de 2 preguntas obligatorias respondidas',
              child: Cinta(alto: 6, llenos: (2 - _faltan) * 2),
            ),
            Expanded(
              child: ListView(
                padding: rellenoAncho(context, arriba: 16, abajo: 24),
                children: [
                  BloqueColor(
                    color: Cv.brisaCoral,
                    borde: Cv.coralSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¿Cómo te fue? 🚲', style: t.headlineMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Domingo ${fechaCorta(widget.info.jornadaFecha)} con el $grupo. '
                          'Tres preguntas, menos de un minuto.',
                          style: t.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Pregunta(
                    numero: 1,
                    titulo: '¿Fuiste a la CicloVida con tu parche?',
                    child: SiNo(
                      valor: _asistio,
                      si: 'Sí, fui',
                      no: 'No fui',
                      colorSeleccion: _colores[0],
                      fondoSeleccion: _brisas[0],
                      onChanged: (v) => setState(() => _asistio = v),
                    ),
                  ),
                  if (_asistio == true) ...[
                    const SizedBox(height: 14),
                    _Pregunta(
                      numero: 2,
                      titulo: '¿Cómo te sentiste? (opcional)',
                      ayuda: '1 es muy mal y 5 es muy bien. Puedes dejarla sin responder.',
                      child: EscalaBienestar(
                        valor: _bienestar,
                        color: _colores[1],
                        // tocar de nuevo el mismo número lo desmarca
                        onChanged: (v) => setState(() => _bienestar = _bienestar == v ? null : v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _Pregunta(
                    numero: numeroVolveria,
                    titulo: '¿Volverías el próximo domingo?',
                    child: SiNo(
                      valor: _volveria,
                      colorSeleccion: _colores[numeroVolveria - 1],
                      fondoSeleccion: _brisas[numeroVolveria - 1],
                      onChanged: (v) => setState(() => _volveria = v),
                    ),
                  ),
                ],
              ),
            ),
            BarraInferior(
              child: FilledButton(
                onPressed: _valida && !_enviando ? _enviar : null,
                child: _enviando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cv.tealInk))
                    : Text(_valida ? 'Enviar' : 'Te ${_faltan == 1 ? 'falta 1' : 'faltan $_faltan'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una pregunta en su tarjeta: número en un círculo del color de la pregunta y el título grande.
class _Pregunta extends StatelessWidget {
  const _Pregunta({required this.numero, required this.titulo, required this.child, this.ayuda});

  final int numero;
  final String titulo;
  final String? ayuda;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = _colores[(numero - 1) % _colores.length];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: Cv.brillo(color)),
                  child: Text(
                    '$numero',
                    style: const TextStyle(fontFamily: Cv.display, fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: t.headlineSmall),
                        if (ayuda != null) ...[
                          const SizedBox(height: 4),
                          Text(ayuda!, style: t.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Escala de 1 a 5. El número, la carita y la palabra siempre se ven: no depende del color.
class EscalaBienestar extends StatelessWidget {
  const EscalaBienestar({super.key, required this.valor, required this.onChanged, this.color = Cv.tealInk});

  static const etiquetas = ['Muy mal', 'Mal', 'Regular', 'Bien', 'Muy bien'];
  static const caritas = ['😣', '🙁', '😐', '🙂', '😄'];

  final int? valor;
  final ValueChanged<int> onChanged;

  /// Relleno del número elegido (un tono Ink: el número va en blanco encima).
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: valor == i,
              label: '$i, ${etiquetas[i - 1]}',
              child: Rebote(
                child: InkWell(
                  borderRadius: BorderRadius.circular(Cv.radioMd),
                  onTap: () => onChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: valor == i ? color : Cv.surfaceRaised,
                            border: Border.all(color: valor == i ? color : Cv.lineStrong, width: 2),
                            boxShadow: valor == i ? Cv.brillo(color) : null,
                          ),
                          child: Text(
                            '$i',
                            style: TextStyle(
                              fontFamily: Cv.display,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: valor == i ? Colors.white : Cv.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ExcludeSemantics(child: Text(caritas[i - 1], style: const TextStyle(fontSize: 20, height: 1.1))),
                        const SizedBox(height: 2),
                        Text(
                          etiquetas[i - 1],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: valor == i ? color : Cv.inkMuted,
                            fontWeight: valor == i ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
