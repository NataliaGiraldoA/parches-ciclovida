import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../sesion.dart';
import '../theme.dart';
import '../widgets/comunes.dart';
import '../widgets/diseno.dart';

/// Aviso de privacidad completo (Ley 1581 de 2012). El texto vive en el backend.
class AvisoPrivacidadScreen extends StatefulWidget {
  const AvisoPrivacidadScreen({super.key});

  @override
  State<AvisoPrivacidadScreen> createState() => _AvisoPrivacidadScreenState();
}

class _AvisoPrivacidadScreenState extends State<AvisoPrivacidadScreen> {
  AvisoPrivacidad? _aviso;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (_error != null) setState(() => _error = null);
    try {
      final a = await Sesion.actual.api.avisoPrivacidad();
      if (!mounted) return;
      setState(() => _aviso = a);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = _aviso;
    return Scaffold(
      appBar: AppBar(title: const Text('Aviso de privacidad')),
      body: SafeArea(
        child: ListView(
          padding: rellenoAncho(context, arriba: 4, abajo: 32),
          children: [
            if (_error != null) TarjetaError(mensaje: _error!, reintentar: _cargar),
            if (a == null && _error == null) ...[
              for (final alto in const [96.0, 140.0, 120.0, 160.0]) ...[
                const SizedBox(height: 14),
                Esqueleto(alto: alto),
              ],
            ],
            if (a != null) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  IconoBurbuja(Icons.shield_outlined, color: Cv.tealInk, fondo: Cv.tealSoft, tamano: 48),
                  SizedBox(width: 12),
                  Expanded(child: Rotulo('Ley 1581 de 2012')),
                ],
              ),
              for (var i = 0; i < a.secciones.length; i++) ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.secciones[i].titulo, style: t.headlineSmall),
                        const SizedBox(height: 6),
                        Text(a.secciones[i].texto, style: t.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('Versión ${a.version}', textAlign: TextAlign.center, style: t.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
