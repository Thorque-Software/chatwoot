// Design artifact only. No application imports, requests or source mutations.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/mauro/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const repo = path.resolve(__dirname, '../..');
const iconSet = require(path.join(repo, 'node_modules/.pnpm/@iconify-json+lucide@1.2.82/node_modules/@iconify-json/lucide/icons.json'));
const source = fs.readFileSync(path.join(repo, 'app/javascript/dashboard/assets/scss/_next-colors.scss'), 'utf8');
const darkSource = source.slice(source.indexOf('.dark {'));
function token(name) {
  const value = darkSource.match(new RegExp(`--${name}: ([\\d ]+);`));
  if (!value) throw new Error(`Missing existing token ${name}`);
  return `rgb(${value[1].trim().replaceAll(' ', ',')})`;
}
const c = {
  bg: token('slate-1'), sidebar: token('slate-2'), card: token('solid-2'),
  field: token('slate-3'), selected: token('surface-active'), line: token('slate-5'),
  connector: token('slate-7'), text: token('slate-12'), muted: token('slate-11'),
  subtle: token('slate-10'), blue: token('blue-11'), primary: token('blue-9'),
  blueBg: token('blue-3'), teal: token('teal-11'), tealBg: token('teal-3'),
  amber: token('amber-11'), amberBg: token('amber-3'), red: token('ruby-11'),
  violet: token('violet-11'), violetBg: token('violet-3'),
};
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
class Frame {
  constructor(width, height, title) {
    this.width = width; this.height = height;
    this.parts = [`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc"><title id="title">${esc(title)}</title><desc id="desc">Propuesta visual, datos de demostración. No es una captura de la aplicación ni un cambio publicado.</desc>`];
    this.rect(0, 0, width, height, c.bg);
  }
  add(markup) { this.parts.push(markup); }
  rect(x, y, w, h, fill, r = 0, stroke = 'none', sw = 1) {
    this.add(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`);
  }
  line(x1, y1, x2, y2, color = c.line, width = 1) {
    this.add(`<path d="M${x1} ${y1}H${x2}" fill="none" stroke="${color}" stroke-width="${width}"/>`);
    if (y1 !== y2) this.parts[this.parts.length - 1] = `<path d="M${x1} ${y1}L${x2} ${y2}" fill="none" stroke="${color}" stroke-width="${width}"/>`;
  }
  text(x, y, content, size = 14, color = c.text, weight = 400, anchor = 'start') {
    this.add(`<text x="${x}" y="${y}" fill="${color}" font-family="Segoe UI, Arial, sans-serif" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}">${esc(content)}</text>`);
  }
  circle(x, y, r, fill) { this.add(`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}"/>`); }
  icon(name, x, y, size = 18, color = c.muted, stroke = 1.5) {
    if (!iconSet.icons[name]) throw new Error(`Missing Lucide icon ${name}`);
    const body = iconSet.icons[name].body.replaceAll('stroke-width="2"', `stroke-width="${stroke}" vector-effect="non-scaling-stroke"`);
    this.add(`<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 24 24" color="${color}">${body}</svg>`);
  }
  surface(x, y, w, h, r = 12, fill = c.card) {
    // Native dark surfaces: one quiet ring, no invented large drop shadow.
    this.rect(x, y, w, h, fill, r, 'rgba(255,255,255,0.08)');
  }
  button(x, y, w, h, label, icon = null, fill = c.field, color = c.text) {
    this.rect(x, y, w, h, fill, 8, c.line);
    if (icon) this.icon(icon, x + 12, y + (h - 16) / 2, 16, color, 2);
    this.text(x + (icon ? 37 : 14), y + h / 2 + 5, label, 13, color, 500);
  }
  link(x, y, label, color = c.blue) { this.text(x, y, label, 13, color, 500); }
  info(x, y) { this.icon('info', x, y, 16, c.subtle); }
  path(d, color = c.connector, width = 1.5) { this.add(`<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round"/>`); }
  arrow(x, y, color = c.connector) { this.path(`M${x - 4} ${y - 4}l4 4-4 4`, color); }
  finish() { return this.parts.join('\n') + '\n</svg>\n'; }
}
function sidebar(f) {
  f.rect(0, 0, 224, f.height, c.sidebar);
  f.line(223.5, 0, 223.5, f.height);
  f.circle(28, 34, 10, c.primary);
  f.rect(24, 29, 8, 9, 'white', 3);
  f.text(49, 39, 'Arroyo Fitness', 15, c.text, 600);
  f.icon('chevrons-up-down', 193, 27, 15);
  f.rect(14, 65, 196, 34, c.field, 8);
  f.icon('search', 25, 74, 16, c.subtle);
  f.text(49, 87, 'Buscar...', 13, c.subtle);
  const nav = [
    ['inbox', 'Mi bandeja de entrada'], ['messages-square', 'Conversaciones'],
    ['clock-3', 'Seguimientos'], ['calendar-check', 'Postventa'],
    ['contact-round', 'Contactos'], ['users-round', 'Panel de vendedores'],
    ['chart-no-axes-combined', 'Informes'], ['megaphone', 'Campañas'],
    ['book-open', 'Centro de ayuda'],
  ];
  nav.forEach(([icon, label], index) => {
    const y = 125 + index * 42;
    const active = label === 'Panel de vendedores';
    if (active) f.rect(10, y - 1, 204, 36, c.selected, 8);
    f.icon(icon, 22, y + 7, 18, active ? c.text : c.muted, active ? 2 : 1.5);
    f.text(51, y + 21, label, 13, active ? c.text : c.muted, active ? 600 : 400);
  });
  f.line(16, f.height - 104, 208, f.height - 104);
  f.icon('settings-2', 23, f.height - 86, 17);
  f.text(51, f.height - 72, 'Ajustes', 13, c.muted);
  f.circle(29, f.height - 31, 15, c.amberBg);
  f.text(29, f.height - 26, 'AL', 11, c.amber, 600, 'middle');
  f.text(51, f.height - 36, 'Administrador local', 12, c.text, 500);
  f.text(51, f.height - 18, 'Arroyo Fitness', 11, c.subtle);
}
function metric(f, x, y, w, label, value, icon, accent = c.blue, foot = '') {
  f.surface(x, y, w, 98);
  f.text(x + 17, y + 25, label, 13, c.muted, 500);
  if (w >= 200) f.icon(icon, x + w - 35, y + 13, 17, accent, 2);
  f.text(x + 17, y + 71, value, 34, accent === c.teal ? c.teal : c.text, 600);
  if (foot) f.text(x + 66, y + 68, foot, 11, c.subtle);
}
function agent(f, x, y, w, person) {
  const juli = person === 'juli';
  f.rect(x, y, w, 98, c.sidebar, 10, c.line);
  f.circle(x + 29, y + 29, 15, juli ? c.blueBg : c.violetBg);
  f.text(x + 29, y + 33, juli ? 'JP' : 'MP', 11, juli ? c.blue : c.violet, 600, 'middle');
  f.text(x + 53, y + 25, juli ? 'Julieta Peralta' : 'Marcos Peralta', 14, c.text, 600);
  f.text(x + 53, y + 45, juli ? '5 derivadas · 3 con atención' : '4 derivadas · 4 con atención', 12, c.muted);
  f.icon('chevron-right', x + w - 28, y + 24, 16, c.subtle);
  f.line(x + 16, y + 59, x + w - 16, y + 59);
  const positions = [x + 17, x + Math.round(w * .37), x + Math.round(w * .70)];
  const cells = juli ? [['3', 'ganadas', c.teal], ['1', 'sin atender', c.amber], ['1', 'cliente sin respuesta', c.muted]]
    : [['1', 'ganada', c.teal], ['1', 'perdida', c.red], ['2', 'en gestión', c.blue]];
  cells.forEach(([n, label, color], i) => {
    f.text(positions[i], y + 82, n, 16, color, 600);
    if (label === 'cliente sin respuesta' && w < 400) {
      f.text(positions[i] + 17, y + 76, 'cliente no', 10, c.muted);
      f.text(positions[i] + 17, y + 90, 'respondió', 10, c.muted);
    } else f.text(positions[i] + 17, y + 81, label, 11, c.muted);
  });
}
function chart(f, x, y, w, h) {
  const juli = [2, 0, 0, 0, 0, 0, 1];
  const marcos = [2, 0, 0, 1, 0, 1, 0];
  const left = x + 24, top = y + 8, bottom = y + h - 28;
  const height = bottom - top;
  [0, 1, 2].forEach(value => {
    const gy = bottom - value * height / 2;
    f.line(left, gy, x + w, gy, c.line);
    f.text(x + 9, gy + 4, value, 10, c.subtle, 400, 'middle');
  });
  const step = (w - 28) / 7;
  for (let i = 0; i < 7; i += 1) {
    const cx = left + step * i + step / 2;
    const bh1 = juli[i] * height / 2;
    const bh2 = marcos[i] * height / 2;
    f.rect(cx - 17, bottom - Math.max(bh1, 2), 13, Math.max(bh1, 2), bh1 ? c.primary : c.connector, 3);
    f.rect(cx + 3, bottom - Math.max(bh2, 2), 13, Math.max(bh2, 2), bh2 ? c.violet : c.connector, 3);
    f.text(cx, bottom + 20, `${14 + i} oct`, 10, c.subtle, 400, 'middle');
  }
}
function postSale(f, x, y, w) {
  f.surface(x, y, w, 266);
  f.text(x + 20, y + 29, 'Recompra y postventa', 15, c.text, 600);
  const rows = [
    {icon: 'repeat-2', number: '1', label: 'Recompra ganada', color: c.teal},
    {icon: 'message-circle', number: '0', label: 'Retomaron contacto', color: c.muted},
    {icon: 'triangle-alert', number: '1', label: 'Consulta con incidencias', color: c.amber},
  ];
  rows.forEach((row, index) => {
    const ry = y + 57 + index * 50;
    f.icon(row.icon, x + 21, ry + 2, 17, row.color);
    f.text(x + 49, ry + 16, row.label, 12, c.muted);
    f.text(x + w - 24, ry + 17, row.number, 20, row.color, 600, 'end');
    if (index < 2) f.line(x + 20, ry + 33, x + w - 20, ry + 33);
  });
  f.line(x + 20, y + 216, x + w - 20, y + 216);
  f.link(x + 21, y + 244, 'Abrir postventa');
  f.icon('arrow-up-right', x + w - 37, y + 229, 17, c.blue);
}
function desktop() {
  const f = new Frame(1440, 1152, 'Mock-up de escritorio del Panel de vendedores de Arroyo');
  sidebar(f);
  const x = 264, w = 1136;
  f.text(x, 31, 'ARROYO  /  PANEL DE VENDEDORES', 10, c.subtle, 600);
  f.rect(1218, 16, 182, 24, c.field, 6);
  f.text(1309, 32, 'PROPUESTA · DATOS DEMO', 10, c.muted, 500, 'middle');
  f.text(x, 75, 'Panel de vendedores', 27, c.text, 600);
  f.text(x, 100, 'Consultas, atención y resultados del equipo.', 14, c.muted);
  f.button(1260, 58, 140, 36, 'Exportar CSV', 'download');
  f.text(x + 16, 144, 'Actividad', 13, c.blue, 600);
  f.text(x + 127, 144, 'Ventanas de 24 hs', 13, c.muted);
  f.text(x + 298, 144, 'Postventa', 13, c.muted);
  f.line(x, 159, x + w, 159);
  f.line(x, 158, x + 94, 158, c.primary, 2);
  f.button(x, 179, 195, 36, '14 – 20 oct 2026', 'calendar-days');
  f.icon('chevron-down', x + 169, 190, 14);
  f.button(x + 207, 179, 216, 36, 'Todos los vendedores', 'users-round');
  f.icon('chevron-down', x + 397, 190, 14);
  f.button(x + 435, 179, 204, 36, 'Demo comercial', 'inbox');
  f.icon('chevron-down', x + 613, 190, 14);
  f.link(x + 657, 202, 'Limpiar');
  f.circle(1257, 198, 3, c.teal);
  f.text(1270, 202, 'Estado actual', 11, c.muted);
  const mw = 275;
  metric(f, x, 237, mw, 'Consultas ingresadas', '11', 'messages-square');
  metric(f, x + 287, 237, mw, 'Sin primera atención', '1', 'clock-3', c.amber);
  metric(f, x + 574, 237, mw, 'En el bot', '1', 'bot', c.violet);
  metric(f, x + 861, 237, mw, 'Ventas ganadas', '4', 'badge-check', c.teal);
  f.rect(x, 351, w, 48, c.amberBg, 8);
  f.icon('clock-alert', x + 16, 366, 18, c.amber);
  f.text(x + 46, 380, '1 consulta sin respuesta del vendedor', 13, c.text, 500);
  f.text(x + 304, 380, '·  Más de 4 horas de atención', 12, c.muted);
  f.link(1246, 380, 'Revisar consulta', c.amber);
  f.icon('arrow-right', 1370, 366, 16, c.amber);
  f.surface(x, 419, w, 324);
  f.text(x + 24, 451, 'Recorrido de las consultas', 16, c.text, 600);
  f.info(x + 230, 438);
  f.text(1376, 451, 'Ingresadas en el período seleccionado', 11, c.subtle, 400, 'end');
  f.text(299, 480, 'INGRESO', 10, c.subtle, 600);
  f.text(551, 480, 'DERIVACIÓN', 10, c.subtle, 600);
  f.text(800, 480, 'ATENCIÓN Y RESULTADOS', 10, c.subtle, 600);
  f.rect(288, 536, 184, 88, c.blueBg, 10, token('blue-7'));
  f.text(306, 570, '11', 30, c.text, 600);
  f.text(306, 596, 'Consultas ingresadas', 12, c.blue, 500);
  // Branches count the same cohort: 1 + 1 + 9 = 11.
  f.path('M472 580H496Q510 580 510 566V531Q510 517 524 517H542'); f.arrow(542, 517);
  f.path('M472 580H542'); f.arrow(542, 580);
  f.path('M472 580H496Q510 580 510 594V619Q510 633 524 633H542', token('blue-7')); f.arrow(542, 633, token('blue-7'));
  [[493, 'bot', 'En el bot', '1', c.violet], [556, 'user-round-x', 'Sin asignar', '1', c.muted], [609, 'users-round', 'Con vendedor', '9', c.blue]].forEach(([y, icon, label, value, color]) => {
    f.rect(542, y, 174, 48, c.sidebar, 8, c.line);
    f.icon(icon, 555, y + 15, 17, color);
    f.text(581, y + 29, label, 12, c.muted);
    f.text(700, y + 30, value, 20, c.text, 600, 'end');
  });
  f.path('M716 633H746V553Q746 539 760 539H790', token('blue-7')); f.arrow(790, 539, token('blue-7'));
  f.path('M716 633H746V644Q746 658 760 658H790', token('blue-7')); f.arrow(790, 658, token('blue-7'));
  agent(f, 790, 493, 586, 'juli');
  agent(f, 790, 609, 586, 'marcos');
  f.text(288, 723, 'Atención y derivación son hitos; los resultados muestran el estado actual.', 11, c.subtle);
  // One activity owner contains both chart and table; avoids another duplicate totals table.
  f.surface(x, 763, 792, 331);
  f.text(x + 22, 795, 'Actividad realizada', 16, c.text, 600);
  f.info(x + 177, 782);
  f.button(875, 778, 159, 32, 'Atendidas', 'messages-square');
  f.icon('chevron-down', 1012, 788, 12);
  f.circle(x + 28, 824, 3.5, c.primary); f.text(x + 39, 828, 'Julieta', 11, c.muted);
  f.circle(x + 112, 824, 3.5, c.violet); f.text(x + 123, 828, 'Marcos', 11, c.muted);
  f.text(1034, 828, '7 consultas con atención en el período', 11, c.muted, 400, 'end');
  chart(f, x + 20, 845, 748, 145);
  f.line(x + 20, 992, x + 772, 992);
  f.text(x + 21, 1014, 'Vendedor', 11, c.subtle, 500);
  const columns = ['14 oct', '15 oct', '16 oct', '17 oct', '18 oct', '19 oct', '20 oct', 'Total'];
  columns.forEach((label, i) => f.text(x + 227 + i * 72, 1014, label, 10, c.subtle, 500, 'middle'));
  const data = [['Julieta', [2, 0, 0, 0, 0, 0, 1, 3], c.blue], ['Marcos', [2, 0, 0, 1, 0, 1, 0, 4], c.violet]];
  data.forEach(([name, values, color], i) => {
    const row = 1040 + i * 29;
    f.circle(x + 26, row - 4, 3, color); f.text(x + 38, row, name, 12, c.muted);
    values.forEach((n, j) => f.text(x + 227 + j * 72, row, n, 12, n ? (j === 7 ? c.text : color) : c.subtle, n ? 600 : 400, 'middle'));
  });
  postSale(f, 1076, 763, 324);
  f.icon('shield-check', 1097, 1050, 15, c.subtle);
  f.text(1120, 1062, '11 consultas con cobertura completa', 11, c.muted);
  f.link(1097, 1087, 'Cómo se cuentan los datos');
  f.text(x, 1125, 'Datos de demostración · 14–20 de octubre de 2026', 11, c.subtle);
  f.text(1400, 1125, 'Diseño propuesto · sin cambios en la aplicación', 11, c.subtle, 400, 'end');
  return f;
}
function mobile() {
  const f = new Frame(390, 1720, 'Mock-up móvil del Panel de vendedores de Arroyo');
  f.rect(0, 0, 390, 57, c.sidebar);
  f.icon('menu', 18, 20, 19); f.circle(58, 29, 9, c.primary);
  f.text(75, 34, 'Arroyo Fitness', 14, c.text, 600);
  f.rect(284, 17, 87, 24, c.field, 6); f.text(327, 33, 'MOCK-UP', 10, c.muted, 500, 'middle');
  f.text(18, 93, 'Panel de vendedores', 23, c.text, 600);
  f.text(18, 118, 'Consultas, atención y resultados.', 13, c.muted);
  f.icon('download', 354, 76, 18);
  f.text(21, 158, 'Actividad', 12, c.blue, 600); f.text(119, 158, 'Ventanas de 24 hs', 12, c.muted); f.text(288, 158, 'Postventa', 12, c.muted);
  f.line(18, 172, 372, 172); f.line(18, 171, 94, 171, c.primary, 2);
  f.button(18, 190, 184, 36, '14 – 20 oct 2026', 'calendar-days');
  f.button(214, 190, 158, 36, 'Todos', 'users-round'); f.icon('chevron-down', 347, 202, 12);
  f.rect(18, 237, 184, 28, c.field, 6); f.icon('inbox', 29, 244, 14); f.text(51, 255, 'Demo comercial', 11, c.muted); f.icon('x', 180, 244, 13);
  f.link(326, 255, 'Limpiar');
  metric(f, 18, 284, 171, 'Consultas ingresadas', '11', 'messages-square');
  metric(f, 201, 284, 171, 'Sin primera atención', '1', 'clock-3', c.amber);
  metric(f, 18, 394, 171, 'En el bot', '1', 'bot', c.violet);
  metric(f, 201, 394, 171, 'Ventas ganadas', '4', 'badge-check', c.teal);
  f.rect(18, 508, 354, 67, c.amberBg, 8); f.icon('clock-alert', 32, 524, 17, c.amber);
  f.text(59, 535, '1 consulta sin respuesta del vendedor', 12, c.text, 500);
  f.link(59, 556, 'Revisar consulta', c.amber); f.icon('arrow-right', 344, 537, 14, c.amber);
  f.surface(18, 593, 354, 523);
  f.text(35, 624, 'Recorrido de las consultas', 15, c.text, 600); f.info(337, 611);
  f.text(35, 645, 'Estado actual · ingresos del período', 11, c.subtle);
  f.rect(35, 664, 320, 64, c.blueBg, 9, token('blue-7'));
  f.text(51, 702, '11', 28, c.text, 600); f.text(97, 701, 'Consultas ingresadas', 13, c.blue);
  f.path('M195 728v16');
  f.rect(35, 744, 154, 39, c.sidebar, 7, c.line); f.icon('bot', 48, 756, 15, c.violet); f.text(71, 769, '1 en el bot', 12, c.muted);
  f.rect(201, 744, 154, 39, c.sidebar, 7, c.line); f.icon('user-round-x', 213, 756, 15); f.text(237, 769, '1 sin asignar', 12, c.muted);
  f.path('M195 783v20', token('blue-7'));
  f.rect(35, 803, 320, 43, c.sidebar, 7, c.line); f.icon('users-round', 49, 817, 16, c.blue); f.text(75, 830, '9 con vendedor', 13, c.text, 500);
  f.icon('chevron-down', 322, 817, 16, c.blue);
  agent(f, 35, 861, 320, 'juli'); agent(f, 35, 974, 320, 'marcos');
  f.text(35, 1097, 'Hitos y resultados se consultan por separado.', 10, c.subtle);
  f.surface(18, 1134, 354, 266);
  f.text(35, 1165, 'Actividad realizada', 15, c.text, 600); f.info(190, 1152);
  f.button(260, 1147, 95, 30, 'Atendidas'); f.icon('chevron-down', 337, 1156, 12);
  f.circle(40, 1189, 3, c.primary); f.text(51, 1193, 'Julieta', 11, c.muted); f.circle(121, 1189, 3, c.violet); f.text(132, 1193, 'Marcos', 11, c.muted);
  chart(f, 31, 1210, 322, 137);
  f.line(35, 1353, 355, 1353); f.link(35, 1380, 'Ver detalle por vendedor y día'); f.icon('arrow-right', 334, 1365, 16, c.blue);
  postSale(f, 18, 1418, 354);
  f.text(195, 1706, 'Propuesta visual · datos de demostración', 10, c.subtle, 400, 'middle');
  return f;
}
async function main() {
  for (const [name, frame] of [['desktop', desktop()], ['mobile', mobile()]]) {
    const svg = frame.finish();
    fs.writeFileSync(path.join(__dirname, `mockup-${name}.svg`), svg);
    await sharp(Buffer.from(svg), { density: 144 }).png().toFile(path.join(__dirname, `mockup-${name}.png`));
    console.log(`${name}: ${frame.width} × ${frame.height}, SVG and PNG exported`);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
