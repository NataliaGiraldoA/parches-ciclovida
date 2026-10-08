import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../formato.dart';
import '../models.dart';
import '../notificaciones.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';
import '../widgets/selectores.dart';
import 'aviso.dart';
import 'ingreso.dart';
import 'principal.dart';
import 'quiz.dart';

/// Registro en cuatro pasos: correo universitario, quién eres, cómo te mueves, autorización.
/// La estación y la actividad solo sirven para recomendar parches: el joven elige después.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  static const _titulos = ['Verifica que estudias en Cali', '¿Quién eres?', '¿Cómo te mueves?', 'Antes de terminar'];

  /// Un ícono y un color de la cinta por paso: el registro avanza por el carril.
  static const _iconos = [Icons.school_outlined, Icons.waving_hand_outlined, Icons.directions_bike, Icons.verified_user_outlined];
  static const _colores = [Cv.rojoInk, Cv.coralInk, Cv.verdeInk, Cv.tealInk];
  static const _suaves = [Cv.rojoSoft, Cv.coralSoft, Cv.verdeSoft, Cv.tealSoft];

  Catalogo? _cat;
  String? _error;
  int _paso = 0;
  bool _enviando = false;

  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _acudiente = TextEditingController();
  String? _correoEnviado;
  String? _universidad;
  String? _codigoDemo;
  bool _pidiendoCodigo = false;

  String? _rango;
  int? _comuna;
  String? _tramo;
  String? _actividad;
  String? _ritmo;
  String? _primeraVez; // 'si' | 'no' | null (opcional)
  bool _aceptaDatos = false;
  bool _declaraMayor = false;
  bool _permisoAcudiente = false;

  bool get _esMenor => _rango == '14-17';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    _nombre.dispose();
    _acudiente.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (_error != null) setState(() => _error = null);
    try {
      final cat = await Sesion.actual.api.catalogo();
      if (!mounted) return;
      setState(() => _cat = cat);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  bool get _pasoValido {
    switch (_paso) {
      case 0:
        return _correoEnviado != null && _correoEnviado == _correo.text.trim() && _codigo.text.trim().length == 6;
      case 1:
        return _nombre.text.trim().length >= 2 && _rango != null && _comuna != null;
      case 2:
        return _actividad != null && _ritmo != null;
      default:
        // la casilla de mayoría de edad es obligatoria para 18+; los menores llevan la de su acudiente
        return _aceptaDatos &&
            (_esMenor ? (_permisoAcudiente && _acudiente.text.trim().length >= 3) : _declaraMayor);
    }
  }

  void _atras() {
    if (_paso == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _paso--);
    }
  }

  Future<void> _pedirCodigo() async {
    FocusScope.of(context).unfocus();
    setState(() => _pidiendoCodigo = true);
    try {
      final r = await Sesion.actual.api.pedirCodigo(_correo.text.trim());
      if (!mounted) return;
      setState(() {
        _correoEnviado = _correo.text.trim();
        _universidad = r.universidad;
        _codigoDemo = r.codigoDemo;
        _codigo.clear();
      });
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _pidiendoCodigo = false);
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _siguiente() async {
    if (_paso < 3) {
      FocusScope.of(context).unfocus();
      setState(() => _paso++);
      return;
    }
    setState(() => _enviando = true);
    try {
      final s = Sesion.actual;
      final r = await s.api.registrar({
        'correo': _correoEnviado,
        'codigo': _codigo.text.trim(),
        'nombre': _nombre.text.trim(),
        'rango_edad': _rango,
        'comuna': _comuna,
        'tramo_id': _tramo,
        'actividad': _actividad,
        'ritmo': _ritmo,
        'primera_vez': _primeraVez == null ? null : _primeraVez == 'si',
        'acepta_datos': _aceptaDatos,
        'declara_mayor': !_esMenor && _declaraMayor,
        'permiso_acudiente': _permisoAcudiente,
        'acudiente_nombre': _esMenor ? _acudiente.text.trim() : null,
      });
      await s.guardarToken(r.token);
      s.matchPendiente = true;
      await Notificaciones.pedirPermiso();
      await Notificaciones.programarSemana();
      if (!mounted) return;
      // Recién registrado: primero el quiz de estilo (se puede saltar), después la app.
      // Va antes del match automático para que el desempate por afinidad ya cuente desde el primer parche.
      final quiz = _cat?.quiz;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => quiz == null ? const PrincipalScreen() : QuizScreen(quiz: quiz, alInicio: true),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        if (e.mensaje.contains('código') || e.mensaje.contains('correo')) _paso = 0;
      });
      _aviso(e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Atrás', onPressed: _enviando ? null : _atras),
        title: Text('Paso ${_paso + 1} de 4'),
      ),
      body: SafeArea(
        child: cat == null
            ? _cargando()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: 'Paso ${_paso + 1} de 4',
                    child: Cinta(alto: 6, llenos: _paso + 1),
                  ),
                  Expanded(
                    child: ListView(
                      padding: rellenoAncho(context, arriba: 20, abajo: 24),
                      children: [
                        Row(
                          children: [
                            IconoBurbuja(_iconos[_paso], color: _colores[_paso], fondo: _suaves[_paso], tamano: 52),
                            const SizedBox(width: 14),
                            Expanded(child: Text(_titulos[_paso], style: Theme.of(context).textTheme.headlineMedium)),
                          ],
                        ),
                        ..._contenido(cat),
                      ],
                    ),
                  ),
                  BarraInferior(
                    child: FilledButton(
                      onPressed: _pasoValido && !_enviando ? _siguiente : null,
                      child: _enviando
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cv.tealInk))
                          : Text(_paso < 3 ? 'Siguiente' : 'Crear mi perfil'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _cargando() {
    if (_error == null) {
      return ListView(
        padding: rellenoAncho(context, arriba: 20, abajo: 20),
        children: const [
          Esqueleto(alto: 52, ancho: 260, radio: Cv.radioMd),
          SizedBox(height: 24),
          Esqueleto(alto: 56, radio: Cv.radioMd),
          SizedBox(height: 12),
          Esqueleto(alto: 56, radio: Cv.radioMd),
          SizedBox(height: 12),
          Esqueleto(alto: 120),
        ],
      );
    }
    return ListView(
      padding: rellenoAncho(context, arriba: 20, abajo: 20),
      children: [
        TarjetaError(
          mensaje: _error!,
          reintentar: _cargar,
          cambiarServidor: () => dialogoServidor(
            context,
            actual: Sesion.actual.apiUrl,
            guardar: (url) async {
              await Sesion.actual.cambiarUrl(url);
              await _cargar();
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _contenido(Catalogo cat) {
    switch (_paso) {
      case 0:
        return _pasoCorreo(cat);
      case 1:
        return [
          const TituloSeccion('Tu nombre', ayuda: 'Solo el primero. Es lo único que verá tu grupo, junto con tu universidad.'),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(hintText: 'Ej. Valentina', counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          TituloSeccion(
            'Tu edad',
            ayuda: cat.permiteMenores
                ? 'Los menores de edad solo van en parches con otros menores de edad.'
                : 'Por ahora el piloto es para jóvenes de 18 a 28 años.',
          ),
          SelectorFila(opciones: cat.rangosEdad, valor: _rango, onChanged: (v) => setState(() => _rango = v)),
          const TituloSeccion('¿En qué comuna vives?'),
          SelectorComuna(comunas: cat.comunas, valor: _comuna, onChanged: (v) => setState(() => _comuna = v)),
        ];
      case 2:
        return [
          const TituloSeccion('¿Qué te gusta hacer?', ayuda: 'Te recomendamos parches de esa actividad.'),
          SelectorActividad(opciones: cat.actividades, valor: _actividad, onChanged: (v) => setState(() => _actividad = v)),
          const TituloSeccion('¿A qué ritmo?', ayuda: 'Con esto armamos grupos de gente que va a una velocidad parecida.'),
          SelectorOpciones(opciones: cat.ritmos, valor: _ritmo, onChanged: (v) => setState(() => _ritmo = v)),
          const TituloSeccion('¿Qué estación te queda cerca?', ayuda: 'Opcional. Te mostramos primero los parches que salen de ahí.'),
          SelectorEstacion(catalogo: cat, comuna: _comuna, valor: _tramo, onChanged: (v) => setState(() => _tramo = v)),
          const TituloSeccion('¿Habías ido antes a la CicloVida?', ayuda: 'Opcional. Nos ayuda a saber si logramos que más jóvenes la conozcan.'),
          SelectorOpciones(
            opciones: const [
              Opcion(id: 'no', nombre: 'Sí, ya había ido'),
              Opcion(id: 'si', nombre: 'No, sería mi primera vez'),
            ],
            valor: _primeraVez,
            onChanged: (v) => setState(() => _primeraVez = v),
          ),
        ];
      default:
        return _pasoAutorizacion(cat);
    }
  }

  List<Widget> _pasoCorreo(Catalogo cat) {
    final t = Theme.of(context).textTheme;
    final enviado = _correoEnviado != null && _correoEnviado == _correo.text.trim();
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Los parches son solo entre estudiantes verificados. Usa el correo que te dio tu universidad: '
          'te enviamos un código de 6 dígitos. No guardamos tu correo.',
          style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
        ),
      ),
      const TituloSeccion('Tu correo institucional'),
      TextField(
        controller: _correo,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.send,
        decoration: const InputDecoration(hintText: 'nombre@usbcali.edu.co'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _correo.text.contains('@') ? _pedirCodigo() : null,
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: _pidiendoCodigo || !_correo.text.contains('@') ? null : _pedirCodigo,
        child: Text(enviado ? 'Enviar otro código' : 'Enviarme el código'),
      ),
      Align(
        child: TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const IngresoScreen()),
          ),
          child: const Text('¿Ya tienes cuenta? Entra con tu correo'),
        ),
      ),
      if (enviado) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Cv.verdeSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified, color: Cv.verdeInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_universidad ?? 'Tu universidad'}. Te enviamos el código a $_correoEnviado.',
                  style: t.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (_codigoDemo != null) ...[
          const SizedBox(height: 8),
          Text(
            'Modo demo, sin servidor de correo: tu código es $_codigoDemo',
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
        const TituloSeccion('Código de 6 dígitos'),
        TextField(
          controller: _codigo,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontFamily: Cv.display, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const TituloSeccion('Universidades del piloto'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final u in cat.universidades)
            Chip(
              label: Text(u.corto),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Cv.ink),
            ),
        ],
      ),
    ];
  }

  List<Widget> _pasoAutorizacion(Catalogo cat) {
    final t = Theme.of(context).textTheme;
    final tramo = _tramo == null ? null : cat.tramo(_tramo!);
    final comuna = _comuna == null ? null : cat.comuna(_comuna!);
    final horaSabado = horaBonita('$kAvisoSabadoHora:${_dosDigitos(kAvisoSabadoMinuto)}');
    final horaDomingo = horaBonita('$kAvisoDomingoHora:${_dosDigitos(kAvisoDomingoMinuto)}');
    return [
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(_nombre.text.trim(), overflow: TextOverflow.ellipsis, style: t.headlineSmall)),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, size: 20, color: Cv.verdeInk),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_universidad ?? ''}. ${cat.nombreDe(cat.actividades, _actividad ?? '')} a ritmo '
                '${cat.nombreDe(cat.ritmos, _ritmo ?? '').toLowerCase()}'
                '${tramo == null ? '' : ', cerca de la estación ${tramo.nombre}'}.',
                style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
              ),
              if (comuna != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Vives en la ${comuna.nombre.toLowerCase()}'
                  '${comuna.barrios.isEmpty ? '' : ', por los lados de ${comuna.barriosResumen(maximo: 2)}'}.',
                  style: t.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      _Aviso(
        icono: Icons.notifications_active_outlined,
        texto: 'Después eliges tu parche. Te avisamos el sábado a las $horaSabado con tu grupo para que confirmes, '
            'y el domingo a la $horaDomingo para saber cómo te fue.',
      ),
      const SizedBox(height: 16),
      Text('Aviso de privacidad', style: t.titleMedium),
      const SizedBox(height: 8),
      const _Punto('Tu correo solo sirve para verificar que estudias: guardamos una huella cifrada y el nombre de tu universidad.'),
      const _Punto('Pedimos tu primer nombre, edad, comuna y preferencias. Nada de documento, dirección, teléfono ni fotos.'),
      const _Punto('Armamos los grupos con k-means usando tu ritmo, tu rango de edad, cuántos domingos has ido y, '
          'si respondes el quiz opcional, tu estilo de parche (solo para desempatar). Nadie ve tus respuestas.'),
      const _Punto('Tu grupo ve tu primer nombre y tu universidad. La Secretaría solo ve cifras, nunca personas.'),
      const _Punto('La pregunta de cómo te sentiste es opcional. Puedes borrar tus datos cuando quieras desde Ajustes.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AvisoPrivacidadScreen())),
          child: const Text('Leer el aviso de privacidad completo'),
        ),
      ),
      if (!_esMenor)
        CheckboxListTile(
          value: _declaraMayor,
          onChanged: (v) => setState(() => _declaraMayor = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Declaro que tengo 18 años o más'),
          subtitle: const Text('Obligatorio. Guardamos la fecha en que lo confirmaste.'),
        ),
      CheckboxListTile(
        value: _aceptaDatos,
        onChanged: (v) => setState(() => _aceptaDatos = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text('Leí el aviso de privacidad y autorizo el tratamiento de mis datos'),
        subtitle: const Text('Ley 1581 de 2012. Guardamos la fecha y la versión del aviso que aceptaste.'),
      ),
      if (_esMenor) ...[
        const SizedBox(height: 8),
        Text('Autorización de tu acudiente', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Como tienes entre 14 y 17 años, tu mamá, papá o acudiente debe autorizarte. Pídele que lo complete contigo.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _acudiente,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre completo del acudiente'),
          onChanged: (_) => setState(() {}),
        ),
        CheckboxListTile(
          value: _permisoAcudiente,
          onChanged: (v) => setState(() => _permisoAcudiente = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Soy el acudiente y autorizo que use Parches CicloVida'),
        ),
      ],
    ];
  }
}

String _dosDigitos(int n) => n.toString().padLeft(2, '0');

class _Punto extends StatelessWidget {
  const _Punto(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: SizedBox(width: 6, height: 6, child: DecoratedBox(decoration: BoxDecoration(color: Cv.tealInk, shape: BoxShape.circle))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Cv.tealSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Cv.tealInk),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
