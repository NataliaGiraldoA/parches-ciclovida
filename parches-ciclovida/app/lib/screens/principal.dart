import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/diseno.dart';
import 'foro.dart';
import 'inicio.dart';
import 'mapa.dart';

/// Cascarón con las tres pestañas: Mi parche, Mapa y Foro, con una barra flotante tipo píldora.
class PrincipalScreen extends StatefulWidget {
  const PrincipalScreen({super.key});

  @override
  State<PrincipalScreen> createState() => _PrincipalScreenState();
}

class _PrincipalScreenState extends State<PrincipalScreen> {
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: [
          // cada pestaña se recarga cuando vuelve a quedar activa: lo que cambie por Telegram se ve al volver
          InicioScreen(activo: _pestana == 0),
          MapaScreen(activo: _pestana == 1),
          ForoScreen(activo: _pestana == 2),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: MarcoAncho(
            maximo: 460,
            child: _BarraPildora(actual: _pestana, onCambio: (i) => setState(() => _pestana = i)),
          ),
        ),
      ),
    );
  }
}

class _Destino {
  const _Destino(this.icono, this.iconoActivo, this.texto, this.color, this.fondo);

  final IconData icono;
  final IconData iconoActivo;
  final String texto;

  /// Tono Ink de la sección (ícono y texto de la pestaña activa).
  final Color color;

  /// Tono Soft de la sección (píldora de la pestaña activa).
  final Color fondo;
}

/// Barra flotante blanca: la pestaña activa se vuelve una píldora con el color de su sección.
class _BarraPildora extends StatelessWidget {
  const _BarraPildora({required this.actual, required this.onCambio});

  final int actual;
  final ValueChanged<int> onCambio;

  static const _destinos = [
    _Destino(Icons.groups_outlined, Icons.groups, 'Mi parche', Cv.coralInk, Cv.coralSoft),
    _Destino(Icons.map_outlined, Icons.map, 'Mapa', Cv.tealInk, Cv.tealSoft),
    _Destino(Icons.forum_outlined, Icons.forum, 'Foro', Cv.verdeInk, Cv.verdeSoft),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Cv.surfaceRaised,
        borderRadius: BorderRadius.circular(33),
        border: Border.all(color: Cv.line),
        boxShadow: Cv.sombraAlta,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _destinos.length; i++)
            Expanded(child: _Pestana(destino: _destinos[i], activa: i == actual, onTap: () => onCambio(i))),
        ],
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({required this.destino, required this.activa, required this.onTap});

  final _Destino destino;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activa,
      label: destino.texto,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: ShapeDecoration(
                color: activa ? destino.fondo : Colors.transparent,
                shape: const StadiumBorder(),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(activa ? destino.iconoActivo : destino.icono, size: 24, color: activa ? destino.color : Cv.inkMuted),
                  Flexible(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: activa
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                destino.texto,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: destino.color),
                              ),
                            )
                          : const SizedBox.shrink(),
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
