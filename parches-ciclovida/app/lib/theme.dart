import 'package:flutter/material.dart';

/// Tokens del design system "Parches CicloVida".
/// Los cuatro colores salen de las letras V, I, D, A del logo; la tinta, del gris de "CICLO".
/// Cada color tiene cuatro tonos: `marca` para decorar (cinta, confeti, íconos grandes), `Ink` para
/// texto e íconos con significado y para fondos con texto blanco (contraste AA), `Soft` para chips
/// y sellos, y `brisa` para bloques grandes. La interfaz es siempre clara: los tonos oscuros solo
/// van en texto y detalles pequeños. No hay modo oscuro.
class Cv {
  /// Fondo de las pantallas: crema, el coral al 3,5 % sobre blanco.
  static const surface = Color(0xFFFFFAF7);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const line = Color(0xFFE3E4E8);

  /// Borde de controles (inputs, casillas): 3,6:1 sobre blanco.
  static const lineStrong = Color(0xFF85878E);
  static const ink = Color(0xFF1D1E22);
  static const inkMuted = Color(0xFF5E6068);

  static const rojo = Color(0xFFE4253F);
  static const coral = Color(0xFFF26B21);
  static const verde = Color(0xFF19A85B);
  static const teal = Color(0xFF0B9BC4);

  static const rojoInk = Color(0xFFB8162E);
  static const coralInk = Color(0xFFB0460B);
  static const verdeInk = Color(0xFF0B7A3F);
  static const tealInk = Color(0xFF06708F);

  static const rojoSoft = Color(0xFFFDE6E9);
  static const coralSoft = Color(0xFFFFEBDD);
  static const verdeSoft = Color(0xFFDDF5E7);
  static const tealSoft = Color(0xFFDBF2FA);

  /// Tintes muy suaves (5-7 %) para bloques de color grandes.
  static const brisaRojo = Color(0xFFFEF4F5);
  static const brisaCoral = Color(0xFFFEF5EF);
  static const brisaVerde = Color(0xFFF1FAF5);
  static const brisaTeal = Color(0xFFF0F9FB);

  static const cinta = [rojo, coral, verde, teal];

  /// La tinta al 20 %: sombras de íconos y texto sobre el mapa.
  static const velo = Color(0x331D1E22);

  /// Degradado de las acciones principales, en los tonos Ink (texto blanco AA en todo el recorrido).
  static const accion = [rojoInk, coralInk];

  /// Tipografía de títulos (Bricolage Grotesque, OFL). El cuerpo es Barlow.
  static const display = 'Bricolage';

  static const radioSm = 12.0;
  static const radioMd = 16.0;
  static const radioLg = 24.0;
  static const radioXl = 32.0;

  /// Ancho máximo del contenido de lectura (formularios, listas, tarjetas) y de pantallas amplias.
  static const anchoLectura = 640.0;
  static const anchoAmplio = 1040.0;

  /// Sombra suave para lo que flota sobre la página (tarjetas, barra de navegación).
  static const sombra = [
    BoxShadow(color: Color(0x141D1E22), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A1D1E22), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// Sombra más marcada para lo que está por encima de todo (diálogos, la celebración).
  static const sombraAlta = [
    BoxShadow(color: Color(0x1F1D1E22), blurRadius: 32, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0F1D1E22), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Sombra de las barras fijas de abajo (botón principal de un formulario, redactor del chat).
  static const sombraArriba = [
    BoxShadow(color: Color(0x141D1E22), blurRadius: 16, offset: Offset(0, -4)),
  ];

  /// Resplandor del color de una acción (botón central, ícono protagonista).
  static List<BoxShadow> brillo(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8)),
      ];
}

/// Cada actividad lleva uno de los cuatro colores del logo.
class ColoresActividad {
  const ColoresActividad(this.marca, this.tinta, this.suave, [this.brisa = Cv.surface]);

  /// Acento decorativo: puntos, bordes gruesos, la cinta. Nunca para texto.
  final Color marca;

  /// Texto o ícono sobre blanco o sobre [suave]; fondo para texto blanco.
  final Color tinta;

  /// Fondo de chips y sellos.
  final Color suave;

  /// Fondo de bloques grandes.
  final Color brisa;
}

ColoresActividad coloresDe(String actividad) {
  switch (actividad) {
    case 'bici':
      return const ColoresActividad(Cv.teal, Cv.tealInk, Cv.tealSoft, Cv.brisaTeal);
    case 'trotar':
      return const ColoresActividad(Cv.coral, Cv.coralInk, Cv.coralSoft, Cv.brisaCoral);
    case 'caminar':
      return const ColoresActividad(Cv.verde, Cv.verdeInk, Cv.verdeSoft, Cv.brisaVerde);
    case 'patines':
      return const ColoresActividad(Cv.rojo, Cv.rojoInk, Cv.rojoSoft, Cv.brisaRojo);
    default:
      return const ColoresActividad(Cv.lineStrong, Cv.ink, Cv.line, Cv.surface);
  }
}

IconData iconoDe(String actividad) {
  switch (actividad) {
    case 'bici':
      return Icons.directions_bike;
    case 'trotar':
      return Icons.directions_run;
    case 'caminar':
      return Icons.directions_walk;
    case 'patines':
      return Icons.roller_skating;
    default:
      return Icons.circle_outlined;
  }
}

/// La cinta de cuatro colores, como la pintura del carril de la CicloVida.
/// Con [llenos] funciona como barra de progreso: los tramos que faltan van en gris.
class Cinta extends StatelessWidget {
  const Cinta({super.key, this.alto = 6, this.llenos = 4, this.radio = 0});

  final double alto;
  final int llenos;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(
        height: alto,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  color: i < llenos ? Cv.cinta[i] : Cv.line,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fondo del botón principal: el degradado de acción. Deshabilitado, queda el gris del tema.
Widget _fondoAccion(BuildContext context, Set<WidgetState> estados, Widget? child) {
  if (estados.contains(WidgetState.disabled)) return child ?? const SizedBox.shrink();
  return Ink(
    decoration: const ShapeDecoration(shape: StadiumBorder(), gradient: LinearGradient(colors: Cv.accion)),
    child: child,
  );
}

Widget _sinDegradado(BuildContext context, Set<WidgetState> estados, Widget? child) => child ?? const SizedBox.shrink();

/// Botón lleno de un solo color, sin el degradado de acción: para acciones propias de una
/// sección o actividad (por ejemplo, "Unirme" en el color de la actividad). [fondo] debe ser un
/// tono Ink (o blanco con [texto] oscuro) para que el texto cumpla AA.
ButtonStyle botonDeColor(
  Color fondo, {
  Color texto = Colors.white,
  Size? minimo,
  EdgeInsetsGeometry? relleno,
}) {
  return FilledButton.styleFrom(
    backgroundColor: fondo,
    foregroundColor: texto,
    minimumSize: minimo,
    padding: relleno,
    backgroundBuilder: _sinDegradado,
  );
}

ThemeData temaParches() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Cv.tealInk,
    onPrimary: Colors.white,
    primaryContainer: Cv.tealSoft,
    onPrimaryContainer: Cv.tealInk,
    secondary: Cv.coralInk,
    onSecondary: Colors.white,
    secondaryContainer: Cv.coralSoft,
    onSecondaryContainer: Cv.coralInk,
    tertiary: Cv.verdeInk,
    onTertiary: Colors.white,
    tertiaryContainer: Cv.verdeSoft,
    onTertiaryContainer: Cv.verdeInk,
    error: Cv.rojoInk,
    onError: Colors.white,
    errorContainer: Cv.rojoSoft,
    onErrorContainer: Cv.rojoInk,
    surface: Cv.surfaceRaised,
    onSurface: Cv.ink,
    onSurfaceVariant: Cv.inkMuted,
    surfaceContainerLowest: Cv.surfaceRaised,
    surfaceContainerLow: Cv.surface,
    surfaceContainer: Cv.surface,
    surfaceContainerHigh: Cv.surface,
    surfaceContainerHighest: Cv.surface,
    outline: Cv.lineStrong,
    outlineVariant: Cv.line,
    inverseSurface: Cv.ink,
    onInverseSurface: Colors.white,
    shadow: Cv.ink,
    scrim: Cv.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Barlow',
    scaffoldBackgroundColor: Cv.surface,
  );

  const boton = TextStyle(fontFamily: 'Barlow', fontSize: 17, fontWeight: FontWeight.w700);
  const pastilla = StadiumBorder();

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: Cv.ink, displayColor: Cv.ink)
        .merge(const TextTheme(
          displayLarge: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w800, fontSize: 64, height: 0.95, letterSpacing: -1.6),
          displayMedium: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w800, fontSize: 52, height: 0.95, letterSpacing: -1.2),
          displaySmall: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w800, fontSize: 42, height: 0.98, letterSpacing: -1),
          headlineLarge: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w800, fontSize: 34, height: 1.02, letterSpacing: -0.8),
          headlineMedium: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w800, fontSize: 28, height: 1.05, letterSpacing: -0.5),
          headlineSmall: TextStyle(fontFamily: Cv.display, fontWeight: FontWeight.w700, fontSize: 22, height: 1.12, letterSpacing: -0.3),
          titleLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, height: 1.25),
          titleMedium: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, height: 1.3),
          titleSmall: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3),
          bodyLarge: TextStyle(fontSize: 17, height: 1.45),
          bodyMedium: TextStyle(fontSize: 15, height: 1.45),
          bodySmall: TextStyle(fontSize: 13, height: 1.4, color: Cv.inkMuted),
          labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4),
        )),
    // Botón principal: píldora con el degradado de acción. Para un solo color, usar botonDeColor().
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: pastilla,
        textStyle: boton,
        backgroundColor: Cv.rojoInk,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Cv.line,
        disabledForegroundColor: Cv.inkMuted,
        elevation: 0,
        backgroundBuilder: _fondoAccion,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: pastilla,
        textStyle: boton,
        backgroundColor: Cv.surfaceRaised,
        foregroundColor: Cv.ink,
        side: const BorderSide(color: Cv.lineStrong, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Cv.tealInk,
        shape: pastilla,
        textStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Cv.ink),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Cv.tealInk,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w700),
    ),
    // Tarjetas blancas con sombra suave: se despegan del fondo crema.
    cardTheme: const CardThemeData(
      color: Cv.surfaceRaised,
      elevation: 2,
      shadowColor: Color(0x2E1D1E22),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Cv.radioLg))),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Cv.surface,
      foregroundColor: Cv.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: Cv.display, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Cv.ink),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(side: BorderSide(color: Cv.line)),
      backgroundColor: Cv.surfaceRaised,
      selectedColor: Cv.tealSoft,
      labelStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 15, fontWeight: FontWeight.w600, color: Cv.ink),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Cv.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Cv.radioMd),
        borderSide: const BorderSide(color: Cv.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Cv.radioMd),
        borderSide: const BorderSide(color: Cv.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Cv.radioMd),
        borderSide: const BorderSide(color: Cv.tealInk, width: 2),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Cv.tealInk, linearTrackColor: Cv.line),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Cv.verdeInk : null),
      side: const BorderSide(color: Cv.lineStrong, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Cv.lineStrong),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Cv.verdeInk : Cv.line),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Cv.verdeInk : Cv.lineStrong),
    ),
    dividerTheme: const DividerThemeData(color: Cv.line, thickness: 1, space: 24),
    listTileTheme: const ListTileThemeData(iconColor: Cv.inkMuted),
    dialogTheme: const DialogThemeData(
      backgroundColor: Cv.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Cv.radioXl))),
      titleTextStyle: TextStyle(fontFamily: Cv.display, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1, color: Cv.ink),
      contentTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 16, height: 1.45, color: Cv.ink),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Cv.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Cv.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Cv.radioXl))),
    ),
    // Avisos claros y flotantes, con sombra: nada de barras negras.
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Cv.surfaceRaised,
      elevation: 8,
      actionTextColor: Cv.tealInk,
      shape: StadiumBorder(side: BorderSide(color: Cv.line)),
      contentTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 15, fontWeight: FontWeight.w600, color: Cv.ink),
    ),
  );
}
