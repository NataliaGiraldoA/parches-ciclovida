import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parches_ciclovida/formato.dart';
import 'package:parches_ciclovida/models.dart';
import 'package:parches_ciclovida/screens/bienvenida.dart';
import 'package:parches_ciclovida/screens/encuesta.dart';
import 'package:parches_ciclovida/theme.dart';
import 'package:parches_ciclovida/widgets/boleta.dart';
import 'package:parches_ciclovida/widgets/parche_card.dart';

const _tramo = {'id': 'panamericana', 'nombre': 'Panamericana', 'comuna': 19};

/// Respuesta real de GET /api/yo/parche después del sábado (copiada del backend).
const _estadoJson = <String, dynamic>{
  'jornada': {'fecha': '2026-09-27', 'estado': 'emparejada', 'inicio': '08:00', 'fin': '13:00'},
  'estado': 'asignado',
  'mi_respuesta': 'pendiente',
  'ajustes': ['franja'],
  'tarde': false,
  'salida': {
    'id': 3,
    'nombre': 'Parche Samán',
    'tramo': _tramo,
    'punto_encuentro': 'Calle 9 con Carrera 37A',
    'referencia': 'Canchas Panamericanas',
    'hora_encuentro': '08:00',
    'hora_nombre': '8:00 a. m.',
    'actividad': 'bici',
    'actividad_nombre': 'Bici',
    'inscritos': 3,
    'universidades': 2,
    'ritmo_nombre': 'Moderado',
    'es_mio': true,
    'para_ti': true,
  },
  'grupo': {
    'id': 7,
    'nombre': 'Parche Samán',
    'tramo': _tramo,
    'punto_encuentro': 'Calle 9 con Carrera 37A',
    'referencia': 'Canchas Panamericanas',
    'hora_encuentro': '08:00',
    'hora_nombre': '8:00 a. m.',
    'actividad': 'bici',
    'actividad_nombre': 'Bici',
    'ritmo': 'moderado',
    'ritmo_nombre': 'Moderado',
    'miembros': [
      {'ref': 31, 'nombre': 'Ana', 'universidad': 'USB Cali', 'actividad': 'bici', 'estado': 'pendiente', 'soy_yo': true},
      {'ref': 32, 'nombre': 'Luis', 'universidad': 'Univalle', 'actividad': 'bici', 'estado': 'confirmado', 'soy_yo': false},
      {'ref': 33, 'nombre': 'Sara', 'universidad': 'Icesi', 'actividad': 'patines', 'estado': 'declinado', 'soy_yo': false},
    ],
    'confirmados': 1,
  },
  'encuesta': null,
};

Widget _envolver(Widget hijo) => MaterialApp(theme: temaParches(), home: Scaffold(body: hijo));

void main() {
  test('formato de fechas y horas en español', () {
    expect(fechaLarga('2026-09-27'), 'domingo 27 de septiembre');
    expect(horaBonita('13:00'), '1:00 p. m.');
    expect(horaBonita('08:00'), '8:00 a. m.');
  });

  test('lee el estado del parche que manda el backend', () {
    final e = EstadoParche.fromJson(_estadoJson);
    expect(e.estado, 'asignado');
    expect(e.salida!.inscritos, 3);
    expect(e.grupo!.miembros, hasLength(3));
    expect(e.grupo!.miembros.first.soyYo, isTrue);
    expect(e.grupo!.miembros[1].universidad, 'Univalle');
    expect(e.ajustes, ['franja']);
    expect(e.encuestaPendiente, isFalse);
  });

  testWidgets('la bienvenida invita a crear el perfil', (tester) async {
    // Pantalla de prueba más alta: el contenido no cabe en el viewport por
    // defecto (800x600) y el ListView no construye lo que queda fuera.
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: temaParches(), home: const BienvenidaScreen()));
    expect(find.text('sal en parche'), findsOneWidget);
    expect(find.text('Crear mi perfil'), findsOneWidget);
  });

  testWidgets('la boleta muestra la hora, la gente y se puede unir', (tester) async {
    final json = Map<String, dynamic>.from(_estadoJson['salida'] as Map)
      ..['es_mio'] = false
      ..['inscritos'] = 12;
    var unido = false;
    await tester.pumpWidget(_envolver(SingleChildScrollView(
      child: BoletaParche(parche: ParcheOpcion.fromJson(json), onUnirme: () => unido = true),
    )));
    expect(find.text('8:00'), findsOneWidget);
    expect(find.text('Para ti'), findsOneWidget);
    expect(find.textContaining('12 estudiantes van de 2 universidades'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    await tester.tap(find.text('Unirme'));
    expect(unido, isTrue);
  });

  testWidgets('la tarjeta del grupo muestra punto, hora, ajuste y botón de reporte', (tester) async {
    final e = EstadoParche.fromJson(_estadoJson);
    bool? respuesta;
    var reportes = 0;
    var cambios = 0;
    await tester.pumpWidget(_envolver(SingleChildScrollView(
      child: ParcheCard(
        grupo: e.grupo!,
        miRespuesta: e.miRespuesta,
        ajustes: e.ajustes,
        ocupado: false,
        onResponder: (va) => respuesta = va,
        onReportar: () => reportes++,
        onCambiar: () => cambios++,
      ),
    )));
    expect(find.text('Parche Samán'), findsOneWidget);
    expect(find.text('Estación Panamericana'), findsOneWidget);
    expect(find.textContaining('no alcanzó a 3 personas'), findsOneWidget);
    expect(find.text('Ana (tú)'), findsOneWidget);
    expect(find.text('Univalle'), findsOneWidget);
    expect(find.text('No va'), findsOneWidget);

    await tester.ensureVisible(find.text('Confirmo, voy'));
    await tester.tap(find.text('Confirmo, voy'));
    expect(respuesta, isTrue);

    await tester.ensureVisible(find.text('Cambiar de parche'));
    await tester.tap(find.text('Cambiar de parche'));
    expect(cambios, 1);

    await tester.ensureVisible(find.text('Reportar un problema'));
    await tester.tap(find.text('Reportar un problema'));
    expect(reportes, 1);
  });

  testWidgets('la escala de bienestar se puede elegir', (tester) async {
    int? elegido;
    await tester.pumpWidget(_envolver(EscalaBienestar(valor: null, onChanged: (v) => elegido = v)));
    await tester.tap(find.text('4'));
    expect(elegido, 4);
    expect(find.text('Muy bien'), findsOneWidget);
  });
}
