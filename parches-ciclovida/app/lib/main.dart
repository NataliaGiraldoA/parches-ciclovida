import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'notificaciones.dart';
import 'screens/bienvenida.dart';
import 'screens/principal.dart';
import 'sesion.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notificaciones.iniciar();
  final sesion = await Sesion.cargar();
  runApp(ParchesApp(registrado: sesion.registrado));
}

class ParchesApp extends StatelessWidget {
  const ParchesApp({super.key, required this.registrado});

  final bool registrado;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parches CicloVida',
      debugShowCheckedModeBanner: false,
      theme: temaParches(),
      // En el navegador, Flutter solo deja arrastrar las listas con el dedo: con esto "jalar para
      // actualizar" y las filas de chips también funcionan con el mouse al probar en la web.
      scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: registrado ? const PrincipalScreen() : const BienvenidaScreen(),
    );
  }
}
