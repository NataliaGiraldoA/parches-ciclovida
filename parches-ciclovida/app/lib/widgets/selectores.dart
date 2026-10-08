import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'comunes.dart';
import 'diseno.dart';

class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.ayuda});

  final String texto;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: Theme.of(context).textTheme.titleMedium),
          if (ayuda != null) ...[
            const SizedBox(height: 2),
            Text(ayuda!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Estaciones de la CicloVida. Primero las de la comuna del joven.
class SelectorTramo extends StatelessWidget {
  const SelectorTramo({super.key, required this.catalogo, required this.valor, required this.onChanged, this.comuna});

  final Catalogo catalogo;
  final String? valor;
  final int? comuna;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tramos = [...catalogo.tramos]
      ..sort((a, b) {
        final ca = a.comuna == comuna ? 0 : 1;
        final cb = b.comuna == comuna ? 0 : 1;
        if (ca != cb) return ca.compareTo(cb);
        return a.nombre.compareTo(b.nombre);
      });
    return Column(
      children: [
        for (final t in tramos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Seleccionable(
              titulo: t.nombre,
              subtitulo: '${t.punto} · comuna ${t.comuna}${t.comuna == comuna ? ' · tu comuna' : ''}',
              seleccionado: valor == t.id,
              onTap: () => onChanged(t.id),
              icono: Icons.place_outlined,
              colorIcono: Cv.tealInk,
              fondoIcono: Cv.tealSoft,
            ),
          ),
      ],
    );
  }
}

/// Estación favorita en una lista desplegable, con la opción de no elegir ninguna.
class SelectorEstacion extends StatelessWidget {
  const SelectorEstacion({super.key, required this.catalogo, required this.valor, required this.onChanged, this.comuna});

  final Catalogo catalogo;
  final String? valor;
  final int? comuna;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tramos = [...catalogo.tramos]
      ..sort((a, b) {
        final ca = a.comuna == comuna ? 0 : 1;
        final cb = b.comuna == comuna ? 0 : 1;
        if (ca != cb) return ca.compareTo(cb);
        return a.nombre.compareTo(b.nombre);
      });
    final elegido = valor == null ? null : catalogo.tramo(valor!);
    final comunaEstacion = elegido == null ? null : catalogo.comuna(elegido.comuna);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: valor,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.place_outlined)),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Cualquiera')),
            for (final t in tramos)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text('${t.nombre}${t.comuna == comuna ? ' · tu comuna' : ''}'),
              ),
          ],
          onChanged: onChanged,
        ),
        // Ficha pequeña de la estación elegida: dónde queda y qué barrios tiene cerca.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: elegido == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Cv.verdeSoft, borderRadius: BorderRadius.circular(Cv.radioMd)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 16, color: Cv.verdeInk),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${elegido.punto} · ${elegido.referencia}',
                                style: const TextStyle(fontSize: 13, height: 1.35, color: Cv.verdeInk, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (comunaEstacion != null && comunaEstacion.barrios.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${comunaEstacion.nombre}: cerca de ${comunaEstacion.barriosResumen()}.',
                            style: const TextStyle(fontSize: 12.5, height: 1.35, color: Cv.verdeInk),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class SelectorActividad extends StatelessWidget {
  const SelectorActividad({super.key, required this.opciones, required this.valor, required this.onChanged});

  final List<Opcion> opciones;
  final String? valor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final o in opciones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Seleccionable(
              titulo: o.nombre,
              seleccionado: valor == o.id,
              onTap: () => onChanged(o.id),
              icono: iconoDe(o.id),
              colorIcono: coloresDe(o.id).tinta,
              fondoIcono: coloresDe(o.id).suave,
              colorSeleccion: coloresDe(o.id).tinta,
              fondoSeleccion: coloresDe(o.id).brisa,
            ),
          ),
      ],
    );
  }
}

class SelectorOpciones extends StatelessWidget {
  const SelectorOpciones({super.key, required this.opciones, required this.valor, required this.onChanged});

  final List<Opcion> opciones;
  final String? valor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final o in opciones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Seleccionable(
              titulo: o.nombre,
              subtitulo: o.detalle,
              seleccionado: valor == o.id,
              onTap: () => onChanged(o.id),
            ),
          ),
      ],
    );
  }
}

/// Opciones cortas en una fila (franja horaria, rango de edad).
class SelectorFila extends StatelessWidget {
  const SelectorFila({super.key, required this.opciones, required this.valor, required this.onChanged});

  final List<Opcion> opciones;
  final String? valor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < opciones.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Pastilla(
              texto: opciones[i].nombre,
              seleccionado: valor == opciones[i].id,
              onTap: () => onChanged(opciones[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.texto, required this.seleccionado, required this.onTap});

  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: seleccionado,
      button: true,
      child: Rebote(
        child: Material(
          color: seleccionado ? Cv.tealSoft : Cv.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Cv.radioMd),
            side: BorderSide(color: seleccionado ? Cv.tealInk : Cv.line, width: seleccionado ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Cv.radioMd),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w600,
                      color: seleccionado ? Cv.tealInk : Cv.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SelectorComuna extends StatelessWidget {
  const SelectorComuna({super.key, required this.comunas, required this.valor, required this.onChanged});

  final List<Comuna> comunas;
  final int? valor;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    Comuna? elegida;
    for (final c in comunas) {
      if (c.id == valor) elegida = c;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: valor,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Elige tu comuna', prefixIcon: Icon(Icons.home_outlined)),
          items: [
            for (final c in comunas) DropdownMenuItem<int>(value: c.id, child: Text(c.nombre)),
          ],
          onChanged: onChanged,
        ),
        // Al elegir, abajo salen en pequeño los barrios que cubre esa comuna.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: elegida == null || elegida.barrios.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PistaBarrios(comuna: elegida),
                ),
        ),
      ],
    );
  }
}

/// "Cubre barrios como El Refugio, San Fernando y El Lido, entre otros."
class PistaBarrios extends StatelessWidget {
  const PistaBarrios({super.key, required this.comuna, this.prefijo = 'Cubre barrios como'});

  final Comuna comuna;
  final String prefijo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Cv.tealSoft,
        borderRadius: BorderRadius.circular(Cv.radioMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.location_city, size: 16, color: Cv.tealInk),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$prefijo ${comuna.barriosResumen(maximo: 4)}.',
              style: const TextStyle(fontSize: 13, height: 1.35, color: Cv.tealInk, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
