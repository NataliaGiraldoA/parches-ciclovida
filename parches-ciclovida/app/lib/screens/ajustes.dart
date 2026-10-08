import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../notificaciones.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/demo.dart';
import '../widgets/diseno.dart';
import '../widgets/telegram.dart';
import 'aviso.dart';
import 'como_armamos.dart';
import 'historial.dart';

/// Ajustes del joven y, al final, las herramientas para la demo con jurados.
/// Devuelve 'borrado' si la persona borró sus datos y 'salir' si cerró sesión.
class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key, required this.onPreferencias, this.onQuiz});

  final Future<void> Function() onPreferencias;
  final Future<void> Function()? onQuiz;

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  late final TextEditingController _clave = TextEditingController(text: Sesion.actual.claveAdmin);
  bool _ocupado = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _demo(Future<String> Function(String clave) accion) async {
    setState(() => _ocupado = true);
    try {
      await Sesion.actual.guardarClave(_clave.text);
      _aviso(await accion(_clave.text.trim()));
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Para volver a entrar te enviaremos un código a tu correo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop('salir');
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar tus datos?'),
        content: const Text('Se borra tu perfil, tus parches y tus encuestas. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Cv.rojoInk),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Sesion.actual.api.borrarMisDatos();
      if (!mounted) return;
      Navigator.of(context).pop('borrado');
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: rellenoAncho(context, arriba: 4, abajo: 32),
        children: [
          const _Seccion('Tu parche y tus avisos', color: Cv.coral),
          _Grupo(
            children: [
              ListTile(
                leading: const IconoBurbuja(Icons.tune, color: Cv.tealInk, fondo: Cv.tealSoft, tamano: 40),
                title: const Text('Cambiar mis preferencias'),
                subtitle: const Text('Actividad, ritmo y estación cercana'),
                onTap: widget.onPreferencias,
              ),
              if (widget.onQuiz != null)
                ListTile(
                  leading: const IconoBurbuja(Icons.local_drink_outlined, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 40),
                  title: const Text('Tu estilo de parche'),
                  subtitle: const Text('El quiz de 5 preguntas. Puedes cambiarlo cuando quieras'),
                  onTap: widget.onQuiz,
                ),
              ListTile(
                leading: const IconoBurbuja(Icons.history, color: Cv.verdeInk, fondo: Cv.verdeSoft, tamano: 40),
                title: const Text('Mis domingos'),
                subtitle: const Text('A qué parches has ido y con quién'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistorialScreen())),
              ),
              ListTile(
                leading: const IconoBurbuja(Icons.notifications_active_outlined, color: Cv.rojoInk, fondo: Cv.rojoSoft, tamano: 40),
                title: const Text('Volver a activar los avisos'),
                subtitle: const Text('Sábado 7:00 p. m. y domingo 1:30 p. m.'),
                onTap: () async {
                  final ok = await Notificaciones.pedirPermiso();
                  await Notificaciones.programarSemana();
                  _aviso(ok || !Notificaciones.soportadas
                      ? 'Avisos programados.'
                      : 'Activa las notificaciones de Parches CicloVida en los ajustes del teléfono.');
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          const TarjetaTelegram(),
          const SizedBox(height: 8),
          const _Seccion('Cómo funciona', color: Cv.teal),
          _Grupo(
            children: [
              ListTile(
                leading: const IconoBurbuja(Icons.account_tree_outlined, color: Cv.tealInk, fondo: Cv.tealSoft, tamano: 40),
                title: const Text('Cómo armamos los grupos'),
                subtitle: const Text('K-means y sus tres variables'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ComoArmamosScreen())),
              ),
              ListTile(
                leading: const IconoBurbuja(Icons.privacy_tip_outlined, color: Cv.verdeInk, fondo: Cv.verdeSoft, tamano: 40),
                title: const Text('Aviso de privacidad'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AvisoPrivacidadScreen())),
              ),
            ],
          ),
          const _Seccion('Herramientas de demo', color: Cv.verde),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Para mostrar el ciclo completo sin esperar al fin de semana.', style: t.bodySmall),
          ),
          _Grupo(
            color: Cv.brisaVerde,
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Ver el aviso del sábado'),
                onTap: () => Notificaciones.probar(context, avisoSabado),
              ),
              ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: const Text('Ver el aviso de la encuesta'),
                onTap: () => Notificaciones.probar(context, avisoDomingo),
              ),
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Ver el tablero de la Secretaría'),
                subtitle: const Text('Lo que haces en la app aparece ahí, sin tu nombre'),
                onTap: () => launchUrl(
                  Uri.parse('${Sesion.actual.apiUrl.replaceAll(RegExp(r'/+$'), '')}/tablero/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Dirección del servidor'),
                subtitle: Text(Sesion.actual.apiUrl),
                onTap: () async {
                  await dialogoServidor(context, actual: Sesion.actual.apiUrl, guardar: Sesion.actual.cambiarUrl);
                  if (mounted) setState(() {});
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _clave,
                      decoration: const InputDecoration(labelText: 'Clave de administración'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => _demo(demoArmarGrupos),
                      child: const Text('1. Armar los grupos del sábado'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => _demo(demoTerminarDomingo),
                      child: const Text('2. Terminar la jornada y abrir encuesta'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Seccion('Tus datos', color: Cv.rojo),
          _Grupo(
            children: [
              ListTile(
                leading: const IconoBurbuja(Icons.logout, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 40),
                title: const Text('Cerrar sesión'),
                subtitle: const Text('Tus datos se quedan guardados. Vuelves a entrar con tu correo'),
                onTap: _cerrarSesion,
              ),
              ListTile(
                leading: const IconoBurbuja(Icons.delete_outline, color: Cv.rojoInk, fondo: Cv.rojoSoft, tamano: 40),
                title: const Text('Borrar mis datos', style: TextStyle(color: Cv.rojoInk)),
                subtitle: const Text('Ley 1581 de 2012: puedes pedirlo cuando quieras'),
                onTap: _borrar,
              ),
            ],
          ),
          const SizedBox(height: 32),
          const PieInstitucional(),
        ],
      ),
    );
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({required this.children, this.color = Cv.surfaceRaised});

  final List<Widget> children;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      ),
    );
  }
}

/// Rótulo de una sección de Ajustes.
class _Seccion extends StatelessWidget {
  const _Seccion(this.texto, {required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Rotulo(texto, color: color),
    );
  }
}
