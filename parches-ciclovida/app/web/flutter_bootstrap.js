{{flutter_js}}
{{flutter_build_config}}

// Sin service worker: guardaba la versión anterior de la app y, después de cada despliegue, la
// gente seguía viendo la vieja. El servidor ya pide no cachear (Cache-Control: no-cache).
_flutter.loader.load({});
