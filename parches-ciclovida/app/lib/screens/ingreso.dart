import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../notificaciones.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/diseno.dart';
import 'principal.dart';

/// Volver a entrar: el mismo correo institucional del registro y un código nuevo.
/// La cuenta es la misma de siempre; no se crea nada.
class IngresoScreen extends StatefulWidget {
  const IngresoScreen({super.key, this.usarDemo = false});

  /// Llega desde "Puedes iniciar sesión con la cuenta demo": entra con ella de una vez.
  final bool usarDemo;

  @override
  State<IngresoScreen> createState() => _IngresoScreenState();
}

class _IngresoScreenState extends State<IngresoScreen> {
  final _correo = TextEditingController();
  final _codigo = TextEditingController();

  String? _correoEnviado;
  String? _universidad;
  String? _codigoDemo;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    if (widget.usarDemo) {
      _correo.text = kCorreoDemo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pedirCodigo();
      });
    }
  }

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _pedirCodigo() async {
    FocusScope.of(context).unfocus();
    setState(() => _ocupado = true);
    try {
      final r = await Sesion.actual.api.pedirCodigo(_correo.text.trim(), para: 'ingreso');
      if (!mounted) return;
      setState(() {
        _correoEnviado = _correo.text.trim();
        _universidad = r.universidad;
        _codigoDemo = r.codigoDemo;
        _codigo.clear();
        // la cuenta demo es pública: su código se llena solo y queda tocar "Entrar"
        if (_esDemo(_correoEnviado) && r.codigoDemo != null) _codigo.text = r.codigoDemo!;
      });
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    setState(() => _ocupado = true);
    try {
      final r = await Sesion.actual.api.ingresar(correo: _correoEnviado!, codigo: _codigo.text.trim());
      await Sesion.actual.guardarToken(r.token);
      await Notificaciones.pedirPermiso();
      await Notificaciones.programarSemana();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const PrincipalScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      _aviso(e.mensaje);
      if (mounted) setState(() => _ocupado = false);
    }
  }

  bool _esDemo(String? correo) => correo?.trim().toLowerCase() == kCorreoDemo;

  Future<void> _usarDemo() async {
    _correo.text = kCorreoDemo;
    await _pedirCodigo();
  }

  bool get _puedeEntrar =>
      _correoEnviado != null && _correoEnviado == _correo.text.trim() && _codigo.text.trim().length == 6;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final enviado = _correoEnviado != null && _correoEnviado == _correo.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Ya tengo cuenta')),
      body: ListView(
        padding: rellenoAncho(context, arriba: 8, abajo: 32),
        children: [
          Row(
            children: [
              const IconoBurbuja(Icons.mail_outline, color: Cv.tealInk, fondo: Cv.tealSoft, tamano: 52),
              const SizedBox(width: 14),
              Expanded(child: Text('Entra con tu correo', style: t.headlineMedium)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Escribe el correo institucional con el que te registraste y te enviamos un código nuevo. '
            'Tu perfil y tus parches siguen intactos.',
            style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Correo institucional',
              hintText: 'tu@usbcali.edu.co',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _ocupado || _correo.text.trim().isEmpty ? null : _pedirCodigo,
            child: Text(enviado ? 'Enviarme otro código' : 'Enviarme el código'),
          ),
          if (enviado) ...[
            const SizedBox(height: 18),
            if (_universidad != null)
              BloqueColor(
                color: Cv.verdeSoft,
                relleno: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                radio: Cv.radioMd,
                child: Row(
                  children: [
                    const Icon(Icons.verified, size: 20, color: Cv.verdeInk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _universidad!,
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: Cv.verdeInk),
                      ),
                    ),
                  ],
                ),
              ),
            if (_codigoDemo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BloqueColor(
                  color: Cv.coralSoft,
                  relleno: const EdgeInsets.all(14),
                  radio: Cv.radioMd,
                  child: Text('Modo demo, sin servidor de correo: tu código es $_codigoDemo',
                      style: t.bodyMedium?.copyWith(color: Cv.coralInk, fontWeight: FontWeight.w700)),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _codigo,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontFamily: Cv.display, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: const InputDecoration(labelText: 'Código de 6 dígitos', counterText: ''),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ocupado || !_puedeEntrar ? null : _entrar,
              child: const Text('Entrar'),
            ),
          ],
          if (kModoDemo && !(enviado && _esDemo(_correoEnviado))) ...[
            const SizedBox(height: 28),
            _TarjetaDemo(onUsar: _ocupado ? null : _usarDemo),
          ],
        ],
      ),
    );
  }
}

/// Los datos de la cuenta demo y el atajo para entrar con ella.
class _TarjetaDemo extends StatelessWidget {
  const _TarjetaDemo({required this.onUsar});

  final VoidCallback? onUsar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BloqueColor(
      color: Cv.brisaCoral,
      borde: Cv.coralSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconoBurbuja(Icons.visibility_outlined, color: Cv.coralInk, fondo: Colors.white, tamano: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Rotulo('Cuenta demo', color: Cv.coral),
                    const SizedBox(height: 4),
                    Text('¿Solo quieres mirar?', style: t.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Entra sin registrarte: ya tiene parche este domingo, domingos pasados y racha.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _DatoDemo(icono: Icons.alternate_email, etiqueta: 'Correo', valor: kCorreoDemo),
          const SizedBox(height: 6),
          const _DatoDemo(icono: Icons.pin_outlined, etiqueta: 'Código', valor: 'te sale en pantalla al pedirlo'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onUsar,
            style: botonDeColor(Cv.coralInk, minimo: const Size.fromHeight(48)),
            icon: const Icon(Icons.login, size: 20),
            label: const Text('Usar la cuenta demo'),
          ),
        ],
      ),
    );
  }
}

class _DatoDemo extends StatelessWidget {
  const _DatoDemo({required this.icono, required this.etiqueta, required this.valor});

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 18, color: Cv.coralInk),
        const SizedBox(width: 8),
        Text('$etiqueta:', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Cv.inkMuted)),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Cv.ink)),
        ),
      ],
    );
  }
}
