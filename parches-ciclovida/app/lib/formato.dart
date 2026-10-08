const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "2026-09-27" -> "domingo 27 de septiembre"
String fechaLarga(String iso) {
  final d = DateTime.parse(iso);
  return '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}';
}

/// "2026-09-27" -> "27 de septiembre"
String fechaCorta(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day} de ${_meses[d.month - 1]}';
}

/// "13:00" -> "1:00 p. m."
String horaBonita(String hhmm) {
  final partes = hhmm.split(':');
  final h = int.parse(partes[0]);
  final m = partes.length > 1 ? partes[1] : '00';
  final sufijo = h < 12 ? 'a. m.' : 'p. m.';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $sufijo';
}

String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
