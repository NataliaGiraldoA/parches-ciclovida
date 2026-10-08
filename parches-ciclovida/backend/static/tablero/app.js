/* Tablero Parches CicloVida: solo lee /api/tablero/*, que ya viene agregado y anonimizado. */
(() => {
  const $ = (s) => document.querySelector(s);
  const css = (v) => getComputedStyle(document.documentElement).getPropertyValue(v).trim();
  const fmt = new Intl.NumberFormat('es-CO');
  const NIVEL = { armado: 'K-means', juntado: 'K-means con gente de otro parche' };
  const ESTADO = {
    finalizada: 'Jornada terminada',
    emparejada: 'Grupos armados, falta el domingo',
    inscripcion: 'Parches abiertos para unirse',
  };
  const CARAS = ['Muy mal', 'Mal', 'Regular', 'Bien', 'Muy bien'];

  let datos = null;
  let grafTendencia = null;
  let grafBase = null;
  let grafRetorno = null;
  let kpisPrevios = null;
  let ultimaOk = null;
  let mapa = null;
  let capaMapa = null;

  const fechaLarga = (f) => new Date(f + 'T12:00:00').toLocaleDateString('es-CO', { weekday: 'long', day: 'numeric', month: 'long' });
  const fechaCorta = (f) => new Date(f + 'T12:00:00').toLocaleDateString('es-CO', { day: 'numeric', month: 'short' });
  const ND = 's. d.'; // sin dato
  const pct = (v) => (v == null ? ND : `${fmt.format(v)} %`);
  const conteo = (c) => (c.suprimido ? `<${datos.anonimato.k_conteo}` : fmt.format(c.valor));
  const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));

  // Servido por el backend, la API está en el mismo sitio; desplegado aparte (Render), config.js
  // trae la dirección del backend.
  const API = String(window.PARCHES_API || '').replace(/\/+$/, '');

  async function getJSON(url) {
    const r = await fetch(API + url);
    if (!r.ok) throw new Error(`${url}: ${r.status}`);
    return r.json();
  }

  async function cargarJornadas() {
    const lista = await getJSON('/api/tablero/jornadas');
    const sel = $('#jornada');
    const actual = sel.value;
    sel.innerHTML = lista.map((j) => `<option value="${j.fecha}">${fechaLarga(j.fecha)}</option>`).join('');
    const porDefecto = (lista.find((j) => j.estado === 'finalizada') || lista[0] || {}).fecha;
    sel.value = actual && lista.some((j) => j.fecha === actual) ? actual : porDefecto;
  }

  function marcarVivo(ok) {
    const el = $('#vivo');
    el.classList.toggle('sin-conexion', !ok);
    if (ok) ultimaOk = new Date();
    el.firstElementChild.nextSibling.textContent = ok ? 'En vivo ' : 'Sin conexión con la app ';
    $('#vivo-hora').textContent = ultimaOk ? `· ${ultimaOk.toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}` : '';
  }

  async function cargarResumen() {
    const fecha = $('#jornada').value;
    datos = await getJSON(`/api/tablero/resumen${fecha ? `?fecha=${fecha}` : ''}`);
    pintar();
  }

  function pintar() {
    $('#aviso-sintetico').hidden = !datos.datos_sinteticos;
    $('#estado-jornada').textContent = ESTADO[datos.estado] || datos.estado;
    $('#nota-privacidad').textContent =
      `Conteos menores a ${datos.anonimato.k_conteo} se muestran como <${datos.anonimato.k_conteo}. ` +
      `Promedios con menos de ${datos.anonimato.k_promedio} respuestas se ocultan.`;
    pintarContexto();
    pintarKpis();
    pintarLecturas();
    pintarReto();
    pintarHabito();
    pintarEmbudo();
    pintarTendencia();
    pintarComunas();
    pintarMapa();
    pintarBienestar();
    pintarGrupos();
  }

  function pintarContexto() {
    const c = window.PARCHES_CONTEXTO;
    const caja = $('#contexto');
    if (!c) return;
    const cifras = (c.cifras || []).filter((x) => x.cifra && x.fuente);
    caja.hidden = false;
    caja.innerHTML = `
      <p class="una-linea">${esc(c.unaLinea || '')}</p>
      ${cifras.length ? `<div class="cifras">${cifras.map((x) => `
        <div class="cifra"><b>${esc(x.cifra)}</b><span>${esc(x.texto)}</span><small>Fuente: ${esc(x.fuente)}</small></div>`).join('')}</div>` : ''}
      <div class="trio">
        ${c.problema ? `<div><h2>El problema</h2><p>${esc(c.problema)}</p></div>` : ''}
        ${(c.valor || []).length ? `<div><h2>Valor público</h2><ul>${c.valor.map((v) => `<li>${esc(v)}</li>`).join('')}</ul></div>` : ''}
      </div>`;
  }

  function pintarLecturas() {
    const l = datos.lecturas || [];
    $('#card-lecturas').hidden = !l.length;
    $('#lecturas').innerHTML = l.map((x) => `<li><span>${esc(x)}</span></li>`).join('');
  }

  function pintarReto() {
    document.querySelectorAll('.kmin').forEach((e) => { e.textContent = datos.anonimato.k_conteo; });

    // reparto modal: una barra partida (sobre ruedas / a pie) y el detalle por actividad
    const modal = datos.reparto_modal;
    const suma = (fam) => modal.filter((m) => m.familia === fam).reduce((s, m) => s + (m.n.valor || 0), 0);
    const ruedas = suma('ruedas');
    const aPie = suma('a_pie');
    const total = ruedas + aPie;
    const p = (v) => (total ? Math.round((100 * v) / total) : 0);
    $('#familia').innerHTML = total
      ? `<div class="ruedas" style="flex:${ruedas || 0.001}" title="Sobre ruedas: ${fmt.format(ruedas)}">Sobre ruedas ${p(ruedas)} %</div>` +
        `<div class="a-pie" style="flex:${aPie || 0.001}" title="A pie: ${fmt.format(aPie)}">A pie ${p(aPie)} %</div>`
      : '';
    const maxM = Math.max(1, ...modal.map((m) => m.n.valor || 0));
    $('#modal').innerHTML = modal.map((m) => fila(
      m.nombre, m.n.valor, maxM, conteo(m.n), { titulo: `${m.nombre}: ${conteo(m.n)}` },
    )).join('');

    const od = datos.origen_destino;
    const maxO = Math.max(1, ...od.pares.map((x) => x.n));
    $('#od').innerHTML = od.pares.length
      ? od.pares.map((x) => fila(`Comuna ${x.comuna} → ${x.estacion}`, x.n, maxO, fmt.format(x.n))).join('')
      : '<p class="sub">Todavía no hay pares con suficientes jóvenes.</p>';
    $('#od-ocultos').textContent = od.ocultos ? `${fmt.format(od.ocultos)} pares con menos jóvenes no se muestran, para proteger el anonimato.` : '';

    const unis = datos.universidades;
    const maxU = Math.max(1, ...unis.map((u) => u.n.valor || 0));
    $('#unis').innerHTML = unis.map((u) => fila(u.nombre, u.n.valor, maxU, conteo(u.n))).join('');
    const t = datos.tejido;
    const pa = datos.participacion;
    $('#tejido').innerHTML = [
      t.mixtos_pct != null ? `<div><b>${pct(t.mixtos_pct)}</b><span>de los grupos mezcla 2 o más universidades</span></div>` : '',
      pa.primera_vez_pct != null ? `<div><b>${pct(pa.primera_vez_pct)}</b><span>nunca había ido a la CicloVida</span></div>` : '',
    ].join('');

    pintarBase();
  }

  function pintarHabito() {
    const h = datos.habito;
    const serie = h.serie;
    const c1 = css('--data-1');
    const c2 = css('--data-2');
    const linea = (label, key, color) => ({
      label, data: serie.map((x) => x[key]), borderColor: color, backgroundColor: color, borderWidth: 2,
      pointRadius: 4, pointHoverRadius: 6, pointBorderColor: '#ffffff', pointBorderWidth: 2, pointBackgroundColor: color,
      tension: 0, spanGaps: true,
    });
    const cfg = {
      type: 'line',
      data: {
        labels: serie.map((x) => fechaCorta(x.fecha)),
        datasets: [linea('Volvieron al domingo siguiente', 'retorno_pct', c1), linea('Con 3 o más domingos seguidos', 'habito_pct', c2)],
      },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top', align: 'start', labels: { boxWidth: 12, boxHeight: 3, color: css('--ink'), font: { family: 'Barlow', size: 13 } } },
          tooltip: {
            backgroundColor: '#1e1f23', padding: 10, titleFont: { family: 'Barlow', weight: '600' }, bodyFont: { family: 'Barlow' },
            callbacks: {
              title: (items) => fechaLarga(serie[items[0].dataIndex].fecha),
              label: (it) => ` ${it.dataset.label}: ${pct(it.parsed.y)}`,
              afterBody: (items) => {
                const x = serie[items[0].dataIndex];
                return [`${fmt.format(x.asistentes)} fueron`, `${fmt.format(x.regresaron)} regresaron tras faltar`];
              },
            },
          },
        },
        scales: {
          y: { min: 0, max: 100, ticks: { stepSize: 25, callback: (v) => `${v} %`, color: css('--ink-muted'), font: { family: 'Barlow' } }, grid: { color: '#ecece8' }, border: { display: false } },
          x: { ticks: { color: css('--ink-muted'), font: { family: 'Barlow' } }, grid: { display: false }, border: { color: '#d6d6d1' } },
        },
      },
    };
    if (grafRetorno) grafRetorno.destroy();
    grafRetorno = new Chart($('#retorno'), cfg);

    const maxR = Math.max(1, ...h.rachas.map((r) => r.n.valor || 0));
    $('#rachas').innerHTML = h.rachas.map((r) => fila(
      r.mas ? '4 o más' : `${r.domingos} ${r.domingos === 1 ? 'domingo' : 'domingos'}`, r.n.valor, maxR, conteo(r.n),
    )).join('');
    const a = h.actual;
    $('#habito-mini').innerHTML = a ? [
      a.retorno_pct != null ? `<div><b>${pct(a.retorno_pct)}</b><span>volvió al domingo siguiente</span></div>` : '',
      `<div><b>${fmt.format(a.regresaron)}</b><span>regresaron después de faltar</span></div>`,
    ].join('') : '';

    $('#escenarios').innerHTML = datos.escenarios.length
      ? datos.escenarios.map((e) => `
        <div class="escenario">
          <span class="area">${esc(e.area)}</span>
          <p class="mide"><small>El tablero mide</small>${esc(e.mide)}</p>
          <p class="decide"><small>Se podría</small>${esc(e.decide)}</p>
        </div>`).join('')
      : '<p class="sub">Los escenarios aparecen cuando hay jornadas terminadas.</p>';
  }

  function pintarBase() {
    const b = datos.tendencia;
    const c1 = css('--data-1');
    const c2 = css('--data-2');
    const cfg = {
      type: 'bar',
      data: {
        labels: b.map((x) => fechaCorta(x.fecha)),
        datasets: [
          { label: 'Recurrentes', data: b.map((x) => x.recurrentes), backgroundColor: c1, borderColor: '#ffffff', borderWidth: 2, borderSkipped: false, borderRadius: 4, maxBarThickness: 64 },
          { label: 'Nuevos', data: b.map((x) => x.nuevos), backgroundColor: c2, borderColor: '#ffffff', borderWidth: 2, borderSkipped: false, borderRadius: 4, maxBarThickness: 64 },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: {
          legend: { position: 'top', align: 'start', labels: { boxWidth: 12, boxHeight: 12, color: css('--ink'), font: { family: 'Barlow', size: 13 } } },
          tooltip: {
            backgroundColor: '#1e1f23', padding: 10, titleFont: { family: 'Barlow', weight: '600' }, bodyFont: { family: 'Barlow' },
            callbacks: {
              title: (items) => fechaLarga(b[items[0].dataIndex].fecha),
              footer: (items) => `Total con parche: ${fmt.format(items.reduce((s, i) => s + i.parsed.y, 0))}`,
            },
          },
        },
        scales: {
          x: { stacked: true, grid: { display: false }, border: { color: '#d6d6d1' }, ticks: { color: css('--ink-muted'), font: { family: 'Barlow' } } },
          y: { stacked: true, beginAtZero: true, grid: { color: '#ecece8' }, border: { display: false }, ticks: { color: css('--ink-muted'), font: { family: 'Barlow' }, callback: (v) => fmt.format(v) } },
        },
      },
    };
    if (grafBase) grafBase.destroy();
    grafBase = new Chart($('#base'), cfg);
  }

  function pintarKpis() {
    const k = datos.kpis;
    const fueron = datos.embudo.find((e) => e.paso === 'Fueron').valor;
    const sinEncuesta = datos.estado !== 'finalizada';
    const nota = sinEncuesta ? 'La encuesta abre al terminar la jornada' : `${fmt.format(k.respuestas)} respuestas`;
    // cambio frente a la jornada anterior que ya terminó
    const i = datos.tendencia.findIndex((x) => x.fecha === datos.fecha);
    const antes = i > 0 ? datos.tendencia[i - 1] : null;
    const ahora = i >= 0 ? datos.tendencia[i] : null;
    const dif = (clave, unidad = 'pts') => {
      if (!antes || !ahora || antes[clave] == null || ahora[clave] == null) return '';
      const d = Math.round((ahora[clave] - antes[clave]) * 10) / 10;
      if (d === 0) return `<div class="dif">= que el ${fechaCorta(antes.fecha)}</div>`;
      return `<div class="dif ${d > 0 ? 'sube' : 'baja'}">${d > 0 ? '▲' : '▼'} ${String(Math.abs(d)).replace('.', ',')} ${unidad} vs. ${fechaCorta(antes.fecha)}</div>`;
    };
    const tiles = [
      { hero: true, lbl: 'Jóvenes que fueron con su parche', val: sinEncuesta ? ND : fmt.format(fueron), det: sinEncuesta ? nota : `de ${fmt.format(k.emparejados)} que tuvieron parche` },
      { lbl: 'Parches formados', val: fmt.format(k.parches), det: `${fmt.format(k.emparejados)} jóvenes de ${fmt.format(k.inscritos)} inscritos` },
      { lbl: 'Confirmaron el sábado', val: pct(k.confirmacion_pct), det: 'de quienes tuvieron parche', extra: dif('confirmacion_pct') },
      { lbl: 'Fueron', val: pct(k.asistencia_pct), det: nota, extra: dif('asistencia_pct') },
      { lbl: 'Volverían', val: pct(k.volverian_pct), det: nota, extra: dif('volverian_pct') },
      { lbl: 'Bienestar promedio', val: k.bienestar_promedio == null ? ND : String(k.bienestar_promedio).replace('.', ','), det: 'sobre 5 · pregunta opcional', extra: dif('bienestar_promedio', '') },
      { lbl: 'Reportes de seguridad', val: fmt.format(k.reportes), det: 'los revisa moderación' },
    ];
    const previos = kpisPrevios;
    $('#kpis').innerHTML = tiles.map((x) => `
      <div class="kpi${x.hero ? ' hero' : ''}">
        <div class="lbl">${x.lbl}</div>
        <div class="val">${x.val}</div>
        ${x.extra || ''}
        <div class="det">${x.det}</div>
      </div>`).join('');
    // lo que cambió desde la consulta anterior (por ejemplo, alguien se registró en la app) destella
    const valores = tiles.map((x) => `${datos.fecha}|${x.val}`);
    if (previos && previos.length === valores.length) {
      document.querySelectorAll('#kpis .kpi').forEach((el, i) => {
        if (previos[i] !== valores[i] && previos[i].split('|')[0] === datos.fecha) el.classList.add('cambio');
      });
    }
    kpisPrevios = valores;
  }

  function fila(nombre, valor, maximo, etiqueta, { base = null, titulo = '' } = {}) {
    const w = (v) => (maximo ? Math.max(0, (100 * v) / maximo) : 0);
    return `<div class="fila${valor == null && base == null ? ' suprimida' : ''}" title="${esc(titulo)}">
      <span class="nom">${esc(nombre)}</span>
      <span class="pista">
        ${base != null ? `<span class="fill base" style="width:${w(base)}%"></span>` : ''}
        ${valor != null ? `<span class="fill" style="width:${w(valor)}%"></span>` : ''}
      </span>
      <span class="num">${etiqueta}</span>
    </div>`;
  }

  function pintarEmbudo() {
    const total = datos.embudo[0].valor || 0;
    $('#embudo').innerHTML = datos.embudo.map((e, i) => {
      const p = total ? Math.round((100 * e.valor) / total) : 0;
      const et = i === 0 ? fmt.format(e.valor) : `${fmt.format(e.valor)} <small>${p} %</small>`;
      return fila(e.paso, e.valor, total, et, { titulo: `${e.paso}: ${fmt.format(e.valor)}` });
    }).join('');
  }

  function pintarTendencia() {
    const t = datos.tendencia;
    const c1 = css('--data-1');
    const c2 = css('--data-2');
    $('#leyenda-tendencia').innerHTML =
      `<span><i style="background:${c1}"></i>Fueron</span><span><i style="background:${c2}"></i>Volverían</span>`;
    const serie = (label, key, color) => ({
      label, data: t.map((x) => x[key]), borderColor: color, backgroundColor: color,
      borderWidth: 2, pointRadius: 4, pointHoverRadius: 6, pointBorderColor: '#ffffff', pointBorderWidth: 2,
      pointBackgroundColor: color, tension: 0, spanGaps: true,
    });
    const cfg = {
      type: 'line',
      data: { labels: t.map((x) => fechaCorta(x.fecha)), datasets: [serie('Fueron', 'asistencia_pct', c1), serie('Volverían', 'volverian_pct', c2)] },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: '#1e1f23', padding: 10, titleFont: { family: 'Barlow', weight: '600' }, bodyFont: { family: 'Barlow' },
            callbacks: {
              title: (items) => fechaLarga(t[items[0].dataIndex].fecha),
              label: (it) => ` ${it.dataset.label}: ${pct(it.parsed.y)}`,
              afterBody: (items) => {
                const x = t[items[0].dataIndex];
                return [`${fmt.format(x.respuestas)} respuestas`, `Bienestar: ${x.bienestar_promedio ?? ND} / 5`];
              },
            },
          },
        },
        scales: {
          y: { min: 40, max: 100, ticks: { stepSize: 20, callback: (v) => `${v} %`, color: css('--ink-muted'), font: { family: 'Barlow' } },
               grid: { color: '#ecece8' }, border: { display: false } },
          x: { ticks: { color: css('--ink-muted'), font: { family: 'Barlow' } }, grid: { display: false }, border: { color: '#d6d6d1' } },
        },
      },
    };
    if (grafTendencia) grafTendencia.destroy();
    grafTendencia = new Chart($('#tendencia'), cfg);
  }

  function pintarComunas() {
    const filas = [...datos.por_comuna].sort((a, b) => (b.inscritos.valor ?? -1) - (a.inscritos.valor ?? -1) || a.comuna - b.comuna);
    const max = Math.max(1, ...filas.map((f) => f.inscritos.valor || 0));
    $('#comunas').innerHTML =
      `<div class="leyenda"><span><i style="background:${css('--data-1')};height:10px"></i>Con parche</span><span><i style="background:${css('--data-track')};height:10px"></i>Inscritos</span></div>` +
      filas.filter((f) => f.inscritos.valor !== 0).map((f) => fila(
        `Comuna ${f.comuna}`, f.con_parche.valor, max,
        `${conteo(f.con_parche)} <small>/ ${conteo(f.inscritos)}</small>`,
        { base: f.inscritos.valor, titulo: `Comuna ${f.comuna}: ${conteo(f.inscritos)} inscritos, ${conteo(f.con_parche)} con parche, ${conteo(f.fueron)} fueron` },
      )).join('');
    $('#tabla-comunas').innerHTML = `<table><thead><tr><th>Comuna</th><th class="n">Inscritos</th><th class="n">Con parche</th><th class="n">Fueron</th><th class="n">Bienestar</th></tr></thead><tbody>${
      datos.por_comuna.map((f) => `<tr><td>Comuna ${f.comuna}</td><td class="n">${conteo(f.inscritos)}</td><td class="n">${conteo(f.con_parche)}</td><td class="n">${conteo(f.fueron)}</td><td class="n">${f.bienestar_promedio ?? `<span class="guion">${ND}</span>`}</td></tr>`).join('')
    }</tbody></table>`;
  }

  function pintarMapa() {
    if (!window.L) return;
    if (!mapa) {
      mapa = L.map('mapa', { scrollWheelZoom: false, zoomControl: true }).setView([3.435, -76.515], 12);
      setTimeout(() => mapa.invalidateSize(), 0);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 17, attribution: '&copy; colaboradores de OpenStreetMap',
      }).addTo(mapa);
    }
    if (capaMapa) capaMapa.remove();
    capaMapa = L.layerGroup().addTo(mapa);
    const color = css('--data-1');
    mapa.fitBounds(datos.por_tramo.map((x) => [x.lat, x.lng]), { padding: [28, 28], maxZoom: 14 });
    datos.por_tramo.forEach((t) => {
      const r = 4 + 1.1 * Math.sqrt(t.con_parche);
      L.circleMarker([t.lat, t.lng], { radius: r, color: '#ffffff', weight: 2, fillColor: color, fillOpacity: 0.55 })
        .bindTooltip(`<b>${esc(t.nombre)}</b> · comuna ${t.comuna}<br>${t.parches} parches · ${t.con_parche} con parche · ${t.fueron} fueron`)
        .addTo(capaMapa);
    });
  }

  function pintarBienestar() {
    const d = datos.bienestar_distribucion;
    const max = Math.max(1, ...d);
    $('#bienestar').innerHTML = d.map((n, i) => `
      <div class="col" title="${CARAS[i]}: ${n} respuestas">
        <span class="v">${fmt.format(n)}</span>
        <span class="barra" style="height:${(150 * n) / max}px"></span>
        <span class="e"><b>${i + 1}</b>${CARAS[i]}</span>
      </div>`).join('');
  }

  function pintarGrupos() {
    const sel = $('#filtro-tramo');
    const elegido = sel.value;
    const tramos = [...new Set(datos.por_grupo.map((g) => g.tramo))].sort();
    sel.innerHTML = '<option value="">Todas</option>' + tramos.map((t) => `<option>${esc(t)}</option>`).join('');
    sel.value = tramos.includes(elegido) ? elegido : '';
    const filas = datos.por_grupo.filter((g) => !sel.value || g.tramo === sel.value);
    const guion = `<span class="guion" title="Menos de ${datos.anonimato.k_promedio} respuestas">${ND}</span>`;
    $('#grupos').innerHTML = `<thead><tr>
        <th>Parche</th><th>Estación</th><th>Hora</th><th>Actividad</th><th>Cómo se armó</th>
        <th class="n">Integrantes</th><th class="n">Confirmaron</th><th class="n">Fueron</th><th class="n">Volverían</th><th class="n">Bienestar</th>
      </tr></thead><tbody>${filas.map((g) => `<tr>
        <td>${esc(g.grupo)}</td><td>${esc(g.tramo)}</td><td>${esc(g.hora)}</td><td>${esc(g.actividad)}</td>
        <td><span class="tag ${g.nivel}">${NIVEL[g.nivel] || g.nivel}</span></td>
        <td class="n">${g.tamano}</td><td class="n">${g.confirmados}</td><td class="n">${g.fueron}</td><td class="n">${g.volverian}</td>
        <td class="n">${g.bienestar_promedio == null ? guion : String(g.bienestar_promedio).replace('.', ',')}</td>
      </tr>`).join('')}</tbody>`;
  }

  $('#jornada').addEventListener('change', cargarResumen);
  $('#filtro-tramo').addEventListener('change', pintarGrupos);

  async function iniciar() {
    try {
      await cargarJornadas();
      await cargarResumen();
      marcarVivo(true);
    } catch (e) {
      marcarVivo(false);
      $('#kpis').innerHTML = `<div class="kpi"><div class="lbl">No se pudo cargar el tablero</div><div class="det">${esc(e.message)}</div></div>`;
    }
  }
  if (window.PARCHES_APP) {
    const a = $('#abrir-app');
    a.href = window.PARCHES_APP;
    a.hidden = false;
  }
  iniciar();
  // se refresca solo durante la demo, conservando la jornada elegida
  setInterval(() => cargarJornadas().then(cargarResumen).then(() => marcarVivo(true)).catch(() => marcarVivo(false)), 10000);
})();
