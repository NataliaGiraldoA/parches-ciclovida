import 'package:flutter/material.dart';

import '../theme.dart';
import 'diseno.dart';

/// Opción que se toca para elegir. Elegida, se tiñe del color de la sección y marca el chulito.
class Seleccionable extends StatelessWidget {
  const Seleccionable({
    super.key,
    required this.titulo,
    required this.seleccionado,
    required this.onTap,
    this.subtitulo,
    this.icono,
    this.colorIcono,
    this.fondoIcono,
    this.colorSeleccion = Cv.tealInk,
    this.fondoSeleccion = Cv.brisaTeal,
  });

  final String titulo;
  final String? subtitulo;
  final bool seleccionado;
  final VoidCallback onTap;
  final IconData? icono;
  final Color? colorIcono;
  final Color? fondoIcono;

  /// Borde y chulito cuando está elegida (un tono Ink).
  final Color colorSeleccion;

  /// Fondo cuando está elegida (un tono brisa o Soft).
  final Color fondoSeleccion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: seleccionado,
      button: true,
      child: Rebote(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: seleccionado ? fondoSeleccion : Cv.surfaceRaised,
            borderRadius: BorderRadius.circular(Cv.radioMd),
            border: Border.all(color: seleccionado ? colorSeleccion : Cv.line, width: seleccionado ? 2 : 1),
            boxShadow: seleccionado ? null : Cv.sombra,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Cv.radioMd),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    if (icono != null) ...[
                      IconoBurbuja(icono!, color: colorIcono ?? Cv.ink, fondo: fondoIcono ?? Cv.surface, tamano: 42),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Cv.ink)),
                          if (subtitulo != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitulo!, style: const TextStyle(fontSize: 13, color: Cv.inkMuted, height: 1.3)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      seleccionado ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: seleccionado ? colorSeleccion : Cv.lineStrong,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dos botones grandes "Sí" / "No". Sin [colorSeleccion], el sí se tiñe de verde y el no de coral;
/// con él, los dos toman el color de la pregunta.
class SiNo extends StatelessWidget {
  const SiNo({
    super.key,
    required this.valor,
    required this.onChanged,
    this.si = 'Sí',
    this.no = 'No',
    this.colorSeleccion,
    this.fondoSeleccion,
  });

  final bool? valor;
  final ValueChanged<bool> onChanged;
  final String si;
  final String no;

  /// Un tono Ink y su brisa.
  final Color? colorSeleccion;
  final Color? fondoSeleccion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Seleccionable(
            titulo: si,
            seleccionado: valor == true,
            onTap: () => onChanged(true),
            colorSeleccion: colorSeleccion ?? Cv.verdeInk,
            fondoSeleccion: fondoSeleccion ?? Cv.brisaVerde,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Seleccionable(
            titulo: no,
            seleccionado: valor == false,
            onTap: () => onChanged(false),
            colorSeleccion: colorSeleccion ?? Cv.coralInk,
            fondoSeleccion: fondoSeleccion ?? Cv.brisaCoral,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta para los estados sin parche asignado (en pausa, en revisión…).
class TarjetaEstado extends StatelessWidget {
  const TarjetaEstado({
    super.key,
    required this.icono,
    required this.titulo,
    required this.texto,
    this.accion,
    this.color = Cv.tealInk,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final Widget? accion;

  /// Un tono Ink: colorea el ícono, y su tinte suave el fondo del ícono y de la tarjeta.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.07), Cv.surfaceRaised],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconoBurbuja(icono, color: color, fondo: color.withValues(alpha: 0.12), tamano: 56),
              ),
              const SizedBox(height: 14),
              Text(titulo, style: t.headlineSmall),
              const SizedBox(height: 6),
              Text(texto, style: t.bodyMedium?.copyWith(color: Cv.inkMuted)),
              if (accion != null) ...[const SizedBox(height: 18), accion!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado de cada integrante: siempre con palabra, nunca solo color.
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado(this.estado, {super.key});

  final String estado;

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case 'confirmado':
        return const Sello('Va', fondo: Cv.verdeSoft, color: Cv.verdeInk, icono: Icons.check);
      case 'declinado':
        return const Sello('No va', fondo: Cv.rojoSoft, color: Cv.rojoInk, icono: Icons.close);
      default:
        return const Sello('Por confirmar', fondo: Cv.line, color: Cv.inkMuted, icono: Icons.schedule);
    }
  }
}

/// Error de conexión con personalidad y salida: reintentar o cambiar el servidor.
class TarjetaError extends StatelessWidget {
  const TarjetaError({super.key, required this.mensaje, required this.reintentar, this.cambiarServidor});

  final String mensaje;
  final VoidCallback reintentar;
  final VoidCallback? cambiarServidor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: EstadoVacio(
          emoji: '📡',
          fondo: Cv.brisaRojo,
          titulo: 'No pudimos conectarnos',
          texto: mensaje,
          accion: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: reintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              if (cambiarServidor != null)
                TextButton(onPressed: cambiarServidor, child: const Text('Cambiar dirección del servidor')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pie que aclara qué es la app. Sin marca de la Alcaldía (recomendación del mentor).
class PieInstitucional extends StatelessWidget {
  const PieInstitucional({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Prototipo del equipo Dedsec para el reto CicloVida · Hackathon Smart City Expo Cali 2026. '
      'No es un canal oficial de la Alcaldía de Cali.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Cv.inkMuted),
    );
  }
}

Future<void> dialogoServidor(BuildContext context, {required String actual, required Future<void> Function(String) guardar}) async {
  final ctrl = TextEditingController(text: actual);
  final nueva = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Dirección del servidor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Es la IP del computador donde corre el backend, por ejemplo http://192.168.1.20:8000'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'http://192.168.1.20:8000', prefixIcon: Icon(Icons.dns_outlined)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Guardar')),
      ],
    ),
  );
  // El controlador no se descarta aquí: el diálogo todavía se está cerrando con animación.
  if (nueva != null && nueva.trim().isNotEmpty) {
    await guardar(nueva);
  }
}
