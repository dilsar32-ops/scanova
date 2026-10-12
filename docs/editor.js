// Scanova · editor de fotos (diseño de Amilcar, 12 oct 2026). Al tocar "Edit Photo" el panel de la derecha pasa a ser
// "Edit Photo": arriba Text, Arrow, Shape y Marker; un cuadro de ayuda; y secciones que se abren: Crop & Rotate,
// Adjustments, Filters, Markup Tools (Moisture, Wet area, Measure, Blur, color y grosor) y Undo & Redo. Abajo Reset y
// Apply Changes. Las marcas se pueden mover, cambiar de tamaño y editar arrastrándolas.
// Nada se pinta sobre la foto hasta guardar: ahí se hace todo sobre la ORIGINAL (girada, ajustada, recortada) y se sube
// como foto NUEVA en el mismo nivel y cuarto. La original nunca se toca.

// ---------- lo puro ----------
export const PRINCIPALES = [['texto', 'Text', 'texto'], ['flecha', 'Arrow', 'flecha'], ['forma', 'Shape', 'forma'], ['marcador', 'Marker', 'lapiz']];
export const MARKUP = [['humedad', 'Moisture', 'gota'], ['area', 'Wet area', 'area'], ['medida', 'Measure', 'regla'], ['borroso', 'Blur', 'borroso']];
export const HERRAMIENTAS = [['lapiz', 'Pen'], ['resalta', 'Highlight'], ['flecha', 'Arrow'], ['circulo', 'Circle'], ['cuadro', 'Box'],
  ['texto', 'Text'], ['humedad', 'Moisture'], ['area', 'Wet area'], ['medida', 'Measure'], ['borroso', 'Blur']];
export const COLORES = ['#ff3b30', '#ff9f0a', '#ffd60a', '#0a84ff', '#30d158', '#ffffff', '#1d1d1f'];
export const MATERIALES = ['Drywall', 'Wood floor', 'Baseboard', 'Cabinet', 'Concrete', 'Other'];
export const FILTROS = [['original', 'Original', {}], ['vivo', 'Vivid', { sat:35, con:15 }], ['claro', 'Bright', { exp:25, bri:10 }],
  ['drama', 'Dramatic', { exp:-10, con:35 }], ['suave', 'Muted', { sat:-40, con:-10 }], ['bn', 'B&W', { sat:-100, con:10 }]];
export const PROPORCIONES = [['libre', 'Free', 0], ['orig', 'Original', -1], ['cuadrado', 'Square', 1], ['43', '4:3', 4 / 3], ['169', '16:9', 16 / 9]];
// 17 % o más mojado, 12-16 secando, menos seco; sin número cuenta como mojado (se puede cambiar a mano).
export function estadoHumedad(v){ if(v === '' || v == null) return 'wet'; const n = Number(v); if(!isFinite(n)) return 'wet'; return n >= 17 ? 'wet' : n >= 12 ? 'drying' : 'dry'; }
const TXT = 1.7;   // el texto nace 1.7 veces la medida base (se ve en la foto sin tener que agrandarlo)
export const ESTADO = { wet:['WET', '#ff3b30'], drying:['DRYING', '#ff9f0a'], dry:['DRY', '#30d158'] };
// Ajustes + filtro -> factores. La vista previa usa CSS (brightness, contrast, saturate) y la copia hace la misma cuenta.
export function factores(aj, filtro){
  const f = (FILTROS.find(x => x[0] === filtro) || FILTROS[0])[2]; const a = aj || {};
  const v = (k) => (a[k] || 0) + (f[k] || 0);
  return { mult: Math.pow(2, v('exp') / 100) * (1 + v('bri') / 200), con: Math.max(0, 1 + v('con') / 100), sat: Math.max(0, 1 + v('sat') / 100) };
}
export const filtroCss = (aj, filtro) => { const f = factores(aj, filtro); return f.mult === 1 && f.con === 1 && f.sat === 1 ? '' : 'brightness(' + f.mult.toFixed(3) + ') contrast(' + f.con.toFixed(3) + ') saturate(' + f.sat.toFixed(3) + ')'; };
export function ajustarPixel(v, f){ const x = ((v / 255) * f.mult - 0.5) * f.con + 0.5; return Math.max(0, Math.min(255, Math.round(x * 255))); }
export function ajustarRGB(r, g, b, f){
  r = ajustarPixel(r, f); g = ajustarPixel(g, f); b = ajustarPixel(b, f);
  if(f.sat !== 1){ const l = 0.2126 * r + 0.7152 * g + 0.0722 * b; r = l + (r - l) * f.sat; g = l + (g - l) * f.sat; b = l + (b - l) * f.sat; }
  const c = (x) => Math.max(0, Math.min(255, Math.round(x))); return [c(r), c(g), c(b)];
}
// Calidez (Warmth, -100 a 100): más rojo y menos azul, o al revés. Nitidez (Sharpness, 0 a 100): realza los bordes.
export function calidezRGB(r, g, b, cal){ const k = (cal || 0) * 0.3; const c = (x) => Math.max(0, Math.min(255, Math.round(x))); return [c(r + k), c(g + k * 0.15), c(b - k)]; }
export function nitidez(datos, w, h, cantidad){
  const k = Math.max(0, Math.min(100, cantidad || 0)) / 100; if(!k || w < 3 || h < 3) return datos;
  const src = new Uint8ClampedArray(datos); const fila = w * 4;
  for(let y = 1; y < h - 1; y++) for(let x = 1; x < w - 1; x++){ const i = y * fila + x * 4;
    for(let c = 0; c < 3; c++){ const v = src[i + c]; datos[i + c] = v + k * (4 * v - src[i - 4 + c] - src[i + 4 + c] - src[i - fila + c] - src[i + fila + c]); } }
  return datos;
}
function calidezYNitidez(ctx, w, h, aj){
  const cal = aj.cal || 0, nit = aj.nit || 0; if(!cal && !nit) return;
  const d = ctx.getImageData(0, 0, w, h); const a = d.data;
  if(cal) for(let i = 0; i < a.length; i += 4){ const [r, g, b] = calidezRGB(a[i], a[i + 1], a[i + 2], cal); a[i] = r; a[i + 1] = g; a[i + 2] = b; }
  if(nit) nitidez(a, w, h, nit);
  ctx.putImageData(d, 0, 0);
}
export const tintaSobre = (hex) => { const h = String(hex).replace('#', ''); const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16); return (r * 299 + g * 587 + b * 114) / 1000 > 160 ? '#111' : '#fff'; };
// Girar 90° (sentido del reloj = +1): los puntos (de 0 a 1) y el recorte giran con la foto.
export const girarPunto = (p, sentido) => sentido > 0 ? [1 - p[1], p[0]] : [p[1], 1 - p[0]];
export const girarRecorte = (c, sentido) => sentido > 0 ? { x: 1 - (c.y + c.h), y: c.x, w: c.h, h: c.w } : { x: c.y, y: 1 - (c.x + c.w), w: c.h, h: c.w };
// La caja de una marca (en pixeles del marco w x h), para tocarla, moverla y cambiarle el tamaño.
export function cajaMarca(m, w, h){
  const u = w / 1000, e = m.escala || 1, pts = (m.puntos || []).map(p => [p[0] * w, p[1] * h]);
  if(m.tipo === 'texto' && pts.length){ const k = u * e * TXT; const ancho = (anchoTexto(String(m.texto || '')) + 22) * k, alto = 30 * k; return { x: pts[0][0] - ancho / 2, y: pts[0][1] - alto / 2, w: ancho, h: alto }; }
  if(m.tipo === 'humedad' && pts.length){ const r = 28 * u * e; return { x: pts[0][0] - r, y: pts[0][1] - r, w: 2 * r, h: 2 * r + (m.material ? 26 * u * e : 0) }; }
  if(!pts.length) return { x:0, y:0, w:0, h:0 };
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]); const g = (m.ancho || 4) * u * (m.tipo === 'resalta' ? 4 : 1) / 2 + 4 * u;
  const x0 = Math.min(...xs) - g, y0 = Math.min(...ys) - g; return { x: x0, y: y0, w: Math.max(...xs) + g - x0, h: Math.max(...ys) + g - y0 };
}
// Ancho del texto en la letra de la pastilla (a 16 px): medido de verdad si hay página, y si no (las pruebas) aproximado.
let MEDIDOR = null;
function anchoTexto(t){
  if(typeof document === 'undefined') return t.length * 9.4;
  if(!MEDIDOR){ MEDIDOR = document.createElement('canvas').getContext('2d'); MEDIDOR.font = '700 16px -apple-system, system-ui, sans-serif'; }
  return MEDIDOR.measureText(t).width;
}
export const dentro = (c, x, y, pad) => x >= c.x - (pad || 0) && x <= c.x + c.w + (pad || 0) && y >= c.y - (pad || 0) && y <= c.y + c.h + (pad || 0);

// Dibuja todas las marcas sobre un contexto con el marco de w x h. fuente = el marco (para difuminar). Coordenadas de 0 a 1.
export function dibujar(ctx, w, h, marcas, fuente){
  const P = (p) => [p[0] * w, p[1] * h];
  for(const m of marcas){
    const u = w / 1000 * (m.escala || 1); const g = Math.max(1, (m.ancho || 4) * w / 1000);
    ctx.save(); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = m.color; ctx.fillStyle = m.color; ctx.lineWidth = g; ctx.setLineDash([]);
    const pts = (m.puntos || []).map(P);
    if(m.tipo === 'lapiz' || m.tipo === 'resalta'){
      if(m.tipo === 'resalta'){ ctx.globalAlpha = 0.35; ctx.lineWidth = g * 4; }
      ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.stroke();
    } else if(m.tipo === 'flecha' && pts.length > 1){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const ang = Math.atan2(b[1] - a[1], b[0] - a[0]); const L = Math.max(g * 6, 16 * w / 1000);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(b[0] - L * Math.cos(ang - 0.45), b[1] - L * Math.sin(ang - 0.45)); ctx.lineTo(b[0], b[1]); ctx.lineTo(b[0] - L * Math.cos(ang + 0.45), b[1] - L * Math.sin(ang + 0.45)); ctx.stroke();
    } else if((m.tipo === 'circulo' || m.tipo === 'cuadro') && pts.length > 1){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const x = Math.min(a[0], b[0]), y = Math.min(a[1], b[1]), ww = Math.abs(b[0] - a[0]), hh = Math.abs(b[1] - a[1]);
      ctx.beginPath(); if(m.tipo === 'circulo') ctx.ellipse(x + ww / 2, y + hh / 2, ww / 2, hh / 2, 0, 0, Math.PI * 2); else ctx.rect(x, y, ww, hh); ctx.stroke();
    } else if(m.tipo === 'area' && pts.length > 2){
      const uu = w / 1000;
      ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.closePath();
      ctx.fillStyle = 'rgba(10,132,255,.28)'; ctx.fill(); ctx.strokeStyle = '#0a84ff'; ctx.lineWidth = Math.max(2, 3 * uu); ctx.setLineDash([10 * uu, 7 * uu]); ctx.stroke(); ctx.setLineDash([]);
      const cx = pts.reduce((s, p) => s + p[0], 0) / pts.length, cy = pts.reduce((s, p) => s + p[1], 0) / pts.length;
      pastilla(ctx, cx, cy, m.texto || 'Wet area', '#0a84ff', '#fff', uu * 1.4);
    } else if(m.tipo === 'medida' && pts.length > 1){
      const uu = w / 1000; const [a, b] = [pts[0], pts[pts.length - 1]]; const ang = Math.atan2(b[1] - a[1], b[0] - a[0]); const t = g * 3;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      [a, b].forEach(p => { ctx.moveTo(p[0] - t * Math.sin(ang), p[1] + t * Math.cos(ang)); ctx.lineTo(p[0] + t * Math.sin(ang), p[1] - t * Math.cos(ang)); }); ctx.stroke();
      if(m.texto) pastilla(ctx, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, m.texto, 'rgba(0,0,0,.7)', '#fff', uu * 1.4);
    } else if(m.tipo === 'texto' && pts.length){
      pastilla(ctx, pts[0][0], pts[0][1], m.texto || '', m.color, tintaSobre(m.color), u * TXT);
    } else if(m.tipo === 'humedad' && pts.length){
      const [x, y] = pts[0]; const r = 28 * u; const [, col] = ESTADO[m.estado] || ESTADO.wet;
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = col; ctx.fill(); ctx.lineWidth = 4 * u; ctx.strokeStyle = '#fff'; ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.font = '800 ' + Math.round(17 * u) + 'px -apple-system, system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText((m.valor === '' || m.valor == null ? '?' : m.valor) + '%', x, y + 1 * u);
      if(m.material) pastilla(ctx, x, y + r + 16 * u, m.material, 'rgba(0,0,0,.65)', '#fff', u * 0.8);
    } else if(m.tipo === 'borroso' && pts.length > 1 && fuente){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const x = Math.round(Math.min(a[0], b[0])), y = Math.round(Math.min(a[1], b[1])), ww = Math.round(Math.abs(b[0] - a[0])), hh = Math.round(Math.abs(b[1] - a[1]));
      if(ww > 2 && hh > 2){ const tam = Math.max(4, Math.round(w / 90)); const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(ww / tam)); c.height = Math.max(1, Math.round(hh / tam));
        const sx = fuente.naturalWidth || fuente.width, sy = fuente.naturalHeight || fuente.height;
        c.getContext('2d').drawImage(fuente, x / w * sx, y / h * sy, ww / w * sx, hh / h * sy, 0, 0, c.width, c.height);
        ctx.imageSmoothingEnabled = false; ctx.drawImage(c, 0, 0, c.width, c.height, x, y, ww, hh); ctx.imageSmoothingEnabled = true; c.width = c.height = 0; }
    }
    ctx.restore();
  }
}
function pastilla(ctx, x, y, txt, fondo, tinta, u){
  if(!txt) return; ctx.save(); ctx.font = '700 ' + Math.round(16 * u) + 'px -apple-system, system-ui, sans-serif';
  const w = ctx.measureText(txt).width + 22 * u, h = 30 * u; const x0 = x - w / 2, y0 = y - h / 2, r = h / 2;
  ctx.beginPath(); ctx.moveTo(x0 + r, y0); ctx.arcTo(x0 + w, y0, x0 + w, y0 + h, r); ctx.arcTo(x0 + w, y0 + h, x0, y0 + h, r); ctx.arcTo(x0, y0 + h, x0, y0, r); ctx.arcTo(x0, y0, x0 + w, y0, r); ctx.closePath();
  ctx.fillStyle = fondo; ctx.fill(); ctx.fillStyle = tinta; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(txt, x, y + 1 * u); ctx.restore();
}
// El marco: la foto ya girada (rot = 0, 90, 180 o 270), en un lienzo.
function hacerMarco(img, rot, max){
  const nw = img.naturalWidth || img.width, nh = img.naturalHeight || img.height; const k = max ? Math.min(1, max / Math.max(nw, nh)) : 1;
  const w = Math.round(nw * k), h = Math.round(nh * k); const c = document.createElement('canvas');
  const rr = ((rot % 360) + 360) % 360; c.width = rr % 180 ? h : w; c.height = rr % 180 ? w : h;
  const ctx = c.getContext('2d'); ctx.translate(c.width / 2, c.height / 2); ctx.rotate(rr * Math.PI / 180); ctx.drawImage(img, -w / 2, -h / 2, w, h);
  ctx.setTransform(1, 0, 0, 1, 0, 0);   // sin esto, todo lo que se pinta después (las marcas de la copia) sale corrido medio cuadro
  return c;
}
function cargarImg(url){ return new Promise((res, rej) => { const im = new Image(); im.onload = () => res(im); im.onerror = () => rej(new Error('the image did not load')); im.src = url; if(im.complete && im.naturalWidth) res(im); }); }

// ---------- el editor en la página ----------
let E = null;
export const activo = () => !!E;
const $ = (s, r = document) => r.querySelector(s);
const IC = (n) => '<svg class="ic"><use href="#i-' + n + '"/></svg>';
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const RECORTE_TODO = () => ({ x:0, y:0, w:1, h:1 });
const hayCambios = () => E && (E.marcas.length || E.rot || E.filtro !== 'original' || Object.values(E.aj).some(Boolean) || E.crop.x || E.crop.y || E.crop.w < 1 || E.crop.h < 1);

export async function abrir(op){
  if(E) return;
  E = { ...op, marcas: [], deshacer: [], rehacer: [], herr: 'texto', forma: 'circulo', marca: 'lapiz', color: COLORES[0], ancho: 5,
        aj: { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }, filtro: 'original', rot: 0, crop: RECORTE_TODO(), prop: 'libre', abierto: '', sel: -1, hoja: '',
        mat: 'Drywall', valor: '', estado: '', estadoFijo: false, cargando: true };
  document.body.classList.add('fv-editando'); if(E.tel){ E.bandeja.hidden = false; } pintarPanel();
  try{
    const r = await fetch(op.urlWeb); if(!r.ok) throw new Error('HTTP ' + r.status);
    const url = URL.createObjectURL(await r.blob()); const im = await cargarImg(url);
    if(!E){ URL.revokeObjectURL(url); return; }
    E.fuente = im; E.urlFuente = url; E.marco = hacerMarco(im, 0); E.cargando = false;
    montar(); pintarPanel(); render();
  }catch(e){ if(E){ E.cargando = false; E.error = 'Could not load the photo to edit. ' + String(e && e.message || e); pintarPanel(); } }
}
export function cerrar(forzar){
  if(!E) return true;
  if(!forzar && hayCambios()){ salir(() => {}); return false; }
  const x = E; E = null; quitarEscritura(x);
  if(x.tel){ x.bandeja.hidden = true; x.bandeja.innerHTML = ''; x.cajaHoja.hidden = true; x.cajaHoja.innerHTML = ''; if(x.velo) x.velo.hidden = true; }
  if(x.base) x.base.remove(); if(x.lienzo) x.lienzo.remove(); x.img.style.visibility = '';
  if(x.urlFuente) setTimeout(() => URL.revokeObjectURL(x.urlFuente), 2000);
  window.removeEventListener('resize', colocar); document.removeEventListener('keydown', teclas);
  document.body.classList.remove('fv-editando');
  if(x.alSalir) x.alSalir();
  return true;
}
const enRecorte = () => E && E.abierto === 'recorte';
const FW = () => E.marco.width, FH = () => E.marco.height;
// Lo que se ve: el recorte (o, mientras se recorta, la foto entera).
const vista = () => enRecorte() ? RECORTE_TODO() : E.crop;

function montar(){
  const caja = E.img.parentNode;
  E.base = document.createElement('canvas'); E.base.className = 'ed-base';
  E.lienzo = document.createElement('canvas'); E.lienzo.className = 'ed-lienzo';
  caja.appendChild(E.base); caja.appendChild(E.lienzo); E.img.style.visibility = 'hidden';
  colocar(); window.addEventListener('resize', colocar); document.addEventListener('keydown', teclas);
  const c = E.lienzo; let acc = null;
  const aMarco = (ev) => { const r = c.getBoundingClientRect(); const v = vista(); const px = (ev.clientX - r.left) / r.width, py = (ev.clientY - r.top) / r.height; return [v.x + px * v.w, v.y + py * v.h]; };
  c.addEventListener('pointerdown', (ev) => {
    if(!E || E.cargando) return; ev.preventDefault(); c.setPointerCapture(ev.pointerId);
    const p = aMarco(ev); const fx = p[0] * FW(), fy = p[1] * FH(); const k = c.getBoundingClientRect().width / (vista().w * FW()); const pad = 10 / k;
    if(enRecorte()){ acc = empezarRecorte(p, pad); return; }
    // ¿Tocó la esquina de la marca escogida (tamaño) o una marca (mover)?
    if(E.sel >= 0){ const cj = cajaMarca(E.marcas[E.sel], FW(), FH()); if(Math.hypot(fx - (cj.x + cj.w), fy - (cj.y + cj.h)) < 16 / k){ acc = { modo:'escala', ini: p, caja: cj, antes: JSON.parse(JSON.stringify(E.marcas[E.sel])), movio: false }; return; } }
    for(let i = E.marcas.length - 1; i >= 0; i--){ if(dentro(cajaMarca(E.marcas[i], FW(), FH()), fx, fy, pad)){ const ya = E.sel === i; E.sel = i; acc = { modo:'mover', ini: p, ultimo: p, ya, movio: false, guardado: false }; render(); pintarPanel(); return; } }
    if(E.sel >= 0){ E.sel = -1; render(); pintarPanel(); }
    const t = herrActual();
    if(t === 'texto'){ acc = { modo:'texto', p }; return; }   // el cuadrito para escribir sale al soltar el dedo (iOS solo abre el teclado así)
    if(t === 'humedad'){ const v = String(E.valor).trim(); agregar({ tipo:'humedad', puntos:[p], valor:v, material:E.mat === 'Other' ? '' : E.mat, estado:E.estado || estadoHumedad(v), escala:1 }); return; }
    acc = { modo:'dibujo', m: { tipo:t, color:E.color, ancho:E.ancho, puntos:[p, p] } };
  });
  c.addEventListener('pointermove', (ev) => {
    if(!acc) return; const p = aMarco(ev);
    if(acc.modo === 'recorte'){ moverRecorte(acc, p); return; }
    if(acc.modo === 'dibujo'){ const m = acc.m; if(m.tipo === 'lapiz' || m.tipo === 'resalta' || m.tipo === 'area') m.puntos.push(p); else m.puntos[1] = p; render(m); return; }
    const m = E.marcas[E.sel]; if(!m) return;
    if(!acc.guardado){ E.deshacer.push(estado()); E.rehacer = []; acc.guardado = true; }
    acc.movio = true;
    if(acc.modo === 'mover'){ const dx = p[0] - acc.ultimo[0], dy = p[1] - acc.ultimo[1]; acc.ultimo = p; m.puntos = m.puntos.map(q => [q[0] + dx, q[1] + dy]); }
    else if(acc.modo === 'escala'){
      const cj = acc.caja; const ox = cj.x / FW(), oy = cj.y / FH(); const r0 = Math.hypot(acc.ini[0] - ox, acc.ini[1] - oy) || 1e-6; const k = Math.max(0.2, Math.min(6, Math.hypot(p[0] - ox, p[1] - oy) / r0));
      if(m.tipo === 'texto' || m.tipo === 'humedad'){ m.escala = (acc.antes.escala || 1) * k; }
      else m.puntos = acc.antes.puntos.map(q => [ox + (q[0] - ox) * k, oy + (q[1] - oy) * k]);
    }
    render();
  });
  const fin = () => {
    if(!acc) return; const a = acc; acc = null;
    if(a.modo === 'recorte'){ render(); return; }
    if(a.modo === 'texto'){ escribir(a.p, -1); return; }
    if(a.modo === 'dibujo'){
      const m = a.m; const [p0, p1] = [m.puntos[0], m.puntos[m.puntos.length - 1]];
      if(!(Math.hypot(p1[0] - p0[0], p1[1] - p0[1]) > 0.01 || m.puntos.length > 3)){ render(); return; }
      if(m.tipo === 'medida') m.texto = (prompt('Measurement (e.g. 4\' 6")') || '').trim();
      if(m.tipo === 'area') m.texto = (prompt('Label for this area', 'Wet area') || '').trim() || 'Wet area';
      agregar(m); return;
    }
    // Tocar otra vez una marca escogida (sin moverla) = editar su texto.
    if(a.modo === 'mover' && !a.movio && a.ya) editarSel();
    pintarPanel(); render();
  };
  c.addEventListener('pointerup', fin); c.addEventListener('pointercancel', fin);
}
// Escribir el texto DIRECTO en la foto: un cuadrito encima del lugar tocado. Enter o tocar afuera = listo; Esc = no.
function quitarEscritura(x){ const z = x || E; if(z && z.escritura){ const n = z.escritura; z.escritura = null; n.remove(); } }
function escribir(p, i){
  quitarEscritura(); const c = E.lienzo; const v = vista(); const m = i >= 0 ? E.marcas[i] : null;
  const inp = document.createElement('input'); inp.type = 'text'; inp.className = 'ed-escribe'; inp.maxLength = 60; inp.placeholder = 'Type here';
  inp.setAttribute('enterkeyhint', 'done'); inp.value = m ? (m.texto || '') : '';
  const color = m ? m.color : E.color; inp.style.background = color; inp.style.color = tintaSobre(color);
  inp.style.left = (c.offsetLeft + (p[0] - v.x) / v.w * c.clientWidth) + 'px'; inp.style.top = (c.offsetTop + (p[1] - v.y) / v.h * c.clientHeight) + 'px';
  c.parentNode.appendChild(inp); E.escritura = inp;
  let hecho = false;
  const listo = (vale) => { if(hecho || !E) return; hecho = true; const t = inp.value.trim(); quitarEscritura();
    if(!vale) return;
    if(m){ if(t && t !== m.texto){ E.deshacer.push(estado()); E.rehacer = []; m.texto = t; } }
    else if(t){ agregar({ tipo:'texto', color, puntos:[p], texto:t, escala:1 }); E.sel = E.marcas.length - 1; }
    render(); pintarPanel(); };
  inp.addEventListener('keydown', (e) => { if(e.key === 'Enter'){ e.preventDefault(); listo(true); } else if(e.key === 'Escape'){ e.preventDefault(); listo(false); } e.stopPropagation(); });
  inp.addEventListener('blur', () => listo(true));
  inp.focus();
}
function herrActual(){ return E.herr === 'forma' ? E.forma : E.herr === 'marcador' ? E.marca : E.herr; }
function editarSel(){
  const m = E.marcas[E.sel]; if(!m) return;
  if(m.tipo === 'texto'){ escribir(m.puntos[0], E.sel); return; }
  if(m.tipo === 'medida' || m.tipo === 'area'){ const t = prompt(m.tipo === 'medida' ? 'Measurement' : m.tipo === 'area' ? 'Label for this area' : 'Text', m.texto || ''); if(t != null && t.trim()){ E.deshacer.push(estado()); E.rehacer = []; m.texto = t.trim(); } }
  else if(m.tipo === 'humedad'){ const t = prompt('Moisture reading (%)', m.valor || ''); if(t != null){ E.deshacer.push(estado()); E.rehacer = []; m.valor = t.trim(); m.estado = estadoHumedad(m.valor); } }
  render(); pintarPanel();
}
function borrarSel(){ if(E.sel < 0) return; E.deshacer.push(estado()); E.rehacer = []; E.marcas.splice(E.sel, 1); E.sel = -1; render(); pintarPanel(); }
function teclas(e){
  if(!E) return; if(/INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || '')) return;
  if((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z'){ e.preventDefault(); e.shiftKey ? rehacer() : deshacer(); }
  else if((e.key === 'Delete' || e.key === 'Backspace') && E.sel >= 0){ e.preventDefault(); borrarSel(); }
}

// ---------- recortar ----------
function empezarRecorte(p, pad){
  const c = E.crop; const esq = [[c.x, c.y], [c.x + c.w, c.y], [c.x, c.y + c.h], [c.x + c.w, c.y + c.h]];
  const tolX = pad * 2 / FW(), tolY = pad * 2 / FH();
  const i = esq.findIndex(q => Math.abs(q[0] - p[0]) < tolX && Math.abs(q[1] - p[1]) < tolY);
  E.deshacer.push(estado()); E.rehacer = [];
  if(i >= 0) return { modo:'recorte', esquina:i, ini:p, antes:{ ...c } };
  if(p[0] > c.x && p[0] < c.x + c.w && p[1] > c.y && p[1] < c.y + c.h) return { modo:'recorte', esquina:-1, ini:p, antes:{ ...c } };
  E.deshacer.pop(); return null;
}
function proporcion(){ const pr = PROPORCIONES.find(x => x[0] === E.prop) || PROPORCIONES[0]; return pr[2] === -1 ? (E.fuente.naturalWidth / E.fuente.naturalHeight) * (E.rot % 180 ? 1 : 1) : pr[2]; }
function moverRecorte(a, p){
  const c = { ...a.antes }; const dx = p[0] - a.ini[0], dy = p[1] - a.ini[1]; const MIN = 0.06;
  if(a.esquina < 0){ c.x = Math.max(0, Math.min(1 - c.w, c.x + dx)); c.y = Math.max(0, Math.min(1 - c.h, c.y + dy)); }
  else {
    let x0 = c.x, y0 = c.y, x1 = c.x + c.w, y1 = c.y + c.h;
    if(a.esquina === 0 || a.esquina === 2) x0 = Math.min(x1 - MIN, Math.max(0, x0 + dx)); else x1 = Math.max(x0 + MIN, Math.min(1, x1 + dx));
    if(a.esquina === 0 || a.esquina === 1) y0 = Math.min(y1 - MIN, Math.max(0, y0 + dy)); else y1 = Math.max(y0 + MIN, Math.min(1, y1 + dy));
    c.x = x0; c.y = y0; c.w = x1 - x0; c.h = y1 - y0;
    const r = proporcion();
    if(r > 0){ // mantener la proporción (en pixeles del marco)
      const hNorm = (c.w * FW() / r) / FH();
      if(hNorm <= 1){ if(a.esquina === 0 || a.esquina === 1) c.y = y1 - hNorm; c.h = hNorm; } else { const wNorm = (c.h * FH() * r) / FW(); if(a.esquina === 0 || a.esquina === 2) c.x = x1 - wNorm; c.w = wNorm; }
      c.x = Math.max(0, c.x); c.y = Math.max(0, c.y); c.w = Math.min(c.w, 1 - c.x); c.h = Math.min(c.h, 1 - c.y);
    }
  }
  E.crop = c; render();
}
function ponerProporcion(id){
  E.prop = id; const r = proporcion(); if(r <= 0){ pintarPanel(); return; }
  E.deshacer.push(estado()); E.rehacer = [];
  let w = 1, h = (FW() / r) / FH(); if(h > 1){ h = 1; w = (FH() * r) / FW(); }
  E.crop = { x: (1 - w) / 2, y: (1 - h) / 2, w, h }; colocar(); pintarPanel();
}
function girar(sentido){
  E.deshacer.push(estado()); E.rehacer = [];
  E.rot = (E.rot + (sentido > 0 ? 90 : 270)) % 360; E.marco = hacerMarco(E.fuente, E.rot);
  E.marcas.forEach(m => { m.puntos = m.puntos.map(p => girarPunto(p, sentido)); });
  E.crop = girarRecorte(E.crop, sentido); colocar(); pintarPanel();
}

// ---------- pintar ----------
// Los dos lienzos van justo encima de la parte de la caja donde cabe la foto (o el recorte).
function colocar(){
  if(!E || !E.lienzo) return; const img = E.img; const v = vista();
  const cw = img.clientWidth, ch = img.clientHeight; const aw = v.w * FW(), ah = v.h * FH();
  const k = Math.min(cw / aw, ch / ah); const w = aw * k, h = ah * k; const dpr = Math.min(2, window.devicePixelRatio || 1);
  [E.base, E.lienzo].forEach(c => { c.style.left = (img.offsetLeft + (cw - w) / 2) + 'px'; c.style.top = (img.offsetTop + (ch - h) / 2) + 'px'; c.style.width = w + 'px'; c.style.height = h + 'px'; c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); });
  render();
}
function render(extra){
  if(!E || !E.lienzo) return; const v = vista(); const b = E.base, c = E.lienzo;
  const bx = b.getContext('2d'); bx.clearRect(0, 0, b.width, b.height);
  bx.drawImage(E.marco, v.x * FW(), v.y * FH(), v.w * FW(), v.h * FH(), 0, 0, b.width, b.height);
  calidezYNitidez(bx, b.width, b.height, E.aj);
  b.style.filter = filtroCss(E.aj, E.filtro);
  const ctx = c.getContext('2d'); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, c.width, c.height);
  const k = c.width / (v.w * FW()); ctx.setTransform(k, 0, 0, k, -v.x * FW() * k, -v.y * FH() * k);
  dibujar(ctx, FW(), FH(), extra ? E.marcas.concat([extra]) : E.marcas, E.marco);
  if(E.sel >= 0 && E.marcas[E.sel] && !enRecorte()){ const cj = cajaMarca(E.marcas[E.sel], FW(), FH());
    ctx.save(); ctx.lineWidth = 1.5 / k; ctx.strokeStyle = '#0a84ff'; ctx.setLineDash([6 / k, 4 / k]); ctx.strokeRect(cj.x, cj.y, cj.w, cj.h); ctx.setLineDash([]);
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#0a84ff'; ctx.lineWidth = 2 / k; ctx.beginPath(); ctx.arc(cj.x + cj.w, cj.y + cj.h, 7 / k, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); ctx.restore(); }
  if(enRecorte()){ const cr = E.crop; const X = cr.x * FW(), Y = cr.y * FH(), W = cr.w * FW(), H = cr.h * FH();
    ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.beginPath(); ctx.rect(0, 0, FW(), FH()); ctx.rect(X, Y, W, H); ctx.fill('evenodd');
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 2 / k; ctx.strokeRect(X, Y, W, H); ctx.lineWidth = 1 / k; ctx.strokeStyle = 'rgba(255,255,255,.5)';
    for(let i = 1; i < 3; i++){ ctx.beginPath(); ctx.moveTo(X + W * i / 3, Y); ctx.lineTo(X + W * i / 3, Y + H); ctx.moveTo(X, Y + H * i / 3); ctx.lineTo(X + W, Y + H * i / 3); ctx.stroke(); }
    ctx.lineWidth = 5 / k; ctx.strokeStyle = '#fff'; const L = 22 / k;
    [[X, Y, 1, 1], [X + W, Y, -1, 1], [X, Y + H, 1, -1], [X + W, Y + H, -1, -1]].forEach(([x, y, sx, sy]) => { ctx.beginPath(); ctx.moveTo(x + L * sx, y); ctx.lineTo(x, y); ctx.lineTo(x, y + L * sy); ctx.stroke(); });
    ctx.restore(); }
}
function estado(){ return { marcas: JSON.parse(JSON.stringify(E.marcas)), aj: { ...E.aj }, filtro: E.filtro, rot: E.rot, crop: { ...E.crop } }; }
function volver(s){ const girado = s.rot !== E.rot; E.marcas = s.marcas; E.aj = s.aj; E.filtro = s.filtro; E.rot = s.rot; E.crop = s.crop; E.sel = -1; if(girado) E.marco = hacerMarco(E.fuente, E.rot); colocar(); pintarPanel(); }
function agregar(m){ E.deshacer.push(estado()); E.rehacer = []; E.marcas.push(m); render(); pintarPanel(); }
function deshacer(){ if(!E.deshacer.length) return; E.rehacer.push(estado()); volver(E.deshacer.pop()); }
function rehacer(){ if(!E.rehacer.length) return; E.deshacer.push(estado()); volver(E.rehacer.pop()); }

const AYUDA = { texto:'Click anywhere on the photo to add text. Then drag to move, resize, or edit.', flecha:'Drag from where the arrow starts to where it points.',
  forma:'Drag on the photo to draw the shape.', marcador:'Draw freely on the photo.', humedad:'Write the reading, then tap where you measured.',
  area:'Draw around the wet area with your finger.', medida:'Drag along what you measured, then write the measurement.', borroso:'Drag over what you want to hide (faces, papers, house numbers).' };
const NOMBRE = { texto:'Text', flecha:'Arrow', circulo:'Circle', cuadro:'Box', lapiz:'Marker', resalta:'Highlight', humedad:'Moisture reading', area:'Wet area', medida:'Measurement', borroso:'Blur' };
function seccion(id, icono, titulo, cuerpo){
  const ab = E.abierto === id;
  return `<div class="ed-acc${ab ? ' abierto' : ''}"><button type="button" class="ed-acc-t" data-ed-abrir="${id}">${IC(icono)}<span>${titulo}</span>${IC('chev')}</button>${ab ? '<div class="ed-acc-c">' + cuerpo + '</div>' : ''}</div>`;
}
function pintarPanel(){
  if(!E) return; if(E.tel) return pintarTel(); const p = E.panel;
  const est = E.estado || estadoHumedad(E.valor); const sel = E.sel >= 0 ? E.marcas[E.sel] : null;
  const tile = ([k, t, ic]) => `<button type="button" class="ed-t${E.herr === k ? ' on' : ''}" data-ed-herr="${k}">${IC(ic)}<span>${t}</span></button>`;
  const colores = `<div class="ed-colores">${COLORES.map(c => `<button type="button" class="ed-color${E.color === c ? ' on' : ''}" data-ed-color="${c}" style="background:${c}" aria-label="Color"></button>`).join('')}</div>`;
  const opciones = E.herr === 'forma' ? `<div class="ed-sub">${[['circulo', 'Circle'], ['cuadro', 'Box']].map(([k, t]) => `<button type="button" class="ed-chip${E.forma === k ? ' on' : ''}" data-ed-forma="${k}">${t}</button>`).join('')}</div>`
    : E.herr === 'marcador' ? `<div class="ed-sub">${[['lapiz', 'Marker'], ['resalta', 'Highlighter']].map(([k, t]) => `<button type="button" class="ed-chip${E.marca === k ? ' on' : ''}" data-ed-marca="${k}">${t}</button>`).join('')}</div>`
    : E.herr === 'humedad' ? `<div class="ed-mat">${MATERIALES.map(m => `<button type="button" class="ed-chip${E.mat === m ? ' on' : ''}" data-ed-mat="${esc(m)}">${esc(m)}</button>`).join('')}</div>
        <div class="ed-lect"><input type="number" inputmode="decimal" id="edValor" min="0" max="100" step="0.1" placeholder="28" value="${esc(E.valor)}"><span>%</span>${Object.keys(ESTADO).map(k => `<button type="button" class="ed-est ${k}${est === k ? ' on' : ''}" data-ed-est="${k}">${ESTADO[k][0]}</button>`).join('')}</div>` : '';
  const conColor = !['humedad', 'area', 'borroso'].includes(E.herr);
  const ayuda = enRecorte() ? 'Drag the corners to crop, or drag inside to move the frame. Close "Crop & Rotate" when you are done.'
    : sel ? 'Selected: ' + (NOMBRE[sel.tipo] || 'mark') + '. Drag to move it, drag the round corner to resize' + (['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? ', tap it again to edit' : '') + '.' : AYUDA[E.herr];
  p.innerHTML = `<div class="ed-cab"><h2 class="fv-h">Edit Photo</h2><button type="button" class="ed-x" data-ed="cerrar" aria-label="Close editor">✕</button></div>
    ${E.cargando ? '<p class="fv-gris">Loading the photo…</p>' : ''}${E.error ? '<p class="aviso">' + esc(E.error) + '</p>' : ''}
    <div class="ed-tiles">${PRINCIPALES.map(tile).join('')}</div>
    <div class="ed-info">${IC('info')}<div><p>${esc(ayuda)}</p>
      ${sel && !enRecorte() ? `<div class="ed-sub">${['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? '<button type="button" class="ed-chip" data-ed="editar">Edit</button>' : ''}<button type="button" class="ed-chip rojo" data-ed="borrar">Delete</button><button type="button" class="ed-chip" data-ed="soltar">Done</button></div>` : ''}
      ${!sel && !enRecorte() ? opciones + (conColor ? colores : '') : ''}</div></div>
    <div class="ed-accs">
      ${seccion('recorte', 'recortar', 'Crop &amp; Rotate', `<div class="ed-sub">${PROPORCIONES.map(([k, t]) => `<button type="button" class="ed-chip${E.prop === k ? ' on' : ''}" data-ed-prop="${k}">${t}</button>`).join('')}</div>
        <div class="ed-sub"><button type="button" class="ed-chip" data-ed="girar-izq">${IC('girar-izq')}Rotate left</button><button type="button" class="ed-chip" data-ed="girar-der">${IC('girar-der')}Rotate right</button><button type="button" class="ed-chip" data-ed="sin-recorte">Reset crop</button></div>`)}
      ${seccion('ajustes', 'ajustes', 'Adjustments', [['exp', 'Exposure'], ['bri', 'Brightness'], ['con', 'Contrast'], ['sat', 'Saturation']].map(([k, t]) => `<div class="ed-fila"><span>${t}</span><input type="range" min="-100" max="100" value="${E.aj[k]}" data-ed-aj="${k}"></div>`).join(''))}
      ${seccion('filtros', 'filtros', 'Filters', `<div class="ed-filtros">${FILTROS.map(([k, t]) => `<button type="button" class="ed-filtro${E.filtro === k ? ' on' : ''}" data-ed-filtro="${k}"><span class="ed-fmini" style="filter:${filtroCss({}, k) || 'none'}"></span>${t}</button>`).join('')}</div>`)}
      ${seccion('markup', 'markup', 'Markup Tools', `<div class="ed-tiles chico">${MARKUP.map(tile).join('')}</div><div class="ed-fila"><span>Line width</span><input type="range" id="edAncho" min="1" max="14" value="${E.ancho}"></div>`)}
      ${seccion('historial', 'deshacer', 'Undo &amp; Redo', `<div class="ed-sub"><button type="button" class="ed-chip" data-ed="deshacer"${E.deshacer.length ? '' : ' disabled'}>${IC('deshacer')}Undo</button><button type="button" class="ed-chip" data-ed="rehacer"${E.rehacer.length ? '' : ' disabled'}>${IC('rehacer')}Redo</button></div><p class="fv-gris">${E.marcas.length} ${E.marcas.length === 1 ? 'mark' : 'marks'} on the photo.</p>`)}
    </div>
    <p class="aviso" id="edAviso"></p>
    <div class="ed-pie"><button type="button" class="btn btn-outline" data-ed="reset">Reset</button><button type="button" class="btn btn-accent" data-ed="aplicar">Apply Changes</button></div>`;
  if(E.urlFuente) E.panel.querySelectorAll('.ed-fmini').forEach(x => { x.style.backgroundImage = 'url(' + E.urlFuente + ')'; });
}

// Pinta todo sobre la foto ORIGINAL (girada, ajustada, con sus marcas y recortada; máximo 4032 px) y devuelve el JPEG.
export async function copiaFinal(){
  const r = await fetch(E.urlOriginal || E.urlWeb); if(!r.ok) throw new Error('HTTP ' + r.status);
  const url = URL.createObjectURL(await r.blob()); const im = await cargarImg(url);
  const marco = hacerMarco(im, E.rot, 4032); const w = marco.width, h = marco.height; const ctx = marco.getContext('2d');
  calidezYNitidez(ctx, w, h, E.aj);
  const f = factores(E.aj, E.filtro);
  if(f.mult !== 1 || f.con !== 1 || f.sat !== 1){ const d = ctx.getImageData(0, 0, w, h); const a = d.data;
    for(let i = 0; i < a.length; i += 4){ const [rr, gg, bb] = ajustarRGB(a[i], a[i + 1], a[i + 2], f); a[i] = rr; a[i + 1] = gg; a[i + 2] = bb; } ctx.putImageData(d, 0, 0); }
  dibujar(ctx, w, h, E.marcas, marco);
  const cr = E.crop; const sx = Math.round(cr.x * w), sy = Math.round(cr.y * h), sw = Math.max(1, Math.round(cr.w * w)), sh = Math.max(1, Math.round(cr.h * h));
  const out = document.createElement('canvas'); out.width = sw; out.height = sh; out.getContext('2d').drawImage(marco, sx, sy, sw, sh, 0, 0, sw, sh);
  const salida = await new Promise(res => out.toBlob(res, 'image/jpeg', 0.9));
  out.width = out.height = 0; marco.width = marco.height = 0; URL.revokeObjectURL(url);
  if(!salida) throw new Error('could not create the image');
  const d = new Date(); const nombre = 'scanova-edit-' + d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0') + '-' + String(d.getHours()).padStart(2, '0') + String(d.getMinutes()).padStart(2, '0') + String(d.getSeconds()).padStart(2, '0') + '.jpg';
  return new File([salida], nombre, { type:'image/jpeg', lastModified: Date.now() });
}
// Apply Changes = guardar la foto editada como foto nueva y abrirla. Save a Copy (arriba) = guardarla y quedarse en la original.
const zonas = () => (E.tel ? [E.bandeja, E.cajaHoja] : [E.panel]).filter(Boolean);
const botonesGuardar = () => [...zonas().flatMap(z => [...z.querySelectorAll('[data-ed="aplicar"]')]), ...document.querySelectorAll('#fvTelGuardar')];
async function guardar(abrirNueva, despues){
  const av = $('#edAviso'); quitarEscritura();
  if(!hayCambios()){ if(av) av.textContent = 'Nothing to save yet: add a mark, an adjustment, a filter or a crop first.'; return false; }
  if(E.guardando) return false; E.guardando = true;
  botonesGuardar().forEach(b => { b.disabled = true; }); if(av){ av.classList.remove('ok'); av.textContent = 'Saving…'; }
  try{
    E.abierto = E.abierto === 'recorte' ? '' : E.abierto; E.sel = -1;
    const archivo = await copiaFinal(); const r = await E.guardar(archivo);
    if(av){ av.classList.add('ok'); av.textContent = r && r.repetida ? 'That copy was already saved.' : 'Saved as a new photo. The original stays as it was.'; }
    const nueva = r && r.foto; const cb = E.alGuardar;
    setTimeout(() => { cerrar(true); if(despues) despues(); else if(abrirNueva && nueva && cb) cb(nueva); }, 700);
    return true;
  }catch(e){ if(E){ E.guardando = false; } if(av) av.textContent = 'Could not save. ' + String(e && e.message || e); botonesGuardar().forEach(b => { b.disabled = false; }); return false; }
}
export const guardarCopia = (abrirNueva) => E ? guardar(abrirNueva) : null;
// Salir del editor (Back, Cancel, la X, otra foto): sin cambios sale directo; con cambios pregunta Save / Discard / Cancel.
let PENDIENTE = null;
export function salir(accion){
  if(!E){ if(accion) accion(); return; }
  quitarEscritura();
  if(!hayCambios()){ cerrar(true); if(accion) accion(); return; }
  const d = $('#fvDialogo'); if(!d){ if(confirm('Discard your changes?')){ cerrar(true); if(accion) accion(); } return; }
  PENDIENTE = accion || (() => {}); d.hidden = false;
}
function contestar(r){
  const d = $('#fvDialogo'); if(d) d.hidden = true; const accion = PENDIENTE; PENDIENTE = null; if(!E || !accion) return;
  if(r === 'guardar') guardar(false, accion);
  else if(r === 'descartar'){ cerrar(true); accion(); }
}

// ---------- el teléfono (su diseño): bandeja abajo con Text, Arrow, Shape, Marker / Crop, Rotate, Adjustments, Markup,
// y hojas que suben (Adjustments con Filters, Markup Tools con lo del agua). Encima de la bandeja, las opciones del momento.
function ponerHoja(h){ if(!E) return; E.hoja = h || ''; if(E.hoja === 'markup' && !MARKUP.some(x => x[0] === E.herr)) E.herr = 'humedad'; E.sel = -1; render(); pintarPanel(); }
const AJ_TEL = [['bri', 'Brightness', 'sol', -100, 100], ['con', 'Contrast', 'contraste', -100, 100], ['sat', 'Saturation', 'saturacion', -100, 100], ['cal', 'Warmth', 'termometro', -100, 100], ['nit', 'Sharpness', 'nitidez', 0, 100]];
function pintarTel(){
  const sel = E.sel >= 0 ? E.marcas[E.sel] : null; const est = E.estado || estadoHumedad(E.valor);
  const tile = ([k, t, ic], on, attr) => `<button type="button" class="ed-tt${on ? ' on' : ''}" ${attr}>${IC(ic)}<span>${t}</span></button>`;
  const colores = `<div class="ed-colores">${COLORES.map(c => `<button type="button" class="ed-color${E.color === c ? ' on' : ''}" data-ed-color="${c}" style="background:${c}" aria-label="Color"></button>`).join('')}</div>`;
  const chips = (lista, actual, attr) => lista.map(([k, t]) => `<button type="button" class="ed-chip${actual === k ? ' on' : ''}" ${attr}="${k}">${t}</button>`).join('');
  let opc;
  if(E.cargando) opc = '<p class="ed-tel-ayuda">Loading the photo…</p>';
  else if(E.error) opc = '<p class="aviso">' + esc(E.error) + '</p>';
  else if(enRecorte()) opc = `<div class="ed-fila-x">${chips(PROPORCIONES.map(x => [x[0], x[1]]), E.prop, 'data-ed-prop')}<button type="button" class="ed-chip" data-ed="girar-izq">${IC('girar-izq')}Left</button><button type="button" class="ed-chip" data-ed="sin-recorte">Reset</button><button type="button" class="ed-chip on" data-ed-abrir="recorte">Done</button></div>`;
  else if(sel) opc = `<div class="ed-fila-x"><span class="ed-tel-ayuda"><b>${esc(NOMBRE[sel.tipo] || 'Mark')}</b></span>${['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? '<button type="button" class="ed-chip" data-ed="editar">Edit</button>' : ''}<button type="button" class="ed-chip rojo" data-ed="borrar">Delete</button><button type="button" class="ed-chip" data-ed="soltar">Done</button></div>`;
  else if(E.herr === 'forma') opc = `<div class="ed-fila-x">${chips([['circulo', 'Circle'], ['cuadro', 'Box']], E.forma, 'data-ed-forma')}${colores}</div>`;
  else if(E.herr === 'marcador') opc = `<div class="ed-fila-x">${chips([['lapiz', 'Marker'], ['resalta', 'Highlighter']], E.marca, 'data-ed-marca')}${colores}</div>`;
  else if(E.herr === 'humedad') opc = `<div class="ed-fila-x"><span class="ed-tel-ayuda"><b>${esc(E.valor || '?')}%</b> · ${esc(E.mat)} · tap where you measured.</span><button type="button" class="ed-chip" data-ed-hoja="markup">Change</button></div>`;
  else if(['area', 'medida', 'borroso'].includes(E.herr)) opc = `<p class="ed-tel-ayuda">${esc(AYUDA[E.herr])}</p>`;
  else opc = `<div class="ed-fila-x">${colores}</div>`;   // Text y Arrow: solo los colores (se toca la foto y se escribe / se arrastra)
  E.bandeja.innerHTML = `<div class="ed-tel-opc">${opc}<div class="ed-tel-hist"><button type="button" class="ed-ic" data-ed="deshacer"${E.deshacer.length ? '' : ' disabled'} aria-label="Undo">${IC('deshacer')}</button><button type="button" class="ed-ic" data-ed="rehacer"${E.rehacer.length ? '' : ' disabled'} aria-label="Redo">${IC('rehacer')}</button></div></div>
    <p class="aviso" id="edAviso"></p>
    <div class="ed-tel-bandeja">
      ${PRINCIPALES.map(h => tile(h, E.herr === h[0] && !enRecorte(), `data-ed-herr="${h[0]}"`)).join('')}
      ${tile(['', 'Crop', 'recortar'], enRecorte(), 'data-ed-abrir="recorte"')}
      ${tile(['', 'Rotate', 'girar-der'], false, 'data-ed="girar-der"')}
      ${tile(['', 'Adjustments', 'ajustes'], E.hoja === 'ajustes' || E.hoja === 'filtros', 'data-ed-hoja="ajustes"')}
      ${tile(['', 'Markup', 'gota'], MARKUP.some(x => x[0] === E.herr) && !enRecorte(), 'data-ed-hoja="markup"')}
    </div>`;
  const H = E.cajaHoja; H.hidden = !E.hoja; if(E.velo) E.velo.hidden = !E.hoja;
  if(!E.hoja){ H.innerHTML = ''; return; }
  const cab = (t, atras) => `<div class="ed-hoja-cab">${atras ? `<button type="button" class="ed-hoja-atras" data-ed-hoja="${atras}">${IC('chev-izq')}</button>` : ''}<h2>${t}</h2><button type="button" class="ed-x" data-ed-hoja="" aria-label="Close">✕</button></div>`;
  if(E.hoja === 'ajustes') H.innerHTML = cab('Adjustments') + AJ_TEL.map(([k, t, ic, mn, mx]) => `<label class="ed-aj">${IC(ic)}<span>${t}</span><input type="range" min="${mn}" max="${mx}" value="${E.aj[k] || 0}" data-ed-aj="${k}"></label>`).join('')
    + `<button type="button" class="ed-hoja-fila" data-ed-hoja="filtros">${IC('filtros')}<span>Filters</span><small>${esc((FILTROS.find(x => x[0] === E.filtro) || FILTROS[0])[1])}</small>${IC('chev-der')}</button>
       <button type="button" class="ed-hoja-fila" data-ed="reset-aj">${IC('deshacer')}<span>Reset Adjustments</span></button>`;
  else if(E.hoja === 'filtros') H.innerHTML = cab('Filters', 'ajustes') + `<div class="ed-filtros">${FILTROS.map(([k, t]) => `<button type="button" class="ed-filtro${E.filtro === k ? ' on' : ''}" data-ed-filtro="${k}"><span class="ed-fmini" style="filter:${filtroCss({}, k) || 'none'}"></span>${t}</button>`).join('')}</div>`;
  else if(E.hoja === 'markup') H.innerHTML = cab('Markup Tools') + `<div class="ed-tiles chico">${MARKUP.map(h => `<button type="button" class="ed-t${E.herr === h[0] ? ' on' : ''}" data-ed-herr="${h[0]}">${IC(h[2])}<span>${h[1]}</span></button>`).join('')}</div>
    ${E.herr === 'humedad' ? `<div class="ed-mat">${MATERIALES.map(m => `<button type="button" class="ed-chip${E.mat === m ? ' on' : ''}" data-ed-mat="${esc(m)}">${esc(m)}</button>`).join('')}</div>
      <div class="ed-lect"><input type="number" inputmode="decimal" id="edValor" min="0" max="100" step="0.1" placeholder="28" value="${esc(E.valor)}"><span>%</span>${Object.keys(ESTADO).map(k => `<button type="button" class="ed-est ${k}${est === k ? ' on' : ''}" data-ed-est="${k}">${ESTADO[k][0]}</button>`).join('')}</div>` : `<p class="ed-tel-ayuda">${esc(AYUDA[E.herr] || '')}</p>`}
    <div class="ed-fila"><span>Line width</span><input type="range" id="edAncho" min="1" max="14" value="${E.ancho}"></div>
    <button type="button" class="btn btn-accent ed-hoja-listo" data-ed-hoja="">Done</button>`;
  if(E.urlFuente) H.querySelectorAll('.ed-fmini').forEach(x => { x.style.backgroundImage = 'url(' + E.urlFuente + ')'; });
}

export function conectar(){
  document.addEventListener('click', (e) => {
    if(!E) return; const q = (s) => e.target.closest(s); let el;
    if(q('#fvCopia')){ guardar(false); return; }
    if((el = q('[data-fv-dlg]'))){ contestar(el.dataset.fvDlg); return; }
    if(!q('#fvPanel') && !q('#edTel') && !q('#edHoja') && !q('#fvVelo')) return;
    if(q('#fvVelo')){ ponerHoja(''); return; }
    if((el = q('[data-ed-hoja]'))){ ponerHoja(el.dataset.edHoja === E.hoja && el.closest('#edTel') ? '' : el.dataset.edHoja); return; }
    if((el = q('[data-ed-herr]'))){ E.herr = el.dataset.edHerr; E.sel = -1; if(E.abierto === 'recorte'){ E.abierto = ''; colocar(); } if(E.tel && !MARKUP.some(x => x[0] === E.herr)) E.hoja = ''; render(); pintarPanel(); return; }
    if((el = q('[data-ed-forma]'))){ E.forma = el.dataset.edForma; pintarPanel(); return; }
    if((el = q('[data-ed-marca]'))){ E.marca = el.dataset.edMarca; pintarPanel(); return; }
    if((el = q('[data-ed-color]'))){ E.color = el.dataset.edColor; pintarPanel(); return; }
    if((el = q('[data-ed-mat]'))){ E.mat = el.dataset.edMat; pintarPanel(); return; }
    if((el = q('[data-ed-est]'))){ E.estado = el.dataset.edEst; E.estadoFijo = true; pintarPanel(); return; }
    if((el = q('[data-ed-filtro]'))){ E.deshacer.push(estado()); E.rehacer = []; E.filtro = el.dataset.edFiltro; render(); pintarPanel(); return; }
    if((el = q('[data-ed-prop]'))){ ponerProporcion(el.dataset.edProp); return; }
    if((el = q('[data-ed-abrir]'))){ const id = el.dataset.edAbrir; const antes = E.abierto; E.abierto = antes === id ? '' : id; E.sel = -1; if(antes === 'recorte' || E.abierto === 'recorte') colocar(); pintarPanel(); return; }
    if((el = q('[data-ed]'))){ const a = el.dataset.ed;
      if(a === 'deshacer') deshacer(); else if(a === 'rehacer') rehacer();
      else if(a === 'cerrar') salir();
      else if(a === 'borrar') borrarSel(); else if(a === 'editar') editarSel(); else if(a === 'soltar'){ E.sel = -1; render(); pintarPanel(); }
      else if(a === 'girar-izq') girar(-1); else if(a === 'girar-der') girar(1);
      else if(a === 'sin-recorte'){ E.deshacer.push(estado()); E.rehacer = []; E.crop = RECORTE_TODO(); E.prop = 'libre'; colocar(); pintarPanel(); }
      else if(a === 'reset'){ if(!hayCambios() || !confirm('Remove all marks, adjustments, filters and crop?')) return; E.deshacer.push(estado()); E.rehacer = [];
        const girado = E.rot !== 0; E.marcas = []; E.aj = { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }; E.filtro = 'original'; E.rot = 0; E.crop = RECORTE_TODO(); E.prop = 'libre'; E.sel = -1; if(girado) E.marco = hacerMarco(E.fuente, 0); colocar(); pintarPanel(); }
      else if(a === 'reset-aj'){ if(!Object.values(E.aj).some(Boolean) && E.filtro === 'original') return; E.deshacer.push(estado()); E.rehacer = []; E.aj = { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }; E.filtro = 'original'; render(); pintarPanel(); }
      else if(a === 'aplicar') guardar(true);
      return; }
  });
  document.addEventListener('input', (e) => {
    if(!E) return;
    if(e.target.id === 'edAncho'){ E.ancho = Number(e.target.value); return; }
    if(e.target.id === 'edValor'){ E.valor = e.target.value; if(!E.estadoFijo) E.estado = ''; const est = E.estado || estadoHumedad(E.valor);
      zonas().forEach(z => z.querySelectorAll('[data-ed-est]').forEach(x => x.classList.toggle('on', x.dataset.edEst === est))); return; }
    const k = e.target.dataset && e.target.dataset.edAj; if(k){ E.aj[k] = Number(e.target.value); render(); }
  });
  document.addEventListener('pointerdown', (e) => { if(E && e.target.dataset && e.target.dataset.edAj){ E.deshacer.push(estado()); E.rehacer = []; } }, true);
}
