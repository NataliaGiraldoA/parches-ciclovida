import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Piezas del lenguaje visual "carril": la CicloVida como una vía. La cinta de cuatro colores se
/// curva como un carril, las líneas punteadas son las del asfalto y el parche es un boleto
/// perforado. Todo sobre fondos claros, con los colores de la marca (theme.dart).

// ---------------------------------------------------------------------------------------------
// Diseño adaptable
// ---------------------------------------------------------------------------------------------

/// Márgenes laterales que centran el contenido en pantallas anchas (16 px en el celular, 24 en
/// tablet) sin encerrar el scroll: la lista sigue respondiendo en todo el ancho de la ventana.
EdgeInsets rellenoAncho(
  BuildContext context, {
  double maximo = Cv.anchoLectura,
  double arriba = 0,
  double abajo = 0,
}) {
  final ancho = MediaQuery.sizeOf(context).width;
  final minimo = ancho < 600 ? 16.0 : 24.0;
  final lateral = math.max(minimo, (ancho - maximo) / 2);
  return EdgeInsets.fromLTRB(lateral, arriba, lateral, abajo);
}

/// Centra [child] con un ancho máximo, para lo que no es una lista: barras inferiores con
/// botones, formularios fijos, tarjetas flotantes sobre el mapa. Solo ocupa el alto de [child].
class MarcoAncho extends StatelessWidget {
  const MarcoAncho({super.key, required this.child, this.maximo = Cv.anchoLectura});

  final Widget child;
  final double maximo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maximo), child: child),
    );
  }
}

/// Barra fija abajo, blanca y con sombra hacia arriba, con su contenido centrado y con ancho
/// máximo: para el botón principal de un formulario o el redactor de un chat.
class BarraInferior extends StatelessWidget {
  const BarraInferior({
    super.key,
    required this.child,
    this.relleno = const EdgeInsets.fromLTRB(20, 12, 20, 16),
    this.maximo = Cv.anchoLectura,
  });

  final Widget child;
  final EdgeInsetsGeometry relleno;
  final double maximo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Cv.surfaceRaised, boxShadow: Cv.sombraArriba),
      child: SafeArea(
        top: false,
        child: MarcoAncho(maximo: maximo, child: Padding(padding: relleno, child: child)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Piezas pequeñas
// ---------------------------------------------------------------------------------------------

/// Rótulo pequeño en mayúsculas con un trazo de color, encima de títulos y secciones.
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key, this.color = Cv.tealInk});

  final String texto;

  /// Color del trazo (decorativo); el texto va siempre en gris tinta.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            texto.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Cv.inkMuted),
          ),
        ),
      ],
    );
  }
}

/// Pastilla con texto (y un ícono opcional): "Para ti", "Estás aquí", "✨ IA".
/// [color] sobre [fondo] debe cumplir AA: un tono Ink sobre su Soft, o blanco sobre un Ink.
class Sello extends StatelessWidget {
  const Sello(this.texto, {super.key, this.fondo = Cv.tealSoft, this.color = Cv.tealInk, this.icono});

  final String texto;
  final Color fondo;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícono dentro de un círculo de color suave: la forma clara de destacar un ícono.
class IconoBurbuja extends StatelessWidget {
  const IconoBurbuja(this.icono, {super.key, this.color = Cv.tealInk, this.fondo = Cv.tealSoft, this.tamano = 44});

  final IconData icono;
  final Color color;
  final Color fondo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
      child: Icon(icono, color: color, size: tamano * 0.5),
    );
  }
}

/// Bloque de color suave (brisa o Soft de la marca), sin sombra: para agrupar y dar ritmo.
class BloqueColor extends StatelessWidget {
  const BloqueColor({
    super.key,
    required this.child,
    this.color = Cv.brisaTeal,
    this.borde,
    this.relleno = const EdgeInsets.all(18),
    this.radio = Cv.radioLg,
  });

  final Widget child;
  final Color color;

  /// Borde opcional (un tono marca o Ink) para resaltar.
  final Color? borde;
  final EdgeInsetsGeometry relleno;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: relleno,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radio),
        border: borde == null ? null : Border.all(color: borde!, width: 1.5),
      ),
      child: child,
    );
  }
}

/// Estado vacío o de error con personalidad: un emoji grande en un círculo suave, un título y,
/// si hace falta, una acción. Nunca una pantalla en blanco.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.emoji,
    required this.titulo,
    this.texto,
    this.accion,
    this.fondo = Cv.brisaTeal,
  });

  final String emoji;
  final String titulo;
  final String? texto;
  final Widget? accion;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ExcludeSemantics(
              child: Container(
                width: 104,
                height: 104,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
                child: Text(emoji, style: const TextStyle(fontSize: 48, height: 1)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(titulo, textAlign: TextAlign.center, style: t.headlineSmall),
          if (texto != null) ...[
            const SizedBox(height: 6),
            Text(texto!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
          ],
          if (accion != null) ...[const SizedBox(height: 18), accion!],
        ],
      ),
    );
  }
}

/// Rebote leve al tocar: [child] se encoge un poco mientras el dedo está encima y vuelve con
/// un rebote. No toma el gesto (el InkWell o botón de adentro sigue funcionando).
class Rebote extends StatefulWidget {
  const Rebote({super.key, required this.child, this.escala = 0.97});

  final Widget child;
  final double escala;

  @override
  State<Rebote> createState() => _ReboteState();
}

class _ReboteState extends State<Rebote> {
  bool _abajo = false;

  void _poner(bool abajo) {
    if (_abajo != abajo) setState(() => _abajo = abajo);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _poner(true),
      onPointerUp: (_) => _poner(false),
      onPointerCancel: (_) => _poner(false),
      child: AnimatedScale(
        scale: _abajo ? widget.escala : 1,
        duration: Duration(milliseconds: _abajo ? 90 : 320),
        curve: _abajo ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Carril: cinta, líneas punteadas y boletos
// ---------------------------------------------------------------------------------------------

/// Dibuja [path] punteado, como la línea de un carril.
void dibujarPunteada(Canvas canvas, Path path, Paint paint, {double trazo = 10, double espacio = 8}) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + trazo, m.length)), paint);
      d += trazo + espacio;
    }
  }
}

/// Fondo claro con la cinta de cuatro colores entrando por la esquina derecha y curvándose como
/// una vía, más una línea de carril punteada. Para encabezados y tarjetas protagonistas. El texto
/// encima va en gris tinta; deja libre la franja derecha (unos 140 px), por donde pasa la cinta.
class FondoCarril extends StatelessWidget {
  const FondoCarril({
    super.key,
    required this.child,
    this.borde = const BorderRadius.all(Radius.circular(Cv.radioLg)),
    this.colores = const [Cv.surfaceRaised, Cv.brisaCoral],
    this.intensidad = 1,
    this.sombra = true,
  });

  final Widget child;
  final BorderRadius borde;

  /// Degradado del fondo (de arriba a la izquierda hacia abajo a la derecha). Siempre tonos claros.
  final List<Color> colores;

  /// 0 a 1: qué tan presentes se ven la cinta y el carril.
  final double intensidad;

  /// Sombra suave alrededor (quitarla cuando va dentro de otra tarjeta).
  final bool sombra;

  @override
  Widget build(BuildContext context) {
    final fondo = ClipRRect(
      borderRadius: borde,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colores),
        ),
        child: CustomPaint(painter: _CarrilPainter(intensidad), child: child),
      ),
    );
    if (!sombra) return fondo;
    return DecoratedBox(decoration: BoxDecoration(borderRadius: borde, boxShadow: Cv.sombra), child: fondo);
  }
}

class _CarrilPainter extends CustomPainter {
  const _CarrilPainter(this.intensidad);

  final double intensidad;

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final ancho = (s.shortestSide * 0.05).clamp(7.0, 11.0);
    final banda = math.min(s.width * 0.3, 140.0);
    final x0 = s.width - banda;
    // La cinta: cuatro franjas que entran por arriba a la derecha y se curvan hacia la orilla.
    for (var i = 0; i < 4; i++) {
      final d = i * ancho * 1.25;
      final franja = Path()
        ..moveTo(x0 + banda * 0.15 + d, -ancho)
        ..cubicTo(
          x0 + banda * 0.55 + d, s.height * 0.28,
          x0 + banda * 0.35 + d, s.height * 0.62,
          s.width + ancho * 3, s.height * 0.8 + d,
        );
      canvas.drawPath(
        franja,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ancho
          ..strokeCap = StrokeCap.round
          ..color = Cv.cinta[i].withValues(alpha: 0.85 * intensidad),
      );
    }
    // La línea de carril punteada que cruza el fondo por abajo.
    final carril = Path()
      ..moveTo(-12, s.height * 0.94)
      ..quadraticBezierTo(s.width * 0.3, s.height * 0.74, s.width * 0.6, s.height + 12);
    dibujarPunteada(
      canvas,
      carril,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Cv.lineStrong.withValues(alpha: 0.3 * intensidad),
    );
  }

  @override
  bool shouldRepaint(_CarrilPainter old) => old.intensidad != intensidad;
}

/// Línea punteada horizontal (o vertical), como la del asfalto o la de un boleto.
class LineaPunteada extends StatelessWidget {
  const LineaPunteada({super.key, this.color = Cv.lineStrong, this.grosor = 1.5, this.vertical = false});

  final Color color;
  final double grosor;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: vertical ? grosor : double.infinity,
      height: vertical ? double.infinity : grosor,
      child: CustomPaint(painter: _PunteadaPainter(color, grosor, vertical)),
    );
  }
}

class _PunteadaPainter extends CustomPainter {
  const _PunteadaPainter(this.color, this.grosor, this.vertical);

  final Color color;
  final double grosor;
  final bool vertical;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round;
    final largo = vertical ? s.height : s.width;
    var d = 0.0;
    while (d < largo) {
      final fin = math.min(d + 6, largo);
      if (vertical) {
        canvas.drawLine(Offset(s.width / 2, d), Offset(s.width / 2, fin), paint);
      } else {
        canvas.drawLine(Offset(d, s.height / 2), Offset(fin, s.height / 2), paint);
      }
      d += 11;
    }
  }

  @override
  bool shouldRepaint(_PunteadaPainter old) => old.color != color || old.grosor != grosor || old.vertical != vertical;
}

/// El corte de un boleto: dos muescas del color del fondo de la página y una línea punteada.
class Perforacion extends StatelessWidget {
  const Perforacion({super.key, this.fondo = Cv.surface, this.color = Cv.surfaceRaised});

  /// Color de la página detrás de la tarjeta: las muescas lo "dejan ver".
  final Color fondo;

  /// Color de la tarjeta en ese punto.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      height: 24,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 24,
            decoration: BoxDecoration(color: fondo, borderRadius: const BorderRadius.horizontal(right: Radius.circular(12))),
          ),
          const SizedBox(width: 8),
          const Expanded(child: LineaPunteada()),
          const SizedBox(width: 8),
          Container(
            width: 12,
            height: 24,
            decoration: BoxDecoration(color: fondo, borderRadius: const BorderRadius.horizontal(left: Radius.circular(12))),
          ),
        ],
      ),
    );
  }
}

/// Caras del grupo apiladas: la inicial de cada quien en un círculo con borde blanco.
/// Solo para el grupo ya armado: antes del sábado nadie ve quién va.
class AvatarPila extends StatelessWidget {
  const AvatarPila({super.key, required this.nombres, this.colores = const [], this.radio = 16, this.maximo = 5});

  final List<String> nombres;

  /// Color de cada círculo (un tono Ink; si falta, rota por los de la marca).
  final List<Color> colores;
  final double radio;
  final int maximo;

  static const _rotacion = [Cv.tealInk, Cv.coralInk, Cv.verdeInk, Cv.rojoInk];

  @override
  Widget build(BuildContext context) {
    final visibles = nombres.take(maximo).toList();
    final resto = nombres.length - visibles.length;
    final paso = radio * 1.35;
    final total = visibles.length + (resto > 0 ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: SizedBox(
        width: radio * 2 + (total - 1) * paso,
        height: radio * 2,
        child: Stack(
          children: [
            for (var i = 0; i < visibles.length; i++)
              Positioned(
                left: i * paso,
                child: _circulo(
                  visibles[i].isEmpty ? '?' : visibles[i].substring(0, 1).toUpperCase(),
                  i < colores.length ? colores[i] : _rotacion[i % _rotacion.length],
                ),
              ),
            if (resto > 0) Positioned(left: visibles.length * paso, child: _circulo('+$resto', Cv.inkMuted)),
          ],
        ),
      ),
    );
  }

  Widget _circulo(String texto, Color color) {
    return Container(
      width: radio * 2,
      height: radio * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: Text(
        texto,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radio * 0.78, height: 1),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Movimiento y carga
// ---------------------------------------------------------------------------------------------

/// Entrada suave (sube y aparece), escalonada por [orden]. Respeta "reducir movimiento".
class Aparecer extends StatefulWidget {
  const Aparecer({super.key, required this.child, this.orden = 0});

  final Widget child;
  final int orden;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer> with SingleTickerProviderStateMixin {
  // El escalonado va dentro de la animación (un Interval) y no en un Future.delayed: un timer
  // pendiente al terminar hace fallar flutter test.
  late final int _espera = 70 * widget.orden.clamp(0, 8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 420 + _espera));
  late final Animation<double> _curva = CurvedAnimation(
    parent: _c,
    curve: Interval(_espera / (420 + _espera), 1, curve: Curves.easeOutCubic),
  );
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curva,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(_curva),
        child: widget.child,
      ),
    );
  }
}

/// Bloque que late mientras carga: la forma de lo que viene, en vez de un circulito girando.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, required this.alto, this.radio = Cv.radioLg, this.ancho});

  final double alto;
  final double radio;

  /// Ancho fijo (por defecto, todo el disponible).
  final double? ancho;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0.7;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.5, end: 1).animate(_c),
        child: Container(
          width: widget.ancho,
          height: widget.alto,
          decoration: BoxDecoration(color: Cv.line, borderRadius: BorderRadius.circular(widget.radio)),
        ),
      ),
    );
  }
}

/// Ondas que salen de un punto, como un radar: "estamos buscando".
class Radar extends StatefulWidget {
  const Radar({super.key, required this.icono, this.color = Cv.tealInk, this.tamano = 64});

  final IconData icono;
  final Color color;
  final double tamano;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0.4;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.tamano,
        height: widget.tamano,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(painter: _RadarPainter(_c.value, widget.color)),
              ),
            ),
            Container(
              width: widget.tamano * 0.56,
              height: widget.tamano * 0.56,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              child: Icon(widget.icono, color: Colors.white, size: widget.tamano * 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final centro = s.center(Offset.zero);
    final minimo = s.shortestSide * 0.28;
    final maximo = s.shortestSide * 0.5;
    for (var k = 0; k < 3; k++) {
      final p = (t + k / 3) % 1;
      canvas.drawCircle(
        centro,
        minimo + (maximo - minimo) * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------------------------
// Rutas de pasos y cuenta regresiva
// ---------------------------------------------------------------------------------------------

/// Una parada de [RutaPasos].
class PasoRuta {
  const PasoRuta({required this.titulo, required this.color, this.texto, this.icono, this.numero});

  final String titulo;
  final String? texto;

  /// Relleno del nodo: un tono Ink (el número o ícono va en blanco encima).
  final Color color;

  /// En el nodo va el ícono o, si no hay, el número.
  final IconData? icono;
  final String? numero;
}

/// Pasos unidos por una línea punteada, como las paradas de una ruta.
class RutaPasos extends StatelessWidget {
  const RutaPasos({super.key, required this.pasos, this.nodo = 38});

  final List<PasoRuta> pasos;
  final double nodo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pasos.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: nodo,
                  child: Column(
                    children: [
                      _nodo(pasos[i]),
                      if (i < pasos.length - 1)
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
                    padding: EdgeInsets.only(top: (nodo - 24) / 2, bottom: i < pasos.length - 1 ? 18 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pasos[i].titulo, style: t.titleMedium),
                        if (pasos[i].texto != null) ...[
                          const SizedBox(height: 2),
                          Text(pasos[i].texto!, style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _nodo(PasoRuta p) {
    return Container(
      width: nodo,
      height: nodo,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.color, shape: BoxShape.circle, boxShadow: Cv.brillo(p.color)),
      child: p.icono != null
          ? Icon(p.icono, color: Colors.white, size: nodo * 0.5)
          : Text(
              p.numero ?? '',
              style: TextStyle(fontFamily: Cv.display, fontSize: nodo * 0.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
            ),
    );
  }
}

/// Cuenta regresiva al domingo: un anillo con la cinta de colores que se va llenando, con el
/// número en el centro sobre un disco blanco.
class AnilloCuenta extends StatelessWidget {
  const AnilloCuenta({super.key, required this.dias, this.tamano = 84});

  /// Días que faltan; 0 o menos es "hoy".
  final int dias;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final hoy = dias <= 0;
    final progreso = hoy ? 1.0 : (7 - dias.clamp(1, 7)) / 7;
    return Semantics(
      label: hoy ? 'Es hoy' : 'Faltan $dias ${dias == 1 ? 'día' : 'días'}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: tamano,
          height: tamano,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: tamano - 10,
                height: tamano - 10,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: Cv.sombra),
              ),
              SizedBox.expand(child: CustomPaint(painter: _AnilloPainter(progreso))),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hoy ? '¡Hoy!' : '$dias',
                    style: TextStyle(
                      fontFamily: Cv.display,
                      fontWeight: FontWeight.w800,
                      fontSize: hoy ? 20 : 32,
                      height: 1,
                      color: hoy ? Cv.coralInk : Cv.ink,
                    ),
                  ),
                  if (!hoy)
                    Text(
                      dias == 1 ? 'día' : 'días',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Cv.inkMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnilloPainter extends CustomPainter {
  const _AnilloPainter(this.progreso);

  final double progreso;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = (Offset.zero & s).deflate(4);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Cv.line,
    );
    if (progreso <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progreso.clamp(0.02, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [Cv.teal, Cv.verde, Cv.coral, Cv.rojo, Cv.teal],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AnilloPainter old) => old.progreso != progreso;
}

// ---------------------------------------------------------------------------------------------
// Celebración
// ---------------------------------------------------------------------------------------------

/// El momento "¡Match!": una tarjeta que aparece con un estallido y confeti en los cuatro colores.
Future<void> celebrar(
  BuildContext context, {
  required String titulo,
  required String texto,
  required IconData icono,
  Color color = Cv.verdeInk,
  String boton = '¡De una!',
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Cv.ink.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, _, __) => _Celebracion(titulo: titulo, texto: texto, icono: icono, color: color, boton: boton),
    transitionBuilder: (ctx, anim, _, child) {
      final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(curva), child: child),
      );
    },
  );
}

class _Celebracion extends StatefulWidget {
  const _Celebracion({required this.titulo, required this.texto, required this.icono, required this.color, required this.boton});

  final String titulo;
  final String texto;
  final IconData icono;
  final Color color;
  final String boton;

  @override
  State<_Celebracion> createState() => _CelebracionState();
}

class _CelebracionState extends State<_Celebracion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Cv.radioXl), boxShadow: Cv.sombraAlta),
            child: Material(
              color: Cv.surfaceRaised,
              borderRadius: BorderRadius.circular(Cv.radioXl),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 180,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Cv.brisaCoral, Cv.surfaceRaised],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: _c,
                                builder: (_, __) => CustomPaint(painter: _EstallidoPainter(_c.value)),
                              ),
                            ),
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: Cv.brillo(widget.color)),
                              child: Icon(widget.icono, color: Colors.white, size: 44),
                            ),
                          ],
                        ),
                      ),
                      const Cinta(alto: 6),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(widget.titulo, textAlign: TextAlign.center, style: t.displaySmall),
                            const SizedBox(height: 10),
                            Text(widget.texto, textAlign: TextAlign.center, style: t.bodyLarge),
                            const SizedBox(height: 20),
                            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.boton)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // El confeti cae por encima de toda la tarjeta sin tapar los toques.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (_, __) => CustomPaint(painter: _ConfetiPainter(_c.value)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EstallidoPainter extends CustomPainter {
  const _EstallidoPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    final centro = s.center(Offset.zero);
    final e = Curves.easeOutCubic.transform((t * 1.6).clamp(0.0, 1.0));
    final alfa = (1 - e) * 0.8 + 0.2;
    // anillo que se abre
    canvas.drawCircle(
      centro,
      48 + 46 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Cv.coral.withValues(alpha: (1 - e) * 0.6),
    );
    // rayos en los cuatro colores de la cinta
    for (var i = 0; i < 16; i++) {
      final angulo = i * math.pi * 2 / 16 + 0.2;
      final dir = Offset(math.cos(angulo), math.sin(angulo));
      final desde = 54 + 26 * e;
      final hasta = desde + (i.isEven ? 16 : 9) + 8 * e;
      canvas.drawLine(
        centro + dir * desde,
        centro + dir * hasta,
        Paint()
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Cv.cinta[i % 4].withValues(alpha: alfa),
      );
    }
  }

  @override
  bool shouldRepaint(_EstallidoPainter old) => old.t != t;
}

/// Confeti que cae y gira: posiciones fijas por pieza (sin azar), para que se vea igual siempre.
class _ConfetiPainter extends CustomPainter {
  const _ConfetiPainter(this.t);

  final double t;
  static const _piezas = 42;

  @override
  void paint(Canvas canvas, Size s) {
    if (t <= 0 || t >= 1) return;
    for (var i = 0; i < _piezas; i++) {
      // pseudo-azar determinista por pieza
      final a = ((i * 73 + 17) % 101) / 101;
      final b = ((i * 37 + 53) % 97) / 97;
      final retraso = b * 0.25;
      final p = ((t - retraso) / (1 - retraso)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final x = s.width * a + math.sin(p * math.pi * 3 + i) * 14;
      final y = -20 + (s.height + 40) * Curves.easeIn.transform(p);
      final alfa = p > 0.85 ? (1 - p) / 0.15 : 1.0;
      final paint = Paint()..color = Cv.cinta[i % 4].withValues(alpha: alfa);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * math.pi * 4 * (i.isEven ? 1 : -1));
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -6, 6, 12), const Radius.circular(1.5)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfetiPainter old) => old.t != t;
}
