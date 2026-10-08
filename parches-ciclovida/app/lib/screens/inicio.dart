import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../formato.dart';
import '../models.dart';
import '../notificaciones.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/boleta.dart';
import '../widgets/comunes.dart';
import '../widgets/demo.dart';
import '../widgets/compartir.dart';
import '../widgets/diseno.dart';
import '../widgets/domingo.dart';
import '../widgets/parche_card.dart';
import '../widgets/telegram.dart';
import 'ajustes.dart';
import 'bienvenida.dart';
import 'chat.dart';
import 'elegir_parche.dart';
import 'encuesta.dart';
import 'historial.dart';
import 'preferencias.dart';
import 'quiz.dart';
import 'reporte.dart';

/// "Mi parche": lo que el joven ve casi siempre.
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key, this.activo = true});

  /// Cuando la pestaña vuelve a quedar activa, se sincroniza con el servidor.
  final bool activo;

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  /// Cada cuánto se sincroniza sola mientras la app está en pantalla.
  static const _cadaCuanto = Duration(seconds: 30);

  Catalogo? _cat;
  Perfil? _perfil;
  EstadoParche? _estado;
  ChatEstado? _chat;
  String? _error;
  bool _ocupado = false;

  /// El parche también cambia fuera de la app (bot de Telegram, lista de espera): la pantalla se
  /// sincroniza al volver a la app, al volver a esta pestaña y cada 30 segundos.
  Timer? _timerSync;
  late final AppLifecycleListener _ciclo;

  Api get _api => Sesion.actual.api;

  @override
  void initState() {
    super.initState();
    Notificaciones.tocada.addListener(_alTocarNotificacion);
    _ciclo = AppLifecycleListener(onResume: _sincronizar);
    _timerSync = Timer.periodic(_cadaCuanto, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _sincronizar();
    });
    _cargar().then((_) => _alTocarNotificacion());
  }

  @override
  void didUpdateWidget(InicioScreen viejo) {
    super.didUpdateWidget(viejo);
    if (widget.activo && !viejo.activo) _sincronizar();
  }

  @override
  void dispose() {
    _timerSync?.cancel();
    _ciclo.dispose();
    Notificaciones.tocada.removeListener(_alTocarNotificacion);
    super.dispose();
  }

  /// Recarga por cambios hechos fuera de la app, y avisa qué cambió. Se salta si hay una acción en
  /// curso o si hay otra pantalla encima (elegir parche, ajustes): esas recargan al volver.
  Future<void> _sincronizar() async {
    if (!mounted || _ocupado || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    await _cargar(avisarCambios: true);
  }

  /// Si el parche o la respuesta cambiaron desde fuera (por ejemplo, por Telegram), lo dice.
  void _avisarCambiosDeFuera(EstadoParche antes, EstadoParche ahora) {
    if (antes.salida?.id != ahora.salida?.id) {
      // del match de la lista de espera ya avisa la notificación
      if (antes.estado == 'en_espera') return;
      if (ahora.salida != null) {
        _aviso('Tu parche se actualizó: ahora estás en el ${ahora.salida!.nombre}.');
      } else if (antes.salida != null) {
        _aviso('Saliste de tu parche.');
      }
      return;
    }
    if (antes.miRespuesta != ahora.miRespuesta) {
      if (ahora.miRespuesta == 'confirmado') _aviso('Quedó confirmado que vas el domingo.');
      if (ahora.miRespuesta == 'declinado') _aviso('Quedó registrado que este domingo no vas.');
    }
  }

  Future<void> _cargar({bool avisarCambios = false}) async {
    final antes = _estado;
    try {
      final cat = _cat ?? await _api.catalogo();
      final perfil = await _api.yo();
      var estado = await _api.miParche();
      // Recién registrado y sin parche: el match lo une solo a un parche con gente y sus mismas
      // características, o lo deja en lista de espera (la pantalla muestra el más parecido).
      ParcheOpcion? celebrarMatch;
      if (estado.estado == 'sin_parche' && Sesion.actual.matchPendiente) {
        Sesion.actual.matchPendiente = false;
        estado = await _api.buscarMatch();
        if (estado.estado == 'inscrito' && estado.salida != null) celebrarMatch = estado.salida;
      }
      // el chat solo existe con parche; si falla, la pantalla sigue sin él
      ChatEstado? chat;
      if (estado.estado == 'inscrito' || estado.estado == 'asignado') {
        try {
          chat = await _api.chat();
        } on ApiException {
          chat = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _cat = cat;
        _perfil = perfil;
        _estado = estado;
        _chat = chat;
        _error = null;
      });
      if (avisarCambios && antes != null) _avisarCambiosDeFuera(antes, estado);
      if (celebrarMatch != null) await _celebrarMatch(celebrarMatch);
      await _revisarNotificaciones();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.sesionInvalida) {
        await _salir();
        return;
      }
      setState(() => _error = e.mensaje);
    }
  }

  /// Avisos del servidor (por ahora, "tu espera encontró parche"): se muestran
  /// como notificación (o tarjeta en web) y se marcan leídos.
  Future<void> _revisarNotificaciones() async {
    try {
      final nuevas = (await _api.notificaciones()).where((n) => !n.leida).toList();
      if (nuevas.isEmpty || !mounted) return;
      await _api.marcarNotificacionesLeidas();
      if (!mounted) return;
      final n = nuevas.first;
      await Notificaciones.probar(context, Aviso(id: 900 + n.id, titulo: n.titulo, cuerpo: n.cuerpo, payload: 'match'));
    } on ApiException {
      // sin conexión: se reintenta en la próxima carga
    }
  }

  Future<void> _salir() async {
    await Sesion.actual.cerrar();
    await Notificaciones.cancelarTodas();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const BienvenidaScreen()),
      (route) => false,
    );
  }

  Future<void> _alTocarNotificacion() async {
    final toque = Notificaciones.tocada.value;
    if (toque == null) return;
    Notificaciones.tocada.value = null;
    await _cargar();
    if (!mounted) return;
    if (toque.payload == 'encuesta' && (_estado?.encuestaPendiente ?? false)) {
      await _abrirEncuesta();
    }
  }

  Future<void> _accion(Future<void> Function() hacer, {String? exito}) async {
    setState(() => _ocupado = true);
    try {
      await hacer();
      await _cargar();
      if (exito != null) _aviso(exito);
    } on ApiException catch (e) {
      _aviso(e.mensaje);
      await _cargar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _responder(bool va) => _accion(
        () => _api.responder(va: va),
        exito: va ? '¡Listo! Tu parche ya sabe que vas.' : 'Gracias por avisar. Tu parche ya lo sabe.',
      );

  Future<void> _pausar(bool pausar) => _accion(() => _api.cambiar({'pausar_esta_semana': pausar}));

  Future<void> _unirme(ParcheOpcion p) => _accion(() => _api.unirme(p.id), exito: '¡Listo! Te uniste al ${p.nombre}.');

  Future<void> _buscarMatch() async {
    setState(() => _ocupado = true);
    try {
      final estado = await _api.buscarMatch();
      if (!mounted) return;
      setState(() => _estado = estado);
      // En espera no hay diálogo: la pantalla ya muestra el parche más parecido con su botón.
      if (estado.estado == 'inscrito' && estado.salida != null) {
        await _celebrarMatch(estado.salida!);
        await _cargar(); // trae también la invitación al chat del parche nuevo
      }
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// El momento "¡Match!": una celebración con la cinta de colores, no un aviso cualquiera.
  Future<void> _celebrarMatch(ParcheOpcion s) async {
    if (!mounted) return;
    await celebrar(
      context,
      titulo: '¡Match!',
      texto: 'Te unimos al ${s.nombre}: ${s.actividadNombre.toLowerCase()} a las ${s.horaNombre} en la estación '
          '${s.tramoNombre}. Hay gente con tus mismos planes.',
      icono: iconoDe(s.actividad),
      color: coloresDe(s.actividad).tinta,
    );
  }

  Future<void> _cancelarEspera() => _accion(_api.cancelarEspera, exito: 'Listo, dejamos de buscar por ti.');

  Future<void> _salirDelParche() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salirte de tu parche?'),
        content: const Text('Tu lugar queda libre para alguien más. Puedes unirte a otro cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salirme')),
        ],
      ),
    );
    if (ok == true) await _accion(_api.salirme, exito: 'Saliste del parche.');
  }

  Future<void> _elegir() async {
    final cat = _cat;
    if (cat == null) return;
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ElegirParcheScreen(
          catalogo: cat,
          tramoInicial: _perfil?.tramoId,
          actualId: _estado?.salida?.id,
        ),
      ),
    );
    await _cargar();
    if (msg != null) _aviso(msg);
  }

  Future<void> _abrirEncuesta() async {
    final e = _estado?.encuesta;
    if (e == null) return;
    final enviada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => EncuestaScreen(info: e)),
    );
    if (enviada == true) {
      await _cargar();
      if (!mounted) return;
      await celebrar(
        context,
        titulo: '¡Gracias!',
        texto: 'Gracias por contarnos. Nos vemos el próximo domingo.',
        icono: Icons.favorite,
        color: Cv.coralInk,
        boton: '¡Nos vemos!',
      );
    }
  }

  /// Atajos de la demo. Al terminar el domingo se abre la encuesta de una vez, como si llegara el aviso.
  Future<void> _abrirDemo() async {
    final estado = _estado;
    if (estado == null) return;
    final r = await abrirHojaDemo(context, estado: estado);
    if (r == null || !mounted) return;
    await _cargar();
    if (!mounted) return;
    if (r.paso == PasoDemo.armarGrupos) {
      if (r.mensaje != null) _aviso(r.mensaje!);
      return;
    }
    if (_estado?.encuestaPendiente ?? false) {
      await _abrirEncuesta();
    } else if (r.mensaje != null) {
      _aviso(r.mensaje!);
    }
  }

  Future<void> _abrirRacha() async {
    final estado = _estado;
    if (estado == null) return;
    final verDomingos = await abrirRacha(context, estado.racha);
    if (verDomingos != true || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistorialScreen()));
    await _cargar();
  }

  Future<void> _abrirPreferencias() async {
    final cat = _cat;
    final perfil = _perfil;
    if (cat == null || perfil == null) return;
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => PreferenciasScreen(catalogo: cat, perfil: perfil)),
    );
    if (cambio == true) await _cargar();
  }

  Future<void> _abrirQuiz() async {
    final q = _cat?.quiz;
    if (q == null) return;
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => QuizScreen(quiz: q)),
    );
    if (msg != null) {
      _aviso(msg);
      await _cargar();
    }
  }

  Future<void> _abrirAjustes() async {
    final resultado = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => AjustesScreen(onPreferencias: _abrirPreferencias, onQuiz: _abrirQuiz)),
    );
    if (resultado == 'borrado' || resultado == 'salir') {
      await _salir();
    } else {
      await _cargar();
    }
  }

  Future<void> _reportar() async {
    final grupo = _estado?.grupo;
    final cat = _cat;
    if (grupo == null || cat == null) return;
    final msg = await abrirReporte(context, grupo: grupo, motivos: cat.motivosReporte);
    if (msg != null) {
      _aviso(msg);
      await _cargar();
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    // En celulares angostos no cabe el logo completo junto a los botones: van solo los anillos.
    final angosto = MediaQuery.sizeOf(context).width < 400;
    final estado = _estado;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: angosto
            ? Image.asset('assets/img/parche-icono.png', height: 38, semanticLabel: 'Parche CicloVida')
            : Image.asset('assets/img/parche-logo.png', height: 38, semanticLabel: 'Parche CicloVida'),
        actions: [
          if (kModoDemo && estado != null) ...[
            BotonDemo(onTap: _abrirDemo),
            const SizedBox(width: 6),
          ],
          if (estado != null) BotonRacha(racha: estado.racha, onTap: _abrirRacha),
          const BotonTelegram(),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Ajustes', onPressed: _abrirAjustes),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: rellenoAncho(context, arriba: 4, abajo: 32),
          children: _animar(_contenido()),
        ),
      ),
    );
  }

  /// Cada bloque entra suave y escalonado (los espacios no se animan). La llave cambia cuando cambia
  /// lo que hay en ese lugar (del esqueleto a la tarjeta, de la espera al parche), y así vuelve a entrar.
  List<Widget> _animar(List<Widget> bloques) {
    var orden = 0;
    return [
      for (final b in bloques)
        if (b is SizedBox)
          b
        else
          Aparecer(key: ValueKey('${b.runtimeType}-$orden'), orden: orden++, child: b),
    ];
  }

  List<Widget> _contenido() {
    final t = Theme.of(context).textTheme;
    final estado = _estado;
    if (_error != null && estado == null) {
      return [
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
      ];
    }
    if (estado == null) {
      // la forma de lo que viene mientras carga
      return const [
        Esqueleto(alto: 150),
        SizedBox(height: 16),
        Esqueleto(alto: 260),
        SizedBox(height: 16),
        Esqueleto(alto: 110),
      ];
    }

    final nombre = _perfil?.nombre;
    return [
      if (estado.encuestaPendiente) ...[
        _TarjetaEncuesta(info: estado.encuesta!, onTap: _abrirEncuesta),
        const SizedBox(height: 16),
      ],
      _Encabezado(nombre: nombre, estado: estado),
      const SizedBox(height: 12),
      if (estado.clima != null && estado.estado != 'suspendido') ...[
        TarjetaClima(clima: estado.clima!),
        const SizedBox(height: 16),
      ] else
        const SizedBox(height: 4),
      ..._principal(estado),
      if (_perfil != null && !_perfil!.quizRespondido && _cat?.quiz != null && estado.estado != 'suspendido') ...[
        const SizedBox(height: 20),
        _TarjetaQuiz(titulo: _cat!.quiz!.titulo, onResponder: _abrirQuiz),
      ],
      const SizedBox(height: 24),
      if (_perfil != null && _cat != null) ...[
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 10), child: Rotulo('Tus preferencias')),
        _TarjetaPreferencias(perfil: _perfil!, cat: _cat!, onCambiar: _abrirPreferencias),
      ],
      const SizedBox(height: 24),
      Text(
        'Tu grupo solo ve tu primer nombre y tu universidad. La Alcaldía solo ve cifras agregadas.',
        textAlign: TextAlign.center,
        style: t.bodySmall,
      ),
    ];
  }

  /// El chat del parche: invitación opcional, o el acceso si ya se unió. Con "Ahora no" queda un
  /// enlace discreto para entrar después, sin insistir.
  List<Widget> _seccionChat() {
    final c = _chat;
    final parcheId = c?.parcheId;
    if (c == null || !c.disponible || parcheId == null) return const [];
    if (c.unido) {
      return [const SizedBox(height: 12), _TarjetaChat(enElChat: c.enElChat, onAbrir: () => _abrirChat())];
    }
    if (Sesion.actual.chatDescartado(parcheId)) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _ocupado ? null : _unirmeAlChat,
            icon: const Icon(Icons.forum_outlined, size: 20),
            label: const Text('Unirme al chat del parche'),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 12),
      _InvitacionChat(
        enElChat: c.enElChat,
        ocupado: _ocupado,
        onUnirme: _unirmeAlChat,
        onAhoraNo: () async {
          await Sesion.actual.descartarChat(parcheId);
          if (mounted) setState(() {});
        },
      ),
    ];
  }

  Future<void> _unirmeAlChat() async {
    setState(() => _ocupado = true);
    ChatEstado? estado;
    try {
      estado = await _api.chatUnirme();
    } on ApiException catch (e) {
      _aviso(e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    if (estado != null && mounted) {
      setState(() => _chat = estado);
      await _abrirChat(estado);
    }
  }

  Future<void> _abrirChat([ChatEstado? abierto]) async {
    var estado = abierto;
    if (estado == null) {
      try {
        estado = await _api.chat();
      } on ApiException catch (e) {
        _aviso(e.mensaje);
        return;
      }
    }
    if (!mounted || !estado.unido) return;
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => ChatScreen(estado: estado!)),
    );
    await _cargar();
    if (msg != null) _aviso(msg);
  }

  List<Widget> _principal(EstadoParche estado) {
    switch (estado.estado) {
      case 'asignado':
        return [
          ParcheCard(
            grupo: estado.grupo!,
            miRespuesta: estado.miRespuesta,
            ajustes: estado.ajustes,
            ocupado: _ocupado,
            onResponder: _responder,
            onReportar: _reportar,
            onCambiar: _elegir,
            onSalir: _salirDelParche,
          ),
          _BotonCompartir(
            parche: ParcheParaCompartir(
              nombre: estado.grupo!.nombre,
              fecha: estado.jornadaFecha,
              horaNombre: estado.grupo!.horaNombre,
              actividad: estado.grupo!.actividad,
              actividadNombre: estado.grupo!.actividadNombre,
              tramoNombre: estado.grupo!.tramoNombre,
            ),
          ),
          ..._seccionChat(),
        ];
      case 'inscrito':
        final s = estado.salida!;
        return [
          BoletaParche(parche: s, onUnirme: () {}),
          _BotonCompartir(
            parche: ParcheParaCompartir(
              nombre: s.nombre,
              fecha: estado.jornadaFecha,
              horaNombre: s.horaNombre,
              actividad: s.actividad,
              actividadNombre: s.actividadNombre,
              tramoNombre: s.tramoNombre,
            ),
          ),
          ..._seccionChat(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Rotulo('Lo que sigue'),
                  const SizedBox(height: 8),
                  Text('Tu grupo se arma el sábado', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: RutaPasos(
                      nodo: 34,
                      pasos: [
                        PasoRuta(
                          icono: Icons.diversity_3,
                          color: Cv.coralInk,
                          titulo: 'Sábado, 5:00 p. m.',
                          texto: 'Dividimos a la gente de tu parche en grupos de 3 a 6 con ritmo, edad y experiencia parecidos.',
                        ),
                        PasoRuta(
                          icono: Icons.notifications_active,
                          color: Cv.verdeInk,
                          titulo: 'Sábado, 7:00 p. m.',
                          texto: 'Te avisamos quiénes van contigo.',
                        ),
                        PasoRuta(
                          icono: Icons.flag,
                          color: Cv.tealInk,
                          titulo: 'Domingo',
                          texto: 'Se encuentran en la estación y arrancan.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _ocupado ? null : _elegir,
                        icon: const Icon(Icons.swap_horiz, size: 20),
                        label: const Text('Cambiar de parche'),
                      ),
                      TextButton(
                        onPressed: _ocupado ? null : _salirDelParche,
                        style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                        child: const Text('Salirme'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ];
      case 'suspendido':
        return const [
          TarjetaEstado(
            icono: Icons.pause_circle_outline,
            color: Cv.rojoInk,
            titulo: 'Tu cuenta está en revisión',
            texto: 'Recibimos reportes sobre un encuentro y una persona del equipo los está revisando. '
                'Mientras tanto no puedes unirte a parches. Si crees que es un error, escríbenos.',
          ),
        ];
      case 'pausado':
        return [
          TarjetaEstado(
            icono: Icons.weekend_outlined,
            color: Cv.coralInk,
            titulo: 'Esta semana descansas',
            texto: 'Si cambias de idea, elige un parche y listo.',
            accion: FilledButton(
              onPressed: _ocupado ? null : () => _pausar(false).then((_) => _elegir()),
              child: const Text('Sí voy, quiero elegir parche'),
            ),
          ),
        ];
      case 'en_espera':
        final espera = estado.espera;
        final parecido = espera?.masParecido;
        return [
          _TarjetaEspera(minutos: espera?.minutos ?? 0),
          const SizedBox(height: 12),
          const TarjetaTelegram(),
          if (parecido != null && (espera?.sugerencias.isEmpty ?? true)) ...[
            const SizedBox(height: 20),
            Text('¿Tienes la iniciativa?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Únete al más parecido aunque aún no haya nadie: el match irá sumando gente que encaje contigo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            BoletaParche(parche: parecido, ocupado: _ocupado, onUnirme: () => _unirme(parecido)),
          ],
          if (espera != null && espera.sugerencias.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Mientras tanto, estos se te parecen', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Seguimos buscando tu parche exacto, pero puedes unirte ya a uno parecido.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final p in espera.sugerencias)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BoletaParche(parche: p, ocupado: _ocupado, onUnirme: () => _unirme(p)),
              ),
          ],
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(onPressed: _ocupado ? null : _elegir, child: const Text('Prefiero elegir yo')),
              TextButton(
                onPressed: _ocupado ? null : _cancelarEspera,
                style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                child: const Text('Cancelar la búsqueda'),
              ),
            ],
          ),
        ];
      default:
        return [
          _TarjetaElegir(ocupado: _ocupado, onBuscarMatch: _buscarMatch, onVerTodos: _elegir),
          Align(
            child: TextButton(
              onPressed: _ocupado ? null : () => _pausar(true),
              style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
              child: const Text('Esta semana no voy'),
            ),
          ),
        ];
    }
  }
}

/// Cartel de la jornada: fondo oscuro con la cinta curvándose como una vía, la fecha en grande y un
/// anillo que se va llenando a medida que se acerca el domingo.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.nombre, required this.estado});

  final String? nombre;
  final EstadoParche estado;

  /// Días que faltan para la jornada (0 = hoy), o null si la fecha no se entiende.
  int? _diasQueFaltan() {
    final f = DateTime.tryParse(estado.jornadaFecha);
    if (f == null) return null;
    final hoy = DateTime.now();
    return DateTime(f.year, f.month, f.day).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dias = _diasQueFaltan();
    return FondoCarril(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Rotulo(
                    dias != null && dias <= 0 ? 'Hoy' : (dias == 1 ? 'Mañana' : 'Este domingo'),
                    color: Cv.coral,
                  ),
                  const SizedBox(height: 8),
                  if (nombre != null)
                    Row(
                      children: [
                        Flexible(
                          child: Text('Hola, $nombre',
                              overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(color: Cv.inkMuted)),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, size: 18, color: Cv.tealInk, semanticLabel: 'Estudiante verificado'),
                      ],
                    ),
                  Text(
                    capitalizar(fechaLarga(estado.jornadaFecha)),
                    style: t.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Cv.coralInk),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'CicloVida de ${horaBonita(estado.inicio)} a ${horaBonita(estado.fin)}',
                          style: t.bodySmall?.copyWith(color: Cv.ink, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (dias != null) ...[
              const SizedBox(width: 12),
              AnilloCuenta(dias: dias),
            ],
          ],
        ),
      ),
    );
  }
}

/// Invitar a los amigos con una imagen del parche (sin la gente del grupo).
class _BotonCompartir extends StatelessWidget {
  const _BotonCompartir({required this.parche});

  final ParcheParaCompartir parche;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        child: TextButton.icon(
          onPressed: () => abrirCompartir(context, parche),
          icon: const Icon(Icons.ios_share, size: 20),
          label: const Text('Compartir mi parche'),
        ),
      ),
    );
  }
}

/// Lista de espera: el match no encontró parche con gente todavía.
class _TarjetaEspera extends StatelessWidget {
  const _TarjetaEspera({required this.minutos});

  final int minutos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Cv.tealSoft,
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
            child: Row(
              children: [
                const Radar(icono: Icons.person_search, tamano: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Rotulo('Lista de espera'),
                      const SizedBox(height: 4),
                      Text('Buscando tu parche…', style: t.headlineSmall?.copyWith(color: Cv.tealInk)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aún no hay un parche con gente y tus mismas características (hora, estación y actividad). '
                  'Apenas alguien encaje contigo, te unimos y te avisamos aquí y por Telegram.',
                  style: t.bodyMedium?.copyWith(color: Cv.inkMuted),
                ),
                if (minutos > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Cv.surface, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 16, color: Cv.inkMuted),
                        const SizedBox(width: 6),
                        Text(
                          minutos == 1 ? 'Llevas 1 minuto en espera' : 'Llevas $minutos minutos en espera',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Cv.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Invitación cuando no tiene parche: que el match busque por él, o elegir a mano.
class _TarjetaElegir extends StatelessWidget {
  const _TarjetaElegir({required this.ocupado, required this.onBuscarMatch, required this.onVerTodos});

  final bool ocupado;
  final VoidCallback onBuscarMatch;
  final VoidCallback onVerTodos;

  @override
  Widget build(BuildContext context) {
    return FondoCarril(
      colores: const [Cv.surfaceRaised, Cv.brisaVerde],
      intensidad: 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Rotulo('Tu domingo', color: Cv.verde),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 56),
              child: Text('Todavía no tienes parche', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(right: 56),
              child: Text(
                'Deja que el match te una al parche con gente de tu hora, tu estación y tu actividad, '
                'o escoge uno tú en las 11 estaciones.',
                style: TextStyle(fontSize: 16, height: 1.45, color: Cv.inkMuted),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: ocupado ? null : onBuscarMatch,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('Buscar mi parche por mí'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: ocupado ? null : onVerTodos,
              child: const Text('Elegir yo mismo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "¿Deseas unirte al chat de tu parche?": opcional, con lo que se comparte dicho de frente.
class _InvitacionChat extends StatelessWidget {
  const _InvitacionChat({required this.enElChat, required this.ocupado, required this.onUnirme, required this.onAhoraNo});

  final int enElChat;
  final bool ocupado;
  final VoidCallback onUnirme;
  final VoidCallback onAhoraNo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconoBurbuja(Icons.forum, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 44),
                const SizedBox(width: 12),
                Expanded(child: Text('¿Deseas unirte al chat de tu parche?', style: t.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Es opcional. Ahí cuadran la llegada y se van conociendo antes del domingo. Si entras, el chat ve '
              'tu primer nombre y tu universidad.${enElChat > 0 ? ' Ya hay $enElChat ${enElChat == 1 ? 'persona' : 'personas'}.' : ''}',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ocupado ? null : onUnirme,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                    icon: const Icon(Icons.forum_outlined, size: 20),
                    label: const Text('Unirme al chat'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: ocupado ? null : onAhoraNo,
                  style: TextButton.styleFrom(foregroundColor: Cv.inkMuted),
                  child: const Text('Ahora no'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Acceso al chat cuando ya se unió.
class _TarjetaChat extends StatelessWidget {
  const _TarjetaChat({required this.enElChat, required this.onAbrir});

  final int enElChat;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onAbrir,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: const IconoBurbuja(Icons.forum, color: Cv.coralInk, fondo: Cv.coralSoft, tamano: 44),
        title: const Text('Chat del parche', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$enElChat en el chat · toca para abrir'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Invitación al quiz de estilo: divertido, opcional y sin resultados visibles.
class _TarjetaQuiz extends StatelessWidget {
  const _TarjetaQuiz({required this.titulo, required this.onResponder});

  final String titulo;
  final VoidCallback onResponder;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      color: Cv.coralSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconoBurbuja(Icons.local_drink, color: Cv.coralInk, fondo: Colors.white, tamano: 46),
                const SizedBox(width: 12),
                Expanded(child: Text('¿Jugo con el parche o directo a casa?', style: t.titleMedium?.copyWith(color: Cv.coralInk))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cuéntanos tu estilo de domingo en 5 preguntas (un minuto). Es opcional y nadie ve tus '
              'respuestas: solo sirven para juntarte con gente que goza el plan como tú.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onResponder,
                style: botonDeColor(Cv.coralInk, minimo: const Size(0, 46), relleno: const EdgeInsets.symmetric(horizontal: 20)),
                child: Text(titulo),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaEncuesta extends StatelessWidget {
  const _TarjetaEncuesta({required this.info, required this.onTap});

  final EncuestaInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final grupo = info.grupoNombre == null ? '' : ' con el ${info.grupoNombre}';
    return Card(
      color: Cv.coralSoft,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Cómo te fue el ${fechaCorta(info.jornadaFecha)}$grupo?', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('Tres preguntas, menos de un minuto.', style: t.bodyMedium),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: botonDeColor(Cv.coralInk),
              child: const Text('Responder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPreferencias extends StatelessWidget {
  const _TarjetaPreferencias({required this.perfil, required this.cat, required this.onCambiar});

  final Perfil perfil;
  final Catalogo cat;
  final VoidCallback onCambiar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tramo = perfil.tramoId == null ? null : cat.tramo(perfil.tramoId!);
    final comuna = cat.comuna(perfil.comuna);
    final barrios = comuna == null || comuna.barrios.isEmpty ? '' : ' · ${comuna.barrios.take(2).join(', ')}…';
    final col = coloresDe(perfil.actividad);
    final filas = <(IconData, String, String)>[
      if (perfil.universidad.isNotEmpty) (Icons.school_outlined, 'Estudias en', perfil.universidad),
      (Icons.place_outlined, 'Estación', tramo == null ? 'Cualquiera' : '${tramo.nombre} · ${tramo.referencia}'),
      (Icons.schedule, 'Hora', perfil.franja == null ? 'Cualquiera' : cat.nombreDe(cat.franjas, perfil.franja!)),
      (iconoDe(perfil.actividad), 'Actividad', cat.nombreDe(cat.actividades, perfil.actividad)),
      (Icons.speed, 'Ritmo', cat.nombreDe(cat.ritmos, perfil.ritmo)),
      (Icons.home_outlined, 'Vives en', 'Comuna ${perfil.comuna}$barrios'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Para recomendarte parches', style: t.titleMedium)),
                TextButton(onPressed: onCambiar, child: const Text('Cambiar')),
              ],
            ),
            const SizedBox(height: 4),
            for (final f in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    IconoBurbuja(f.$1, color: col.tinta, fondo: col.suave, tamano: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$2, style: t.bodySmall),
                          Text(f.$3, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
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
