import 'package:flutter/material.dart';

import '../config.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';
import 'ingreso.dart';
import 'registro.dart';

class BienvenidaScreen extends StatelessWidget {
  const BienvenidaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Cv.surface,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // El cartel: fondo claro con la cinta curvándose como el carril y el titular en stickers.
          FondoCarril(
            borde: const BorderRadius.vertical(bottom: Radius.circular(36)),
            child: SafeArea(
              bottom: false,
              child: MarcoAncho(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: Cv.sombra,
                            ),
                            child: Image.asset(
                              'assets/img/parche-logo.png',
                              height: 44,
                              semanticLabel: 'Parche CicloVida',
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => dialogoServidor(
                              context,
                              actual: Sesion.actual.apiUrl,
                              guardar: Sesion.actual.cambiarUrl,
                            ),
                            style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                            icon: const Icon(Icons.dns_outlined, size: 18),
                            label: const Text('Servidor'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      Aparecer(
                        child: Semantics(
                          header: true,
                          label: 'Este domingo sal en parche a la CicloVida',
                          child: const ExcludeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Franja(texto: 'Este domingo', color: Cv.rojoInk, giro: -0.035),
                                _Franja(texto: 'sal en parche', color: Cv.verdeInk, giro: 0.02, sangria: 22),
                                _Franja(texto: 'a la CicloVida', color: Cv.tealInk, giro: -0.02, sangria: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Aparecer(
                        orden: 1,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'Cada semana abrimos parches en las 11 estaciones: a pie o sobre ruedas, a las 8:00, 9:30 '
                            'u 11:00. Solo para estudiantes de universidades de Cali, verificados con su correo '
                            'institucional.',
                            style: t.bodyLarge,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Aparecer(
                        orden: 2,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Cifra(numero: '11', texto: 'estaciones', color: Cv.tealInk),
                            _Cifra(numero: '3', texto: 'horarios', color: Cv.coralInk),
                            _Cifra(numero: '4', texto: 'actividades', color: Cv.verdeInk),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: rellenoAncho(context, arriba: 28, abajo: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Aparecer(
                  orden: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(alignment: Alignment.centerLeft, child: Rotulo('Así funciona')),
                      SizedBox(height: 16),
                      RutaPasos(
                        pasos: [
                          PasoRuta(
                            numero: '1',
                            color: Cv.rojoInk,
                            titulo: 'Verifica tu correo',
                            texto: 'El de tu universidad, y crea tu perfil.',
                          ),
                          PasoRuta(
                            numero: '2',
                            color: Cv.coralInk,
                            titulo: 'Elige tu parche',
                            texto: 'Hora, actividad y estación. O deja que el match lo busque por ti.',
                          ),
                          PasoRuta(
                            numero: '3',
                            color: Cv.verdeInk,
                            titulo: 'El sábado se arma tu grupo',
                            texto: 'De 3 a 6 personas, y confirmas si vas.',
                          ),
                          PasoRuta(
                            numero: '4',
                            color: Cv.tealInk,
                            titulo: 'El domingo, a rodar',
                            texto: 'Se encuentran en la estación y arrancan.',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Aparecer(
                  orden: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RegistroScreen())),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Crear mi perfil'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const IngresoScreen())),
                        child: const Text('Ya tengo cuenta'),
                      ),
                      if (kModoDemo) ...[
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const IngresoScreen(usarDemo: true))),
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          label: const Text('Puedes iniciar sesión con la cuenta demo'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.shield_outlined, size: 16, color: Cv.inkMuted),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tu grupo solo ve tu primer nombre y tu universidad. Se encuentran siempre en una estación pública.',
                              style: t.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Cinta(alto: 8, radio: 4),
                const SizedBox(height: 16),
                const PieInstitucional(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una línea del titular sobre una franja de color, levemente girada como un sticker.
class _Franja extends StatelessWidget {
  const _Franja({required this.texto, required this.color, required this.giro, this.sangria = 0});

  final String texto;
  final Color color;
  final double giro;
  final double sangria;

  @override
  Widget build(BuildContext context) {
    // En un celular de 375 px el titular queda en 41 px; en pantallas anchas, hasta 56.
    final tamano = (MediaQuery.sizeOf(context).width * 0.11).clamp(34.0, 56.0);
    return Padding(
      padding: EdgeInsets.only(left: sangria, bottom: 8),
      child: Transform.rotate(
        angle: giro,
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 16, 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            boxShadow: Cv.brillo(color),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontFamily: Cv.display,
              fontWeight: FontWeight.w800,
              fontSize: tamano,
              letterSpacing: -1,
              height: 1,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una cifra del programa en una pastilla blanca sobre el cartel.
class _Cifra extends StatelessWidget {
  const _Cifra({required this.numero, required this.texto, required this.color});

  final String numero;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Cv.line),
        borderRadius: BorderRadius.circular(Cv.radioMd),
        boxShadow: Cv.sombra,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            numero,
            style: TextStyle(fontFamily: Cv.display, fontSize: 28, fontWeight: FontWeight.w800, color: color, height: 1),
          ),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Cv.inkMuted)),
        ],
      ),
    );
  }
}
