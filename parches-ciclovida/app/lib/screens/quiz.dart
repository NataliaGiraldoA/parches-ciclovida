import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/diseno.dart';
import '../widgets/comunes.dart';
import 'principal.dart';

/// Quiz "Tu estilo de parche": 5 preguntas rápidas y en tono de domingo.
/// Es opcional, no muestra resultados ni etiquetas, y solo sirve para que el
/// sistema desempate entre grupos con gente que disfruta el plan como tú.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.quiz, this.alInicio = false});

  final QuizInfo quiz;

  /// Justo después del registro: se puede saltar y, al terminar o saltar, sigue a la app.
  /// Si lo salta, la invitación queda en "Mi parche" y en Ajustes para hacerlo después.
  final bool alInicio;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Map<int, String> _respuestas = {};
  bool _enviando = false;

  bool get _completo => widget.quiz.preguntas.every((p) => _respuestas.containsKey(p.id));

  void _seguir(String? mensaje) {
    if (!widget.alInicio) {
      Navigator.of(context).pop(mensaje);
      return;
    }
    if (mensaje != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PrincipalScreen()),
      (route) => false,
    );
  }

  void _saltar() => _seguir(null);

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      final mensaje = await Sesion.actual.api.responderQuiz(_respuestas);
      if (!mounted) return;
      _seguir(mensaje);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final quiz = widget.quiz;
    final respondidas = _respuestas.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(quiz.titulo),
        automaticallyImplyLeading: !widget.alInicio,
        actions: [
          if (widget.alInicio)
            TextButton(
              onPressed: _enviando ? null : _saltar,
              style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
              child: const Text('Ahora no'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: '$respondidas de ${quiz.preguntas.length} respondidas',
              child: Cinta(alto: 6, llenos: (respondidas * 4 / quiz.preguntas.length).ceil()),
            ),
            Expanded(
              child: ListView(
                padding: rellenoAncho(context, arriba: 16, abajo: 24),
                children: [
                  if (widget.alInicio) ...[
                    BloqueColor(
                      color: Cv.brisaCoral,
                      borde: Cv.coralSoft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('¡Tu perfil está listo! 🎉', style: t.headlineMedium),
                          const SizedBox(height: 6),
                          Text('Antes de buscarte parche, cuéntanos cómo te gusta el domingo.', style: t.bodyLarge),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(quiz.detalle, style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < quiz.preguntas.length; i++) ...[
                    const SizedBox(height: 14),
                    _Pregunta(
                      numero: i + 1,
                      pregunta: quiz.preguntas[i],
                      elegida: _respuestas[quiz.preguntas[i].id],
                      onElegir: (opcion) => setState(() => _respuestas[quiz.preguntas[i].id] = opcion),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Tus respuestas no se muestran a nadie: ni a tu grupo, ni a la Alcaldía. '
                    'Solo las usa el sistema para armarte un parche más afín.',
                    textAlign: TextAlign.center,
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            BarraInferior(
              relleno: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: _completo && !_enviando ? _enviar : null,
                    child: Text(_completo
                        ? '¡Listo, ese soy yo!'
                        : 'Te ${quiz.preguntas.length - respondidas == 1 ? 'falta 1' : 'faltan ${quiz.preguntas.length - respondidas}'}'),
                  ),
                  if (widget.alInicio)
                    TextButton(
                      onPressed: _enviando ? null : _saltar,
                      style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                      child: const Text('No quiero hacerlo ahora'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pregunta extends StatelessWidget {
  const _Pregunta({required this.numero, required this.pregunta, required this.elegida, required this.onElegir});

  /// Cada pregunta toma un color de la cinta, en su tono Ink (el número blanco encima cumple AA).
  static const _colores = [Cv.rojoInk, Cv.coralInk, Cv.verdeInk, Cv.tealInk];
  static const _brisas = [Cv.brisaRojo, Cv.brisaCoral, Cv.brisaVerde, Cv.brisaTeal];

  final int numero;
  final QuizPregunta pregunta;
  final String? elegida;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) {
    final i = (numero - 1) % _colores.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _colores[i], shape: BoxShape.circle, boxShadow: Cv.brillo(_colores[i])),
                  child: Text(
                    '$numero',
                    style: const TextStyle(fontFamily: Cv.display, fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(pregunta.texto, style: Theme.of(context).textTheme.headlineSmall)),
              ],
            ),
            const SizedBox(height: 12),
            for (final o in pregunta.opciones)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Seleccionable(
                  titulo: o.texto,
                  seleccionado: elegida == o.id,
                  onTap: () => onElegir(o.id),
                  colorSeleccion: _colores[i],
                  fondoSeleccion: _brisas[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
