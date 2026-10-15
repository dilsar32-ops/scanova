// Scanova · editor de fotos (diseño de Amilcar, 12 oct 2026). Al tocar "Edit Photo" el panel de la derecha pasa a ser
// "Edit Photo": arriba Text, Arrow, Shape y Marker; un cuadro de ayuda; y secciones que se abren: Crop & Rotate,
// Adjustments, Filters, Markup Tools (Moisture, Wet area, Measure, Blur, color y grosor) y Undo & Redo. Abajo Reset y
// Apply Changes. Las marcas se pueden mover, cambiar de tamaño y editar arrastrándolas.
// Nada se pinta sobre la foto hasta guardar: ahí se hace todo sobre la ORIGINAL (girada, ajustada, recortada) y se sube
// como foto NUEVA en el mismo nivel y cuarto. La original nunca se toca.

// ---------- lo puro ----------
export const PRINCIPALES = [['texto', 'Text', 'texto'], ['flecha', 'Arrow', 'flecha'], ['forma', 'Shape', 'forma'], ['marcador', 'Marker', 'lapiz']];
// Shape (su pedido, 15-oct: "solo hay dos"): las figuras que se arrastran de esquina a esquina.
export const FORMAS = [['circulo', 'Circle'], ['cuadro', 'Box'], ['redondo', 'Rounded box'], ['linea', 'Line'], ['doble', 'Double arrow'],
  ['triangulo', 'Triangle'], ['estrella', 'Star'], ['cruz', 'X'], ['palomita', 'Check']];
// Marker (15-oct): el marcador, un pincel (trazo ancho y suave) y el resaltador.
export const MARCAS = [['lapiz', 'Marker'], ['pincel', 'Brush'], ['resalta', 'Highlighter']];
// Text: con su pastilla de color o sin fondo (transparente, con un borde para que se lea sobre la foto).
// Line width (su "sí", 15-oct): junto a las herramientas que lo usan, no escondido en Markup Tools. En el teléfono son
// cuatro botones con la raya de cada grosor (una barra deslizable no cabe en la fila que se desliza).
export const GROSORES = [['fino', 'Thin', 2], ['medio', 'Medium', 5], ['grueso', 'Thick', 9], ['extra', 'Extra thick', 14]];
export const USA_GROSOR = (tipo) => ['flecha', 'lapiz', 'pincel', 'resalta', 'medida', 'circulo', 'cuadro', 'redondo', 'linea', 'doble', 'triangulo', 'estrella', 'cruz', 'palomita'].includes(tipo);
// El botón encendido es el grosor más cercano (en la computadora se puede escoger cualquier número con la barra).
export const grosorCercano = (v) => GROSORES.reduce((a, g) => Math.abs(g[2] - v) < Math.abs(a[2] - v) ? g : a)[0];
export const FONDOS = [['lleno', 'Color'], ['ninguno', 'Transparent']];
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
// Como el CSS de la vista previa: brightness() se corta en el blanco ANTES del contrast() (si no, la foto guardada salía
// con los claros más brillantes que lo que se veía).
export function ajustarPixel(v, f){ const b = Math.min(1, (v / 255) * f.mult); const x = (b - 0.5) * f.con + 0.5; return Math.max(0, Math.min(255, Math.round(x * 255))); }
export function ajustarRGB(r, g, b, f){
  r = ajustarPixel(r, f); g = ajustarPixel(g, f); b = ajustarPixel(b, f);
  if(f.sat !== 1){ const l = 0.2126 * r + 0.7152 * g + 0.0722 * b; r = l + (r - l) * f.sat; g = l + (g - l) * f.sat; b = l + (b - l) * f.sat; }
  const c = (x) => Math.max(0, Math.min(255, Math.round(x))); return [c(r), c(g), c(b)];
}
// Calidez (Warmth, -100 a 100): más rojo y menos azul, o al revés. Nitidez (Sharpness, 0 a 100): realza los bordes.
export function calidezRGB(r, g, b, cal){ const k = (cal || 0) * 0.3; const c = (x) => Math.max(0, Math.min(255, Math.round(x))); return [c(r + k), c(g + k * 0.15), c(b - k)]; }
// paso = a cuántos pixeles están los vecinos: en la foto guardada (4 veces más grande que la vista) el realce tiene que
// ser igual de ancho respecto a la foto, si no se veía fuerte en pantalla y casi nada en la foto guardada.
export function nitidez(datos, w, h, cantidad, paso){
  const k = Math.max(0, Math.min(100, cantidad || 0)) / 100; const s = Math.max(1, Math.round(paso || 1)); if(!k || w < 2 * s + 1 || h < 2 * s + 1) return datos;
  const src = new Uint8ClampedArray(datos); const fila = w * 4, dx = 4 * s, dy = fila * s;
  for(let y = s; y < h - s; y++) for(let x = s; x < w - s; x++){ const i = y * fila + x * 4;
    for(let c = 0; c < 3; c++){ const v = src[i + c]; datos[i + c] = v + k * (4 * v - src[i - dx + c] - src[i + dx + c] - src[i - dy + c] - src[i + dy + c]); } }
  return datos;
}
function calidezYNitidez(ctx, w, h, aj, paso){
  const cal = aj.cal || 0, nit = aj.nit || 0; if(!cal && !nit) return;
  const d = ctx.getImageData(0, 0, w, h); const a = d.data;
  if(cal){ const k = cal * 0.3, k2 = k * 0.15; for(let i = 0; i < a.length; i += 4){ a[i] += k; a[i + 1] += k2; a[i + 2] -= k; } }   // la misma cuenta que calidezRGB, sin crear arreglos por pixel
  if(nit) nitidez(a, w, h, nit, paso);
  ctx.putImageData(d, 0, 0);
}
// Difuminar (pixelar) un rectángulo de un lienzo tomando los pixeles de "fuente" (del mismo tamaño que el lienzo).
function pixelar(ctx, fuente, x, y, ww, hh, tam){
  x = Math.round(x); y = Math.round(y); ww = Math.round(ww); hh = Math.round(hh); if(ww <= 2 || hh <= 2) return;
  const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(ww / tam)); c.height = Math.max(1, Math.round(hh / tam));
  c.getContext('2d').drawImage(fuente, x, y, ww, hh, 0, 0, c.width, c.height);
  ctx.save(); ctx.imageSmoothingEnabled = false; ctx.drawImage(c, 0, 0, c.width, c.height, x, y, ww, hh); ctx.restore(); c.width = c.height = 0;
}
// La medida base de las marcas: el lado LARGO de la foto entre 1000 (con el ancho, al girar una foto a lo alto las marcas
// se achicaban un 25 %).
const UNIDAD = (w, h) => Math.max(w, h) / 1000;
export const tintaSobre = (hex) => { const h = String(hex).replace('#', ''); const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16); return (r * 299 + g * 587 + b * 114) / 1000 > 160 ? '#111' : '#fff'; };
// Girar 90° (sentido del reloj = +1): los puntos (de 0 a 1) y el recorte giran con la foto.
export const girarPunto = (p, sentido) => sentido > 0 ? [1 - p[1], p[0]] : [p[1], 1 - p[0]];
export const girarRecorte = (c, sentido) => sentido > 0 ? { x: 1 - (c.y + c.h), y: c.x, w: c.h, h: c.w } : { x: c.y, y: 1 - (c.x + c.w), w: c.h, h: c.w };
// La caja de una marca (en pixeles del marco w x h), para tocarla, moverla y cambiarle el tamaño.
export function cajaMarca(m, w, h){
  const u = UNIDAD(w, h), e = m.escala || 1, pts = (m.puntos || []).map(p => [p[0] * w, p[1] * h]);
  if(m.tipo === 'texto' && pts.length){ const k = u * e * TXT; const ancho = (anchoTexto(String(m.texto || '')) + 22) * k, alto = 30 * k; return { x: pts[0][0] - ancho / 2, y: pts[0][1] - alto / 2, w: ancho, h: alto }; }
  if(m.tipo === 'humedad' && pts.length){ const r = 28 * u * e; return { x: pts[0][0] - r, y: pts[0][1] - r, w: 2 * r, h: 2 * r + (m.material ? 26 * u * e : 0) }; }
  if(!pts.length) return { x:0, y:0, w:0, h:0 };
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]); const g = (m.ancho || 4) * u * (m.tipo === 'resalta' ? 4 : m.tipo === 'pincel' ? 3.2 : 1) / 2 + 4 * u;
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
// ¿El dedo cae sobre la marca? Las figuras y los trazos se tocan por su LÍNEA, no por la caja que las encierra: con la
// caja, tocar DENTRO de un círculo agarraba el círculo y no dejaba poner un texto ni dibujar ahí adentro.
const distSeg = (x, y, a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1]; const l2 = dx * dx + dy * dy; const t = l2 ? Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2)) : 0; return Math.hypot(x - (a[0] + t * dx), y - (a[1] + t * dy)); };
function distLinea(x, y, pts, cerrada){
  if(!pts.length) return Infinity; if(pts.length === 1) return Math.hypot(x - pts[0][0], y - pts[0][1]);
  let d = Infinity; for(let i = 1; i < pts.length; i++) d = Math.min(d, distSeg(x, y, pts[i - 1], pts[i]));
  if(cerrada && pts.length > 2) d = Math.min(d, distSeg(x, y, pts[pts.length - 1], pts[0])); return d;
}
function dentroPoligono(x, y, pts){ let s = false; for(let i = 0, j = pts.length - 1; i < pts.length; j = i++){ const a = pts[i], b = pts[j]; if((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) s = !s; } return s; }
// El contorno de las figuras (en pixeles del marco), con las mismas medidas con que se dibujan: [[puntos, cerrada], ...].
function contornoFigura(m, w, h){
  const pts = (m.puntos || []).map(p => [p[0] * w, p[1] * h]); if(pts.length < 2) return null;
  const [a, b] = [pts[0], pts[pts.length - 1]]; const cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2;
  let ww = Math.abs(b[0] - a[0]), hh = Math.abs(b[1] - a[1]); const q = (((m.giro || 0) % 4) + 4) % 4; if(q % 2){ const t = ww; ww = hh; hh = t; }
  const co = Math.round(Math.cos(q * Math.PI / 2)), si = Math.round(Math.sin(q * Math.PI / 2));
  const L = (lista) => lista.map(([x, y]) => [cx + x * co - y * si, cy + x * si + y * co]); const x = -ww / 2, y = -hh / 2;
  if(m.tipo === 'circulo') return [[Array.from({ length: 48 }, (_, i) => [cx + Math.cos(i / 48 * Math.PI * 2) * ww / 2, cy + Math.sin(i / 48 * Math.PI * 2) * hh / 2]), true]];
  if(m.tipo === 'cuadro' || m.tipo === 'redondo') return [[L([[x, y], [x + ww, y], [x + ww, y + hh], [x, y + hh]]), true]];
  if(m.tipo === 'triangulo') return [[L([[0, y], [x + ww, y + hh], [x, y + hh]]), true]];
  if(m.tipo === 'estrella') return [[L(Array.from({ length: 10 }, (_, i) => { const an = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? 0.42 : 1; return [Math.cos(an) * rr * ww / 2, Math.sin(an) * rr * hh / 2]; })), true]];
  if(m.tipo === 'cruz') return [[L([[x, y], [x + ww, y + hh]]), false], [L([[x + ww, y], [x, y + hh]]), false]];
  if(m.tipo === 'palomita') return [[L([[x, y + hh * 0.55], [x + ww * 0.38, y + hh], [x + ww, y]]), false]];
  return null;
}
export function tocaMarca(m, x, y, tol, w, h){
  if(!dentro(cajaMarca(m, w, h), x, y, tol)) return false;
  const t = m.tipo; if(t === 'texto' || t === 'humedad' || t === 'borroso') return true;
  const pts = (m.puntos || []).map(p => [p[0] * w, p[1] * h]); const U = UNIDAD(w, h); const g = Math.max(1, (m.ancho || 4) * U);
  const lim = tol + (t === 'resalta' ? g * 4 : t === 'pincel' ? g * 3.2 : g) / 2;
  const enPastilla = (cx, cy, txt, s) => Math.abs(x - cx) <= (anchoTexto(txt) + 22) * s / 2 + tol && Math.abs(y - cy) <= 30 * s / 2 + tol;
  // El área mojada se agarra por su orilla o su letrero, NO por dentro: adentro se ponen las lecturas de humedad.
  if(t === 'area'){ const cx = pts.reduce((a, q) => a + q[0], 0) / pts.length, cy = pts.reduce((a, q) => a + q[1], 0) / pts.length;
    return distLinea(x, y, pts, true) <= lim || enPastilla(cx, cy, m.texto || 'Wet area', U * 1.4); }
  if(t === 'lapiz' || t === 'resalta' || t === 'pincel') return distLinea(x, y, pts) <= lim;
  if(t === 'medida' && m.texto && pts.length > 1 && enPastilla((pts[0][0] + pts[pts.length - 1][0]) / 2, (pts[0][1] + pts[pts.length - 1][1]) / 2, m.texto, U * 1.4)) return true;
  if(t === 'flecha' || t === 'linea' || t === 'doble' || t === 'medida') return distLinea(x, y, [pts[0], pts[pts.length - 1]]) <= lim + g * 3;
  const c = contornoFigura(m, w, h); return c ? c.some(([l, cerrada]) => distLinea(x, y, l, cerrada) <= lim) : true;
}

// Dibuja todas las marcas sobre un contexto con el marco de w x h. fuente = el marco (para difuminar). Coordenadas de 0 a 1.
export function dibujar(ctx, w, h, marcas, fuente){
  const P = (p) => [p[0] * w, p[1] * h];
  const U = UNIDAD(w, h);
  for(const m of marcas){
    const u = U * (m.escala || 1); const g = Math.max(1, (m.ancho || 4) * U);
    ctx.save(); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = m.color; ctx.fillStyle = m.color; ctx.lineWidth = g; ctx.setLineDash([]);
    const pts = (m.puntos || []).map(P);
    if(m.tipo === 'lapiz' || m.tipo === 'resalta'){
      if(m.tipo === 'resalta'){ ctx.globalAlpha = 0.35; ctx.lineWidth = g * 4; }
      ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.stroke();
    } else if(m.tipo === 'pincel' && pts.length){
      // Pincel: trazo ancho y suavizado (curvas por los puntos medios), con el borde más suave (dos pasadas, sin
      // sombras: el difuminado de canvas no escala igual en la vista que en la foto guardada).
      const camino = () => { ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
        if(pts.length < 3){ pts.forEach(p => ctx.lineTo(p[0], p[1])); }
        else { for(let i = 1; i < pts.length - 1; i++){ const mx = (pts[i][0] + pts[i + 1][0]) / 2, my = (pts[i][1] + pts[i + 1][1]) / 2; ctx.quadraticCurveTo(pts[i][0], pts[i][1], mx, my); }
          const z = pts[pts.length - 1]; ctx.lineTo(z[0], z[1]); }
        if(pts.length === 1) ctx.lineTo(pts[0][0] + 0.01, pts[0][1]); };
      ctx.globalAlpha = 0.45; ctx.lineWidth = g * 3.2; camino(); ctx.stroke();
      ctx.globalAlpha = 1; ctx.lineWidth = g * 2.3; camino(); ctx.stroke();
    } else if(m.tipo === 'flecha' && pts.length > 1){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const ang = Math.atan2(b[1] - a[1], b[0] - a[0]); const L = Math.max(g * 6, 16 * U);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(b[0] - L * Math.cos(ang - 0.45), b[1] - L * Math.sin(ang - 0.45)); ctx.lineTo(b[0], b[1]); ctx.lineTo(b[0] - L * Math.cos(ang + 0.45), b[1] - L * Math.sin(ang + 0.45)); ctx.stroke();
    } else if((m.tipo === 'circulo' || m.tipo === 'cuadro') && pts.length > 1){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const x = Math.min(a[0], b[0]), y = Math.min(a[1], b[1]), ww = Math.abs(b[0] - a[0]), hh = Math.abs(b[1] - a[1]);
      ctx.beginPath(); if(m.tipo === 'circulo') ctx.ellipse(x + ww / 2, y + hh / 2, ww / 2, hh / 2, 0, 0, Math.PI * 2); else ctx.rect(x, y, ww, hh); ctx.stroke();
    } else if(['redondo', 'triangulo', 'estrella', 'cruz', 'palomita'].includes(m.tipo) && pts.length > 1){
      // Las figuras que no son iguales al girarlas (triángulo, palomita) giran con la foto: m.giro = cuartos de vuelta.
      const [a, b] = [pts[0], pts[pts.length - 1]]; const cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2;
      const q = (((m.giro || 0) % 4) + 4) % 4; let ww = Math.abs(b[0] - a[0]), hh = Math.abs(b[1] - a[1]); if(q % 2){ const t = ww; ww = hh; hh = t; }
      ctx.translate(cx, cy); ctx.rotate(q * Math.PI / 2); const x = -ww / 2, y = -hh / 2;
      ctx.beginPath();
      if(m.tipo === 'redondo'){ const r = Math.min(ww, hh) * 0.18; ctx.moveTo(x + r, y); ctx.arcTo(x + ww, y, x + ww, y + hh, r); ctx.arcTo(x + ww, y + hh, x, y + hh, r); ctx.arcTo(x, y + hh, x, y, r); ctx.arcTo(x, y, x + ww, y, r); ctx.closePath(); }
      else if(m.tipo === 'triangulo'){ ctx.moveTo(0, y); ctx.lineTo(x + ww, y + hh); ctx.lineTo(x, y + hh); ctx.closePath(); }
      else if(m.tipo === 'estrella'){ for(let i = 0; i < 10; i++){ const ang = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? 0.42 : 1; const px = Math.cos(ang) * rr * ww / 2, py = Math.sin(ang) * rr * hh / 2; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); } ctx.closePath(); }
      else if(m.tipo === 'cruz'){ ctx.moveTo(x, y); ctx.lineTo(x + ww, y + hh); ctx.moveTo(x + ww, y); ctx.lineTo(x, y + hh); }
      else { ctx.moveTo(x, y + hh * 0.55); ctx.lineTo(x + ww * 0.38, y + hh); ctx.lineTo(x + ww, y); }
      ctx.stroke();
    } else if((m.tipo === 'linea' || m.tipo === 'doble') && pts.length > 1){
      const [a, b] = [pts[0], pts[pts.length - 1]]; const ang = Math.atan2(b[1] - a[1], b[0] - a[0]); const L = Math.max(g * 6, 16 * U);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
      if(m.tipo === 'doble') [[b, ang], [a, ang + Math.PI]].forEach(([p, an]) => { ctx.beginPath(); ctx.moveTo(p[0] - L * Math.cos(an - 0.45), p[1] - L * Math.sin(an - 0.45)); ctx.lineTo(p[0], p[1]); ctx.lineTo(p[0] - L * Math.cos(an + 0.45), p[1] - L * Math.sin(an + 0.45)); ctx.stroke(); });
    } else if(m.tipo === 'area' && pts.length > 2){
      const uu = U;
      ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.closePath();
      ctx.fillStyle = 'rgba(10,132,255,.28)'; ctx.fill(); ctx.strokeStyle = '#0a84ff'; ctx.lineWidth = Math.max(2, 3 * uu); ctx.setLineDash([10 * uu, 7 * uu]); ctx.stroke(); ctx.setLineDash([]);
      const cx = pts.reduce((s, p) => s + p[0], 0) / pts.length, cy = pts.reduce((s, p) => s + p[1], 0) / pts.length;
      pastilla(ctx, cx, cy, m.texto || 'Wet area', '#0a84ff', '#fff', uu * 1.4);
    } else if(m.tipo === 'medida' && pts.length > 1){
      const uu = U; const [a, b] = [pts[0], pts[pts.length - 1]]; const ang = Math.atan2(b[1] - a[1], b[0] - a[0]); const t = g * 3;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      [a, b].forEach(p => { ctx.moveTo(p[0] - t * Math.sin(ang), p[1] + t * Math.cos(ang)); ctx.lineTo(p[0] + t * Math.sin(ang), p[1] - t * Math.cos(ang)); }); ctx.stroke();
      if(m.texto) pastilla(ctx, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, m.texto, 'rgba(0,0,0,.7)', '#fff', uu * 1.4);
    } else if(m.tipo === 'texto' && pts.length){
      if(m.fondo === 'ninguno') textoSuelto(ctx, pts[0][0], pts[0][1], m.texto || '', m.color, u * TXT);
      else pastilla(ctx, pts[0][0], pts[0][1], m.texto || '', m.color, tintaSobre(m.color), u * TXT);
    } else if(m.tipo === 'humedad' && pts.length){
      const [x, y] = pts[0]; const r = 28 * u; const [, col] = ESTADO[m.estado] || ESTADO.wet;
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = col; ctx.fill(); ctx.lineWidth = 4 * u; ctx.strokeStyle = '#fff'; ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.font = '800 ' + Math.round(17 * u) + 'px -apple-system, system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText((m.valor === '' || m.valor == null ? '?' : m.valor) + '%', x, y + 1 * u);
      if(m.material) pastilla(ctx, x, y + r + 16 * u, m.material, 'rgba(0,0,0,.65)', '#fff', u * 0.8);
    } else if(m.tipo === 'borroso' && pts.length > 1 && fuente){
      // fuente = la foto YA ajustada y sin marcas, del mismo tamaño que el marco (en la vista previa se difumina en el
      // lienzo de abajo, con su filtro; ver render): así el bloque sale igual en pantalla y en la foto guardada.
      const [a, b] = [pts[0], pts[pts.length - 1]];
      pixelar(ctx, fuente, Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]), Math.max(4, Math.round(U * 1000 / 90)));
    }
    ctx.restore();
  }
}
// Texto sin fondo: la letra en su color con un borde que contrasta (oscuro, o claro si la letra es oscura), del mismo
// tamaño que la pastilla para que la caja de tocarlo y la de la foto guardada sean la misma.
export const bordeDeTexto = (hex) => tintaSobre(hex) === '#fff' && luz(hex) < 70 ? 'rgba(255,255,255,.95)' : 'rgba(0,0,0,.85)';
const luz = (hex) => { const h = String(hex).replace('#', ''); return (parseInt(h.slice(0, 2), 16) * 299 + parseInt(h.slice(2, 4), 16) * 587 + parseInt(h.slice(4, 6), 16) * 114) / 1000; };
function textoSuelto(ctx, x, y, txt, color, u){
  if(!txt) return; ctx.save(); ctx.font = '800 ' + Math.round(16 * u) + 'px -apple-system, system-ui, sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round'; ctx.miterLimit = 2;
  ctx.lineWidth = Math.max(1, 3.2 * u); ctx.strokeStyle = bordeDeTexto(color); ctx.strokeText(txt, x, y + 1 * u);
  ctx.fillStyle = color; ctx.fillText(txt, x, y + 1 * u); ctx.restore();
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
// Bajar la foto de la nube SIN la copia que guardó el navegador al enseñarla: esa copia no trae el permiso (CORS) y el
// fetch falla ("Failed to fetch"). Fue lo que no dejaba editar en vivo (13 oct 2026).
export const bajar = (url) => fetch(url, { cache:'no-store' });
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
  // Nada escogido al abrir (su pedido, 15-oct): ni Text ni ninguna otra herramienta hasta que él la toque.
  const yo = E = { ...op, marcas: [], deshacer: [], rehacer: [], herr: '', forma: 'circulo', marca: 'lapiz', color: COLORES[0], ancho: 5, textoFondo: 'lleno', baseLlave: '',
        aj: { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }, filtro: 'original', rot: 0, crop: RECORTE_TODO(), prop: 'libre', abierto: '', sel: -1, hoja: '',
        mat: 'Drywall', valor: '', estado: '', estadoFijo: false, cargando: true };
  document.body.classList.add('fv-editando'); if(E.tel){ E.bandeja.hidden = false; } pintarPanel();
  document.querySelectorAll('#fvTelGuardar').forEach(b => { b.disabled = false; });   // Save de arriba (teléfono) se quedaba apagado tras el primer guardado
  try{
    const r = await bajar(op.urlWeb); if(E !== yo) return; if(!r.ok) throw new Error('HTTP ' + r.status);
    const url = URL.createObjectURL(await r.blob()); const im = await cargarImg(url);
    // Si mientras bajaba se cerró (o se abrió otra foto), esta carga ya no es de nadie: no pisa al editor nuevo.
    if(E !== yo){ URL.revokeObjectURL(url); return; }
    E.fuente = im; E.urlFuente = url; E.marco = hacerMarco(im, E.rot); E.cargando = false;
    montar(); pintarPanel(); render();
  }catch(e){ if(E === yo){ E.cargando = false; E.error = 'Could not load the photo to edit. ' + String(e && e.message || e); pintarPanel(); } }
}
export function cerrar(forzar){
  if(!E) return true;
  if(!forzar && hayCambios()){ salir(() => {}); return false; }
  const x = E; E = null; quitarEscritura(x);
  if(x.tel){ x.bandeja.hidden = true; x.bandeja.innerHTML = ''; x.cajaHoja.hidden = true; x.cajaHoja.innerHTML = ''; if(x.velo) x.velo.hidden = true; }
  if(x.base) x.base.remove(); if(x.lienzo) x.lienzo.remove(); x.img.style.visibility = '';
  if(x.urlFuente) setTimeout(() => URL.revokeObjectURL(x.urlFuente), 2000);
  window.removeEventListener('resize', colocar); document.removeEventListener('keydown', teclas); if(x.obs) x.obs.disconnect();
  if(x.raf) cancelAnimationFrame(x.raf); if(x.rafMov) cancelAnimationFrame(x.rafMov);
  document.querySelectorAll('#fvTelGuardar').forEach(b => { b.disabled = false; });
  document.body.classList.remove('fv-editando', 'ed-activo');
  if(x.alSalir) x.alSalir();
  return true;
}
const enRecorte = () => E && E.abierto === 'recorte';
const FW = () => E.marco.width, FH = () => E.marco.height;
// Lo que se ve: el recorte (o, mientras se recorta, la foto entera).
const vista = () => enRecorte() ? RECORTE_TODO() : E.crop;

function montar(){
  if(E.lienzo) return;   // nunca dos pares de lienzos encima de la foto
  const caja = E.img.parentNode;
  E.base = document.createElement('canvas'); E.base.className = 'ed-base'; E.base.getContext('2d', { willReadFrequently: true });
  E.lienzo = document.createElement('canvas'); E.lienzo.className = 'ed-lienzo';
  caja.appendChild(E.base); caja.appendChild(E.lienzo); E.img.style.visibility = 'hidden';
  colocar(); window.addEventListener('resize', colocar); document.addEventListener('keydown', teclas);
  // En el teléfono la bandeja cambia de alto (y la foto con ella) sin que cambie la ventana: los lienzos la siguen.
  if(typeof ResizeObserver !== 'undefined'){ let ultimo = ''; E.obs = new ResizeObserver(() => { const t = caja.clientWidth + 'x' + caja.clientHeight; if(t !== ultimo){ ultimo = t; colocar(); } }); E.obs.observe(caja); }
  const c = E.lienzo; let acc = null;
  const aMarco = (ev) => { const r = c.getBoundingClientRect(); const v = vista(); const px = (ev.clientX - r.left) / r.width, py = (ev.clientY - r.top) / r.height; return [v.x + px * v.w, v.y + py * v.h]; };
  const pedirRender = (extra) => { E.extraPend = extra || null; if(!E.rafMov) E.rafMov = requestAnimationFrame(() => { if(!E) return; E.rafMov = 0; render(E.extraPend); }); };   // un pintado por cuadro
  const sinPendiente = () => { if(E && E.rafMov){ cancelAnimationFrame(E.rafMov); E.rafMov = 0; } };
  c.addEventListener('pointerdown', (ev) => {
    if(!E || E.cargando) return;
    if(acc && ev.isPrimary !== false && !c.hasPointerCapture(acc.id)) acc = null;   // un toque anterior que se quedó sin terminar
    // Un dedo a la vez: el segundo dedo de un pellizco (o el botón derecho) no hace nada; antes dibujaba un zigzag
    // entre los dos dedos o soltaba lo que se estaba arrastrando.
    if(acc || ev.isPrimary === false || ev.button > 0) return;
    ev.preventDefault(); try{ c.setPointerCapture(ev.pointerId); }catch{}
    // Su reporte (13-oct): "cuando uno escribe ya no puede mover el texto". Tocar la foto para terminar de escribir
    // NO le quita el foco al cuadrito (el preventDefault de arriba lo impide), así que lo escrito se perdía y salía
    // otro cuadrito vacío: nunca quedaba un texto que arrastrar. Ahora ese toque GUARDA lo escrito, y si el dedo cae
    // sobre el texto recién puesto, ese mismo toque ya lo arrastra.
    let recienEscrito = false;
    if(E.escritura){ const f = E.escrituraListo; if(f) f(true); else quitarEscritura(); recienEscrito = true; }
    const p = aMarco(ev); const fx = p[0] * FW(), fy = p[1] * FH(); const k = c.getBoundingClientRect().width / (vista().w * FW());
    const tactil = ev.pointerType !== 'mouse'; const pad = (tactil ? 16 : 10) / k;
    const nuevo = (a) => { if(a){ a.id = ev.pointerId; a.cx = ev.clientX; a.cy = ev.clientY; } acc = a; };
    if(enRecorte()){ nuevo(empezarRecorte(p, pad)); return; }
    // ¿Tocó el asa redonda de la marca escogida (tamaño)? El asa está afuera de la esquina, así que no tapa el texto.
    if(E.sel >= 0 && E.marcas[E.sel]){ const m = E.marcas[E.sel]; const cj = cajaMarca(m, FW(), FH()); const a = asaDe(cj, k);
      if(!dentro(cj, fx, fy, 0) && Math.hypot(fx - a.x, fy - a.y) < (tactil ? 24 : 14) / k){ nuevo({ modo:'escala', ini: p, caja: cj, antes: JSON.parse(JSON.stringify(m)), movio: false, guardado: false }); return; } }
    // ¿Tocó una marca (mover)? La escogida se agarra por toda su caja (la que se ve punteada); las demás, por su línea.
    for(let i = E.marcas.length - 1; i >= 0; i--){ const mk = E.marcas[i];
      if(i === E.sel ? dentro(cajaMarca(mk, FW(), FH()), fx, fy, pad) : tocaMarca(mk, fx, fy, pad, FW(), FH())){ const ya = E.sel === i; E.sel = i;
        nuevo({ modo:'mover', ini: p, pts0: mk.puntos.map(q => q.slice()), ya, movio: false, guardado: false }); render(); pintarPanel(); return; } }
    // Tocar afuera de la marca escogida solo la suelta (no pone otra marca en el mismo toque).
    if(E.sel >= 0){ E.sel = -1; render(); pintarPanel(); return; }
    const t = herrActual(); if(!t) return;   // sin herramienta escogida, tocar la foto no hace nada
    if(t === 'texto'){ if(recienEscrito) return; nuevo({ modo:'texto', p }); return; }   // el cuadrito para escribir sale al soltar el dedo (iOS solo abre el teclado así)
    if(t === 'humedad'){ const v = String(E.valor).trim(); const lectura = { tipo:'humedad', puntos:[p], valor:v, material:E.mat === 'Other' ? '' : E.mat, estado:E.estado || estadoHumedad(v), escala:1 };
      E.estado = ''; E.estadoFijo = false;   // un WET/DRY escogido a mano vale para ESTA lectura, no para las siguientes
      agregar(lectura); return; }
    nuevo({ modo:'dibujo', k, m: { tipo:t, color:E.color, ancho:E.ancho, puntos:[p, p] } });
  });
  c.addEventListener('pointermove', (ev) => {
    if(!acc){ if(E && !E.cargando && ev.pointerType === 'mouse') ponerCursor(aMarco(ev)); return; }
    if(ev.pointerId !== acc.id) return;
    const p = aMarco(ev);
    if(acc.modo === 'recorte'){ moverRecorte(acc, p); return; }
    if(acc.modo === 'texto') return;
    if(acc.modo === 'dibujo'){ const m = acc.m;
      if(m.tipo === 'lapiz' || m.tipo === 'resalta' || m.tipo === 'pincel' || m.tipo === 'area'){
        // Un punto nuevo solo si el dedo se movió 2 px en la pantalla: el trazo sale igual y pesa mucho menos.
        const l = m.puntos[m.puntos.length - 1]; if(Math.hypot((p[0] - l[0]) * FW(), (p[1] - l[1]) * FH()) * acc.k < 2) return; m.puntos.push(p); }
      else m.puntos[1] = p;
      pedirRender(m); return; }
    const m = E.marcas[E.sel]; if(!m) return;
    // Margen para el temblor del dedo: hasta 6 px no se mueve nada (así "tocarla otra vez para editar" sí funciona en
    // el iPhone, y no se llena el Undo de pasos que no cambian nada).
    if(!acc.movio){ if(Math.hypot(ev.clientX - acc.cx, ev.clientY - acc.cy) < 6) return; acc.movio = true; }
    if(!acc.guardado){ E.deshacer.push(estado()); E.rehacer = []; acc.guardado = true; }
    if(acc.modo === 'mover'){
      // Se mueve desde donde estaba al agarrarla, y su centro no puede salir de lo que se ve (se perdía fuera de la foto).
      const v = vista(); const xs = acc.pts0.map(q => q[0]), ys = acc.pts0.map(q => q[1]);
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2, cy = (Math.min(...ys) + Math.max(...ys)) / 2;
      const dx = Math.max(v.x - cx, Math.min(v.x + v.w - cx, p[0] - acc.ini[0])), dy = Math.max(v.y - cy, Math.min(v.y + v.h - cy, p[1] - acc.ini[1]));
      m.puntos = acc.pts0.map(q => [q[0] + dx, q[1] + dy]); }
    else if(acc.modo === 'escala'){ const A = acc.antes; const px = (q, o) => Math.hypot((q[0] - o[0]) * FW(), (q[1] - o[1]) * FH());
      // Texto y lectura crecen desde su CENTRO (como se dibujan): el asa sigue al dedo. Lo demás, desde la esquina de arriba.
      if(m.tipo === 'texto' || m.tipo === 'humedad'){ const c0 = A.puntos[0]; const f = Math.max(0.2, Math.min(6, px(p, c0) / (px(acc.ini, c0) || 1e-6))); m.escala = Math.max(0.3, Math.min(8, (A.escala || 1) * f)); }
      else { const o = [acc.caja.x / FW(), acc.caja.y / FH()]; const f = Math.max(0.2, Math.min(6, px(p, o) / (px(acc.ini, o) || 1e-6))); m.puntos = A.puntos.map(q => [o[0] + (q[0] - o[0]) * f, o[1] + (q[1] - o[1]) * f]); }
    }
    pedirRender();
  });
  const fin = (ev) => {
    if(!acc || (ev && ev.pointerId !== acc.id)) return; const a = acc; acc = null; sinPendiente();
    if(a.modo === 'recorte'){ if(JSON.stringify(E.crop) !== JSON.stringify(a.antes)){ E.deshacer.push(a.estadoAntes); E.rehacer = []; } render(); pintarPanel(); return; }
    if(a.modo === 'texto'){ escribir(a.p, -1); return; }
    if(a.modo === 'dibujo'){
      // Un toque sin arrastrar (menos de 6 px en la pantalla) no deja marca.
      const m = a.m; let L = 0; for(let i = 1; i < m.puntos.length; i++) L += Math.hypot((m.puntos[i][0] - m.puntos[i - 1][0]) * FW(), (m.puntos[i][1] - m.puntos[i - 1][1]) * FH());
      if(L * a.k < 6){ render(); return; }
      if(m.tipo === 'medida') m.texto = (prompt('Measurement (e.g. 4\' 6")') || '').trim();
      if(m.tipo === 'area') m.texto = (prompt('Label for this area', 'Wet area') || '').trim() || 'Wet area';
      agregar(m); return;
    }
    // Tocar otra vez una marca escogida (sin moverla) = editar su texto.
    if(a.modo === 'mover' && !a.movio && a.ya) editarSel();
    pintarPanel(); render();
  };
  // iOS interrumpió el toque (una notificación, el gesto de la barra de inicio): se DESCARTA, no se guarda como si se
  // hubiera soltado (antes abría el cuadrito de texto o agregaba la flecha a medio dibujar).
  const cancelar = (ev) => {
    if(!acc || ev.pointerId !== acc.id) return; const a = acc; acc = null; sinPendiente();
    if(a.modo === 'recorte') E.crop = a.antes;
    else if((a.modo === 'mover' || a.modo === 'escala') && a.guardado){ volver(E.deshacer.pop()); return; }
    render(); pintarPanel();
  };
  c.addEventListener('pointerup', fin); c.addEventListener('pointercancel', cancelar); c.addEventListener('lostpointercapture', cancelar);
  // iOS: un toque que empieza en la foto NUNCA mueve la página. Probado en el iPhone (simulador): justo después de cerrar
  // el teclado, iOS tomaba el primer arrastre como desplazamiento de la página y mandaba pointercancel; el texto
  // regresaba a su lugar y se soltaba ("no se puede mover el texto"). touch-action:none solo no alcanza en ese momento.
  const sinPagina = (ev) => { if(ev.cancelable) ev.preventDefault(); };
  c.addEventListener('touchstart', sinPagina, { passive:false }); c.addEventListener('touchmove', sinPagina, { passive:false });
}
// El asa redonda para cambiar el tamaño: afuera de la esquina de abajo a la derecha (no encima del texto) y siempre dentro
// de lo que se ve. ui = pixeles de pantalla por pixel del marco.
function asaDe(cj, ui){ const v = vista(); const r = 9 / ui, off = 7 / ui;
  return { x: Math.min(cj.x + cj.w + off, (v.x + v.w) * FW() - r - 2 / ui), y: Math.min(cj.y + cj.h + off, (v.y + v.h) * FH() - r - 2 / ui), r }; }
function ponerCursor(p){
  const c = E.lienzo; if(!c) return; const fx = p[0] * FW(), fy = p[1] * FH(); const k = c.getBoundingClientRect().width / (vista().w * FW()); const pad = 10 / k;
  let cur = enRecorte() ? 'move' : E.herr ? 'crosshair' : 'default';
  if(!enRecorte()){
    if(E.sel >= 0 && E.marcas[E.sel]){ const cj = cajaMarca(E.marcas[E.sel], FW(), FH()); const a = asaDe(cj, k); if(dentro(cj, fx, fy, pad)) cur = 'move'; else if(Math.hypot(fx - a.x, fy - a.y) < 14 / k) cur = 'nwse-resize'; }
    if(cur !== 'nwse-resize' && cur !== 'move' && E.marcas.some(m => tocaMarca(m, fx, fy, pad, FW(), FH()))) cur = 'move';
  }
  if(c.style.cursor !== cur) c.style.cursor = cur;
}
// Escribir el texto DIRECTO en la foto: un cuadrito encima del lugar tocado. Enter o tocar afuera = listo; Esc = no.
function quitarEscritura(x){ const z = x || E; if(z && z.escritura){ const n = z.escritura; z.escritura = null; z.escrituraListo = null; n.remove(); } }
function escribir(p, i){
  quitarEscritura(); const c = E.lienzo; const v = vista(); const m = i >= 0 ? E.marcas[i] : null;
  const inp = document.createElement('input'); inp.type = 'text'; inp.className = 'ed-escribe'; inp.maxLength = 60; inp.placeholder = 'Type here';
  inp.setAttribute('enterkeyhint', 'done'); inp.value = m ? (m.texto || '') : '';
  const color = m ? m.color : E.color; const fondo = m ? (m.fondo || 'lleno') : E.textoFondo;
  if(fondo === 'ninguno'){ const b = bordeDeTexto(color); inp.style.background = 'rgba(0,0,0,.28)'; inp.style.borderStyle = 'dashed'; inp.style.color = color; inp.style.textShadow = `0 0 2px ${b}, 0 0 2px ${b}, 0 0 3px ${b}`; }
  else { inp.style.background = color; inp.style.color = tintaSobre(color); }
  inp.style.left = (c.offsetLeft + (p[0] - v.x) / v.w * c.clientWidth) + 'px'; inp.style.top = (c.offsetTop + (p[1] - v.y) / v.h * c.clientHeight) + 'px';
  c.parentNode.appendChild(inp); E.escritura = inp;
  let hecho = false;
  // diferir = no volver a pintar los botones en este momento: si el cuadrito se cerró porque se tocó un botón (Apply,
  // un color, una herramienta), repintar aquí borraba ese botón y el toque se perdía. Se repintan después del clic.
  const listo = (vale, diferir) => { if(hecho || !E) return; hecho = true; const t = inp.value.trim(); quitarEscritura();
    if(vale){
      if(m){ if(t && t !== m.texto){ E.deshacer.push(estado()); E.rehacer = []; m.texto = t; } }
      else if(t){ E.deshacer.push(estado()); E.rehacer = []; E.marcas.push({ tipo:'texto', color, puntos:[p], texto:t, escala:1, fondo }); E.sel = E.marcas.length - 1; }
    }
    render(); if(diferir) panelDespues(); else pintarPanel(); };
  inp.addEventListener('keydown', (e) => { if(e.key === 'Enter'){ e.preventDefault(); listo(true); } else if(e.key === 'Escape'){ e.preventDefault(); listo(false); } e.stopPropagation(); });
  inp.addEventListener('blur', () => listo(true, true));
  E.escrituraListo = listo;
  inp.focus();
}
function panelDespues(){
  const yo = E; let hecho = false;
  const f = () => { if(hecho) return; hecho = true; clearTimeout(t); document.removeEventListener('click', f); if(E && E === yo) pintarPanel(); };
  const t = setTimeout(f, 450); document.addEventListener('click', f);
}
// Terminar lo que se está escribiendo (guardándolo) antes de otra acción: Apply, salir, cambiar de herramienta.
function terminarEscritura(diferir){ if(E && E.escritura){ const f = E.escrituraListo; if(f) f(true, diferir); else quitarEscritura(); } }
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
  if(!E) return; const a = document.activeElement;
  if(a && (a.isContentEditable || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT' || (a.tagName === 'INPUT' && !['range', 'button', 'checkbox', 'radio'].includes(a.type)))) return;
  if((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z'){ e.preventDefault(); e.shiftKey ? rehacer() : deshacer(); }
  else if((e.key === 'Delete' || e.key === 'Backspace') && E.sel >= 0){ e.preventDefault(); borrarSel(); }
}

// ---------- recortar ----------
function empezarRecorte(p, pad){
  const c = E.crop; const esq = [[c.x, c.y], [c.x + c.w, c.y], [c.x, c.y + c.h], [c.x + c.w, c.y + c.h]];
  const tolX = pad * 2 / FW(), tolY = pad * 2 / FH();
  const i = esq.findIndex(q => Math.abs(q[0] - p[0]) < tolX && Math.abs(q[1] - p[1]) < tolY);
  if(i >= 0) return { modo:'recorte', esquina:i, ini:p, antes:{ ...c }, estadoAntes: estado() };
  if(p[0] > c.x && p[0] < c.x + c.w && p[1] > c.y && p[1] < c.y + c.h) return { modo:'recorte', esquina:-1, ini:p, antes:{ ...c }, estadoAntes: estado() };
  return null;
}
function proporcion(){ const pr = PROPORCIONES.find(x => x[0] === E.prop) || PROPORCIONES[0]; return pr[2] === -1 ? FW() / FH() : pr[2]; }
function moverRecorte(a, p){
  const c = { ...a.antes }; const dx = p[0] - a.ini[0], dy = p[1] - a.ini[1]; const MIN = 0.06;
  if(a.esquina < 0){ c.x = Math.max(0, Math.min(1 - c.w, c.x + dx)); c.y = Math.max(0, Math.min(1 - c.h, c.y + dy)); }
  else {
    const r = proporcion(); const izq = a.esquina === 0 || a.esquina === 2, arriba = a.esquina === 0 || a.esquina === 1;
    if(r > 0){
      // Proporción fija (4:3, 16:9, Square, Original): la esquina de enfrente se queda quieta y el recorte crece hasta lo
      // más grande que cabe, SIN romper la proporción al llegar a la orilla.
      const ax = izq ? a.antes.x + a.antes.w : a.antes.x, ay = arriba ? a.antes.y + a.antes.h : a.antes.y;
      const aW = (wn) => wn * FW() / (r * FH());   // alto (normalizado) que le toca a un ancho
      let w = Math.max(izq ? ax - p[0] : p[0] - ax, (arriba ? ay - p[1] : p[1] - ay) * FH() * r / FW());
      const wMax = Math.min(izq ? ax : 1 - ax, (arriba ? ay : 1 - ay) * FH() * r / FW());
      w = Math.min(wMax, Math.max(w, MIN, MIN * FH() * r / FW())); const h = aW(w);
      c.x = izq ? ax - w : ax; c.y = arriba ? ay - h : ay; c.w = w; c.h = h;
    } else {
      let x0 = c.x, y0 = c.y, x1 = c.x + c.w, y1 = c.y + c.h;
      if(izq) x0 = Math.min(x1 - MIN, Math.max(0, x0 + dx)); else x1 = Math.max(x0 + MIN, Math.min(1, x1 + dx));
      if(arriba) y0 = Math.min(y1 - MIN, Math.max(0, y0 + dy)); else y1 = Math.max(y0 + MIN, Math.min(1, y1 + dy));
      c.x = x0; c.y = y0; c.w = x1 - x0; c.h = y1 - y0;
    }
  }
  E.crop = c; render();
}
function ponerProporcion(id){
  if(!E.marco) return; E.prop = id; const r = proporcion(); if(r <= 0){ pintarPanel(); return; }
  E.deshacer.push(estado()); E.rehacer = [];
  let w = 1, h = (FW() / r) / FH(); if(h > 1){ h = 1; w = (FH() * r) / FW(); }
  E.crop = { x: (1 - w) / 2, y: (1 - h) / 2, w, h }; colocar(); pintarPanel();
}
const GIRAN = ['triangulo', 'estrella', 'palomita'];
function girar(sentido){
  if(!E.marco) return; E.deshacer.push(estado()); E.rehacer = [];
  if(E.prop === '43' || E.prop === '169') E.prop = 'libre';   // un 16:9 girado ya es 9:16: no seguir diciendo 16:9
  E.rot = (E.rot + (sentido > 0 ? 90 : 270)) % 360; E.marco = hacerMarco(E.fuente, E.rot);
  E.marcas.forEach(m => { m.puntos = m.puntos.map(p => girarPunto(p, sentido)); if(GIRAN.includes(m.tipo)) m.giro = (m.giro || 0) + (sentido > 0 ? 1 : -1); });
  E.crop = girarRecorte(E.crop, sentido); colocar(); pintarPanel();
}

// ---------- pintar ----------
// Los dos lienzos van justo encima de la parte de la caja donde cabe la foto (o el recorte).
function colocar(){
  if(!E) return;
  // ¿Pasó de teléfono a computadora o al revés (un iPad que se gira, una ventana que se angosta)? Las herramientas se
  // cambian de lugar en vez de desaparecer.
  const tel = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(max-width: 899px)').matches : !!E.tel;
  if(tel !== !!E.tel && E.bandeja){ E.tel = tel; E.bandeja.hidden = !tel; if(!tel){ E.hoja = ''; if(E.cajaHoja){ E.cajaHoja.hidden = true; E.cajaHoja.innerHTML = ''; } if(E.velo) E.velo.hidden = true; } pintarPanel(); }
  if(!E.lienzo) return; const img = E.img; const v = vista();
  const cw = img.clientWidth, ch = img.clientHeight; const aw = v.w * FW(), ah = v.h * FH();
  const k = Math.min(cw / aw, ch / ah); const w = aw * k, h = ah * k; const dpr = Math.min(2, window.devicePixelRatio || 1);
  E.baseLlave = '';
  [E.base, E.lienzo].forEach(c => { c.style.left = (img.offsetLeft + (cw - w) / 2) + 'px'; c.style.top = (img.offsetTop + (ch - h) / 2) + 'px'; c.style.width = w + 'px'; c.style.height = h + 'px'; c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); });
  render();
}
function render(extra){
  if(!E || !E.lienzo) return; const v = vista(); const b = E.base, c = E.lienzo;
  // La foto de abajo se vuelve a pintar solo cuando cambia (recorte, giro, calidez, nitidez, tamaño). Antes se pintaba
  // (y se recorría pixel por pixel con calidez/nitidez) con CADA movimiento del dedo al dibujar o mover una marca.
  // Lo difuminado (Blur) se pinta en la foto de abajo, desde la foto ya ajustada y con su filtro: igual que en la guardada.
  const todas = extra ? E.marcas.concat([extra]) : E.marcas; const blurs = todas.filter(m => m.tipo === 'borroso');
  const llave = [v.x, v.y, v.w, v.h, b.width, b.height, E.aj.cal || 0, E.aj.nit || 0, JSON.stringify(blurs.map(m => m.puntos))].join('|');
  if(llave !== E.baseLlave || E.baseMarco !== E.marco){ E.baseLlave = llave; E.baseMarco = E.marco;
    const bx = b.getContext('2d'); bx.clearRect(0, 0, b.width, b.height);
    bx.drawImage(E.marco, v.x * FW(), v.y * FH(), v.w * FW(), v.h * FH(), 0, 0, b.width, b.height);
    calidezYNitidez(bx, b.width, b.height, E.aj, 1);
    if(blurs.length){ const kb = b.width / (v.w * FW()); const tam = Math.max(3, Math.round(Math.max(FW(), FH()) / 90 * kb));
      blurs.forEach(m => { const [p0, p1] = [m.puntos[0], m.puntos[m.puntos.length - 1]]; if(!p0 || !p1) return;
        pixelar(bx, b, (Math.min(p0[0], p1[0]) - v.x) * FW() * kb, (Math.min(p0[1], p1[1]) - v.y) * FH() * kb, Math.abs(p1[0] - p0[0]) * FW() * kb, Math.abs(p1[1] - p0[1]) * FH() * kb, tam); }); } }
  const fc = filtroCss(E.aj, E.filtro); if(b.style.filter !== fc) b.style.filter = fc;
  const ctx = c.getContext('2d'); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, c.width, c.height);
  const k = c.width / (v.w * FW()); ctx.setTransform(k, 0, 0, k, -v.x * FW() * k, -v.y * FH() * k);
  dibujar(ctx, FW(), FH(), todas, null);
  // Las rayitas de la selección y del recorte, en pixeles de PANTALLA (k cuenta los del aparato: en el iPhone el asa
  // salía de 7 px).
  const ui = c.clientWidth / (v.w * FW());
  if(E.sel >= 0 && E.marcas[E.sel] && !enRecorte()){ const cj = cajaMarca(E.marcas[E.sel], FW(), FH()); const a = asaDe(cj, ui);
    ctx.save(); ctx.lineWidth = 1.5 / ui; ctx.strokeStyle = '#0a84ff'; ctx.setLineDash([6 / ui, 4 / ui]); ctx.strokeRect(cj.x, cj.y, cj.w, cj.h); ctx.setLineDash([]);
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#0a84ff'; ctx.lineWidth = 2.5 / ui; ctx.beginPath(); ctx.arc(a.x, a.y, a.r, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); ctx.restore(); }
  if(enRecorte()){ const cr = E.crop; const X = cr.x * FW(), Y = cr.y * FH(), W = cr.w * FW(), H = cr.h * FH();
    ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.beginPath(); ctx.rect(0, 0, FW(), FH()); ctx.rect(X, Y, W, H); ctx.fill('evenodd');
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 2 / ui; ctx.strokeRect(X, Y, W, H); ctx.lineWidth = 1 / ui; ctx.strokeStyle = 'rgba(255,255,255,.5)';
    for(let i = 1; i < 3; i++){ ctx.beginPath(); ctx.moveTo(X + W * i / 3, Y); ctx.lineTo(X + W * i / 3, Y + H); ctx.moveTo(X, Y + H * i / 3); ctx.lineTo(X + W, Y + H * i / 3); ctx.stroke(); }
    ctx.lineWidth = 4 / ui; ctx.strokeStyle = '#fff'; const L = 20 / ui;
    [[X, Y, 1, 1], [X + W, Y, -1, 1], [X, Y + H, 1, -1], [X + W, Y + H, -1, -1]].forEach(([x, y, sx, sy]) => { ctx.beginPath(); ctx.moveTo(x + L * sx, y); ctx.lineTo(x, y); ctx.lineTo(x, y + L * sy); ctx.stroke(); });
    ctx.restore(); }
}
function estado(){ return { marcas: JSON.parse(JSON.stringify(E.marcas)), aj: { ...E.aj }, filtro: E.filtro, rot: E.rot, crop: { ...E.crop } }; }
function volver(s){ const girado = s.rot !== E.rot; E.marcas = s.marcas; E.aj = s.aj; E.filtro = s.filtro; E.rot = s.rot; E.crop = s.crop; E.sel = -1; if(girado) E.marco = hacerMarco(E.fuente, E.rot); colocar(); pintarPanel(); }
function agregar(m){ E.deshacer.push(estado()); E.rehacer = []; E.marcas.push(m); render(); pintarPanel(); }
function deshacer(){ if(!E.deshacer.length) return; E.rehacer.push(estado()); volver(E.deshacer.pop()); }
function rehacer(){ if(!E.rehacer.length) return; E.deshacer.push(estado()); volver(E.rehacer.pop()); }

const AYUDA = { '':'Pick a tool above: Text, Arrow, Shape or Marker. To move something you already added, drag it on the photo.',
  texto:'Click anywhere on the photo to add text. Then drag to move, resize, or edit.', flecha:'Drag from where the arrow starts to where it points.',
  forma:'Pick a shape, then drag on the photo to draw it.', marcador:'Draw freely on the photo.', humedad:'Write the reading, then tap where you measured.',
  area:'Draw around the wet area with your finger.', medida:'Drag along what you measured, then write the measurement.', borroso:'Drag over what you want to hide (faces, papers, house numbers).' };
const NOMBRE = { texto:'Text', flecha:'Arrow', circulo:'Circle', cuadro:'Box', redondo:'Rounded box', linea:'Line', doble:'Double arrow', triangulo:'Triangle', estrella:'Star', cruz:'X', palomita:'Check',
  lapiz:'Marker', pincel:'Brush', resalta:'Highlight', humedad:'Moisture reading', area:'Wet area', medida:'Measurement', borroso:'Blur' };
// Dibujitos de las figuras y los marcadores para los botones (no hay iconos de ellos en la página).
const FIG = { circulo:'<ellipse cx="8" cy="8" rx="6.2" ry="5.2"/>', cuadro:'<rect x="2" y="3" width="12" height="10"/>', redondo:'<rect x="2" y="3" width="12" height="10" rx="3.2"/>',
  linea:'<path d="M2.5 13.5L13.5 2.5"/>', doble:'<path d="M2.5 13.5L13.5 2.5M8.5 2.5h5v5M2.5 8.5v5h5"/>', triangulo:'<path d="M8 2.2L14 13.5H2z"/>',
  estrella:'<path d="M8 1.6l1.9 4.2 4.5.4-3.4 3 1 4.4L8 11.3l-4 2.3 1-4.4-3.4-3 4.5-.4z"/>', cruz:'<path d="M3 3l10 10M13 3L3 13"/>', palomita:'<path d="M2.2 8.6l4 4L13.8 3.4"/>',
  lapiz:'<path d="M2 12.5C5 7 8.5 6 14 4"/>', pincel:'<path d="M2.5 12C5 7.5 8.5 6.5 13.5 4.5" style="stroke-width:3.6"/>', resalta:'<path d="M2.5 9.5h11" style="stroke-width:5.5;opacity:.45"/>',
  fino:'<path d="M2.5 8h11" style="stroke-width:1.2"/>', medio:'<path d="M2.5 8h11" style="stroke-width:2.4"/>', grueso:'<path d="M2.5 8h11" style="stroke-width:3.8"/>', extra:'<path d="M2.5 8h11" style="stroke-width:5.6"/>',
  lleno:'<rect x="1.5" y="4.5" width="13" height="7" rx="3.5" style="fill:currentColor;stroke:none"/>', ninguno:'<rect x="1.5" y="4.5" width="13" height="7" rx="3.5" style="stroke-dasharray:2 1.6"/>' };
const figura = (k) => `<svg class="ed-fig" viewBox="0 0 16 16" aria-hidden="true">${FIG[k] || ''}</svg>`;
// Las marcas que tienen color propio (se les puede cambiar escogiéndolas y tocando otro color).
const CON_COLOR = (m) => !!m && !['area', 'humedad', 'borroso'].includes(m.tipo);
// La barra de Line width (computadora) y los cuatro grosores (teléfono). Con una marca escogida muestran SU grosor.
const filaGrosor = (v) => `<div class="ed-fila ed-grosor"><span>Line width</span><input type="range" id="edAncho" min="1" max="14" value="${Math.round(v || 4)}"></div>`;
const chipsGrosor = (v) => { const on = grosorCercano(v || 4); return GROSORES.map(([k, t, n]) => `<button type="button" class="ed-chip solo${on === k ? ' on' : ''}" data-ed-grosor="${n}" aria-label="${t}" title="${t}">${figura(k)}</button>`).join(''); };
const chipFondo = (actual, corto) => `<button type="button" class="ed-chip${actual === 'ninguno' ? ' on' : ''}" data-ed-fondo="1" aria-pressed="${actual === 'ninguno'}">${figura('ninguno')}${corto ? 'Transparent' : 'Transparent background'}</button>`;
function seccion(id, icono, titulo, cuerpo){
  const ab = E.abierto === id;
  return `<div class="ed-acc${ab ? ' abierto' : ''}"><button type="button" class="ed-acc-t" data-ed-abrir="${id}">${IC(icono)}<span>${titulo}</span>${IC('chev')}</button>${ab ? '<div class="ed-acc-c">' + cuerpo + '</div>' : ''}</div>`;
}
function pintarPanel(){
  if(!E) return; if(E.lienzo && !E.cargando) E.lienzo.style.cursor = enRecorte() ? 'move' : E.herr ? 'crosshair' : 'default';
  // Con una herramienta escogida (o una marca), las flechas de cambiar foto del teléfono no se comen los toques de la orilla.
  document.body.classList.toggle('ed-activo', !!(E.herr || E.sel >= 0 || enRecorte()));
  if(E.tel) return pintarTel(); const p = E.panel;
  const est = E.estado || estadoHumedad(E.valor); const sel = E.sel >= 0 ? E.marcas[E.sel] : null;
  const tile = ([k, t, ic]) => `<button type="button" class="ed-t${E.herr === k ? ' on' : ''}" data-ed-herr="${k}">${IC(ic)}<span>${t}</span></button>`;
  const colorDe = (actual) => `<div class="ed-colores">${COLORES.map(c => `<button type="button" class="ed-color${actual === c ? ' on' : ''}" data-ed-color="${c}" style="background:${c}" aria-label="Color"></button>`).join('')}</div>`;
  const colores = colorDe(E.color);
  const opciones = E.herr === 'forma' ? `<div class="ed-sub">${FORMAS.map(([k, t]) => `<button type="button" class="ed-chip${E.forma === k ? ' on' : ''}" data-ed-forma="${k}">${figura(k)}${t}</button>`).join('')}</div>`
    : E.herr === 'marcador' ? `<div class="ed-sub">${MARCAS.map(([k, t]) => `<button type="button" class="ed-chip${E.marca === k ? ' on' : ''}" data-ed-marca="${k}">${figura(k)}${t}</button>`).join('')}</div>`
    : E.herr === 'texto' ? `<div class="ed-sub">${chipFondo(E.textoFondo)}</div>`
    : E.herr === 'humedad' ? `<div class="ed-mat">${MATERIALES.map(m => `<button type="button" class="ed-chip${E.mat === m ? ' on' : ''}" data-ed-mat="${esc(m)}">${esc(m)}</button>`).join('')}</div>
        <div class="ed-lect"><input type="number" inputmode="decimal" id="edValor" min="0" max="100" step="0.1" placeholder="28" value="${esc(E.valor)}"><span>%</span>${Object.keys(ESTADO).map(k => `<button type="button" class="ed-est ${k}${est === k ? ' on' : ''}" data-ed-est="${k}">${ESTADO[k][0]}</button>`).join('')}</div>` : '';
  const conColor = !!E.herr && !['humedad', 'area', 'borroso'].includes(E.herr);
  const ayuda = enRecorte() ? 'Drag the corners to crop, or drag inside to move the frame. Close "Crop & Rotate" when you are done.'
    : sel ? 'Selected: ' + (NOMBRE[sel.tipo] || 'mark') + '. Drag to move it, drag the round corner to resize' + (['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? ', tap it again to edit' : '') + '.' : (AYUDA[E.herr] || AYUDA['']);
  p.innerHTML = `<div class="ed-cab"><h2 class="fv-h">Edit Photo</h2><button type="button" class="ed-x" data-ed="cerrar" aria-label="Close editor">✕</button></div>
    ${E.cargando ? '<p class="fv-gris">Loading the photo…</p>' : ''}${E.error ? '<p class="aviso">' + esc(E.error) + '</p>' : ''}
    <div class="ed-tiles">${PRINCIPALES.map(tile).join('')}</div>
    <div class="ed-info">${IC('info')}<div><p>${esc(ayuda)}</p>
      ${sel && !enRecorte() ? `<div class="ed-sub">${['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? '<button type="button" class="ed-chip" data-ed="editar">Edit</button>' : ''}${sel.tipo === 'texto' ? chipFondo(sel.fondo) : ''}<button type="button" class="ed-chip rojo" data-ed="borrar">Delete</button><button type="button" class="ed-chip" data-ed="soltar">Done</button></div>${CON_COLOR(sel) ? colorDe(sel.color) : ''}${USA_GROSOR(sel.tipo) ? filaGrosor(sel.ancho) : ''}` : ''}
      ${!sel && !enRecorte() ? opciones + (conColor ? colores : '') + (E.herr && USA_GROSOR(herrActual()) ? filaGrosor(E.ancho) : '') : ''}</div></div>
    <div class="ed-accs">
      ${seccion('recorte', 'recortar', 'Crop &amp; Rotate', `<div class="ed-sub">${PROPORCIONES.map(([k, t]) => `<button type="button" class="ed-chip${E.prop === k ? ' on' : ''}" data-ed-prop="${k}">${t}</button>`).join('')}</div>
        <div class="ed-sub"><button type="button" class="ed-chip" data-ed="girar-izq">${IC('girar-izq')}Rotate left</button><button type="button" class="ed-chip" data-ed="girar-der">${IC('girar-der')}Rotate right</button><button type="button" class="ed-chip" data-ed="sin-recorte">Reset crop</button></div>`)}
      ${seccion('ajustes', 'ajustes', 'Adjustments', [['exp', 'Exposure'], ['bri', 'Brightness'], ['con', 'Contrast'], ['sat', 'Saturation']].map(([k, t]) => `<div class="ed-fila"><span>${t}</span><input type="range" min="-100" max="100" value="${E.aj[k]}" data-ed-aj="${k}"></div>`).join(''))}
      ${seccion('filtros', 'filtros', 'Filters', `<div class="ed-filtros">${FILTROS.map(([k, t]) => `<button type="button" class="ed-filtro${E.filtro === k ? ' on' : ''}" data-ed-filtro="${k}"><span class="ed-fmini" style="filter:${filtroCss({}, k) || 'none'}"></span>${t}</button>`).join('')}</div>`)}
      ${seccion('markup', 'markup', 'Markup Tools', `<div class="ed-tiles chico">${MARKUP.map(tile).join('')}</div>`)}
      ${seccion('historial', 'deshacer', 'Undo &amp; Redo', `<div class="ed-sub"><button type="button" class="ed-chip" data-ed="deshacer"${E.deshacer.length ? '' : ' disabled'}>${IC('deshacer')}Undo</button><button type="button" class="ed-chip" data-ed="rehacer"${E.rehacer.length ? '' : ' disabled'}>${IC('rehacer')}Redo</button></div><p class="fv-gris">${E.marcas.length} ${E.marcas.length === 1 ? 'mark' : 'marks'} on the photo.</p>`)}
    </div>
    <p class="aviso" id="edAviso"></p>
    <div class="ed-pie"><button type="button" class="btn btn-outline" data-ed="reset">Reset</button><button type="button" class="btn btn-accent" data-ed="aplicar">Apply Changes</button></div>`;
  if(E.urlFuente) E.panel.querySelectorAll('.ed-fmini').forEach(x => { x.style.backgroundImage = 'url(' + E.urlFuente + ')'; });
}

// Pinta todo sobre la foto ORIGINAL (girada, ajustada, con sus marcas y recortada; máximo 4032 px) y devuelve el JPEG.
export async function copiaFinal(z = E){
  // La ORIGINAL (máxima calidad); si no se puede leer (formato raro o red), la de 1600 px, para no quedarse sin guardar.
  let url, im;
  if(!z.urlOriginal && z.firmarOriginal){ try{ z.urlOriginal = await z.firmarOriginal(); }catch(e){ console.warn('firmar original', e); } }
  for(const fuente of [z.urlOriginal, z.urlWeb].filter(Boolean)){
    try{ const r = await bajar(fuente); if(!r.ok) throw new Error('HTTP ' + r.status); url = URL.createObjectURL(await r.blob()); im = await cargarImg(url); break; }
    catch(e){ if(url){ URL.revokeObjectURL(url); url = null; } if(fuente === z.urlWeb || !z.urlWeb) throw e; }
  }
  const marco = hacerMarco(im, z.rot, 4032); const w = marco.width, h = marco.height; const ctx = marco.getContext('2d', { willReadFrequently: true });
  // Sharpness con el mismo ancho que en la vista previa (ahí un pixel de pantalla son varios de la foto grande).
  const vb = z.base && z.base.width ? z.base.width / (z.crop.w || 1) : 0; const paso = vb ? Math.max(1, Math.round(w / vb)) : 1;
  calidezYNitidez(ctx, w, h, z.aj, paso);
  const f = factores(z.aj, z.filtro);
  if(f.mult !== 1 || f.con !== 1 || f.sat !== 1){ const d = ctx.getImageData(0, 0, w, h); const a = d.data;
    // Brillo y contraste por tabla (256 valores) en vez de una cuenta y un arreglo nuevo por cada pixel.
    const tabla = new Uint8ClampedArray(256); for(let v = 0; v < 256; v++) tabla[v] = ajustarPixel(v, f); const s = f.sat;
    for(let i = 0; i < a.length; i += 4){ let r = tabla[a[i]], g = tabla[a[i + 1]], b = tabla[a[i + 2]];
      if(s !== 1){ const l = 0.2126 * r + 0.7152 * g + 0.0722 * b; r = l + (r - l) * s; g = l + (g - l) * s; b = l + (b - l) * s; }
      a[i] = r; a[i + 1] = g; a[i + 2] = b; }
    ctx.putImageData(d, 0, 0); }
  // Primero lo difuminado (desde la foto ajustada SIN marcas), después las marcas encima: igual que en la vista previa.
  const blurs = z.marcas.filter(m => m.tipo === 'borroso'), resto = z.marcas.filter(m => m.tipo !== 'borroso');
  if(blurs.length){ const limpio = document.createElement('canvas'); limpio.width = w; limpio.height = h; limpio.getContext('2d').drawImage(marco, 0, 0); dibujar(ctx, w, h, blurs, limpio); limpio.width = limpio.height = 0; }
  dibujar(ctx, w, h, resto, null);
  const cr = z.crop; const sx = Math.round(cr.x * w), sy = Math.round(cr.y * h), sw = Math.max(1, Math.round(cr.w * w)), sh = Math.max(1, Math.round(cr.h * h));
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
  if(!E) return false; terminarEscritura();   // lo que estaba escribiendo se guarda (antes se borraba)
  const yo = E; const av = $('#edAviso');
  if(!hayCambios()){ if(av) av.textContent = 'Nothing to save yet: add a mark, an adjustment, a filter or a crop first.'; return false; }
  if(yo.guardando || !yo.marco) return false; yo.guardando = true;
  if(yo.abierto === 'recorte'){ yo.abierto = ''; colocar(); }   // con Crop abierto, la vista se quedaba estirada si fallaba
  yo.sel = -1; pintarPanel(); render();
  botonesGuardar().forEach(b => { b.disabled = true; }); const av2 = $('#edAviso'); if(av2){ av2.classList.remove('ok'); av2.textContent = 'Saving…'; }
  try{
    // Todo con "yo", no con el editor de ese momento: si cambiara a mitad, no se sube la foto equivocada.
    const archivo = await copiaFinal(yo); const r = await yo.guardar(archivo);
    const av3 = E === yo ? $('#edAviso') : null; if(av3){ av3.classList.add('ok'); av3.textContent = r && r.repetida ? 'That copy was already saved.' : 'Saved as a new photo. The original stays as it was.'; }
    const nueva = r && r.foto; const cb = yo.alGuardar;
    setTimeout(() => { if(E === yo) cerrar(true); if(despues) despues(); else if(abrirNueva && nueva && cb) cb(nueva); }, 700);
    return true;
  }catch(e){ yo.guardando = false; if(E !== yo) return false; const av4 = $('#edAviso'); if(av4) av4.textContent = 'Could not save. ' + String(e && e.message || e); botonesGuardar().forEach(b => { b.disabled = false; }); return false; }
}
export const guardarCopia = (abrirNueva) => E ? guardar(abrirNueva) : null;
// ¿Hay algo hecho en el editor que se perdería? (para no salir de la pantalla sin preguntar)
export const sinGuardar = () => !!E && !!(hayCambios() || E.escritura);
// Salir del editor (Back, Cancel, la X, otra foto): sin cambios sale directo; con cambios pregunta Save / Discard / Cancel.
let PENDIENTE = null;
export function salir(accion){
  if(!E){ if(accion) accion(); return; }
  // Mientras guarda no se sale (antes se subía la foto equivocada y se cerraba el editor de la siguiente).
  if(E.guardando){ const av = $('#edAviso'); if(av){ av.classList.remove('ok'); av.textContent = 'Saving… one moment.'; } return; }
  terminarEscritura();
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
function ponerHoja(h){ if(!E) return; E.hoja = h || ''; E.sel = -1; render(); pintarPanel(); }   // abrir Markup ya no escoge Moisture solo
const AJ_TEL = [['bri', 'Brightness', 'sol', -100, 100], ['con', 'Contrast', 'contraste', -100, 100], ['sat', 'Saturation', 'saturacion', -100, 100], ['cal', 'Warmth', 'termometro', -100, 100], ['nit', 'Sharpness', 'nitidez', 0, 100]];
function pintarTel(){
  const sel = E.sel >= 0 ? E.marcas[E.sel] : null; const est = E.estado || estadoHumedad(E.valor);
  const tile = ([k, t, ic], on, attr) => `<button type="button" class="ed-tt${on ? ' on' : ''}" ${attr}>${IC(ic)}<span>${t}</span></button>`;
  const colorDe = (actual) => `<div class="ed-colores">${COLORES.map(c => `<button type="button" class="ed-color${actual === c ? ' on' : ''}" data-ed-color="${c}" style="background:${c}" aria-label="Color"></button>`).join('')}</div>`;
  const colores = colorDe(E.color);
  const chips = (lista, actual, attr) => lista.map(([k, t]) => `<button type="button" class="ed-chip${actual === k ? ' on' : ''}" ${attr}="${k}">${t}</button>`).join('');
  let opc;
  if(E.cargando) opc = '<p class="ed-tel-ayuda">Loading the photo…</p>';
  else if(E.error) opc = '<p class="aviso">' + esc(E.error) + '</p>';
  else if(enRecorte()) opc = `<div class="ed-fila-x">${chips(PROPORCIONES.map(x => [x[0], x[1]]), E.prop, 'data-ed-prop')}<button type="button" class="ed-chip" data-ed="girar-izq">${IC('girar-izq')}Left</button><button type="button" class="ed-chip" data-ed="sin-recorte">Reset</button><button type="button" class="ed-chip on" data-ed-abrir="recorte">Done</button></div>`;
  else if(sel) opc = `<div class="ed-fila-x"><span class="ed-tel-ayuda"><b>${esc(NOMBRE[sel.tipo] || 'Mark')}</b></span>${['texto', 'medida', 'area', 'humedad'].includes(sel.tipo) ? '<button type="button" class="ed-chip" data-ed="editar">Edit</button>' : ''}${sel.tipo === 'texto' ? chipFondo(sel.fondo, true) : ''}<button type="button" class="ed-chip rojo" data-ed="borrar">Delete</button><button type="button" class="ed-chip" data-ed="soltar">Done</button>${CON_COLOR(sel) ? colorDe(sel.color) : ''}${USA_GROSOR(sel.tipo) ? chipsGrosor(sel.ancho) : ''}</div>`;
  else if(!E.herr) opc = '<p class="ed-tel-ayuda">Pick a tool below, or drag a mark to move it.</p>';
  else if(E.herr === 'forma') opc = `<div class="ed-fila-x">${FORMAS.map(([k, t]) => `<button type="button" class="ed-chip solo${E.forma === k ? ' on' : ''}" data-ed-forma="${k}" aria-label="${t}" title="${t}">${figura(k)}</button>`).join('')}${colores}${chipsGrosor(E.ancho)}</div>`;
  else if(E.herr === 'marcador') opc = `<div class="ed-fila-x">${MARCAS.map(([k, t]) => `<button type="button" class="ed-chip${E.marca === k ? ' on' : ''}" data-ed-marca="${k}">${figura(k)}${t}</button>`).join('')}${colores}${chipsGrosor(E.ancho)}</div>`;
  else if(E.herr === 'texto') opc = `<div class="ed-fila-x">${chipFondo(E.textoFondo, true)}${colores}</div>`;
  else if(E.herr === 'humedad') opc = `<div class="ed-fila-x"><span class="ed-tel-ayuda"><b>${esc(E.valor || '?')}%</b> · ${esc(E.mat)} · tap where you measured.</span><button type="button" class="ed-chip" data-ed-hoja="markup">Change</button></div>`;
  else if(['area', 'borroso'].includes(E.herr)) opc = `<p class="ed-tel-ayuda">${esc(AYUDA[E.herr])}</p>`;
  else opc = `<div class="ed-fila-x">${colores}${chipsGrosor(E.ancho)}</div>`;   // Arrow y Measure: colores y grosor (se arrastra en la foto)
  // La fila de opciones se desliza: al tocar un color o un grosor del final, que no brinque al principio.
  const filaAntes = E.bandeja.querySelector('.ed-tel-opc .ed-fila-x'); const clave = sel ? 'sel' + E.sel : (E.herr || '') + '/' + (enRecorte() ? 'r' : '');
  const xAntes = filaAntes && E.filaClave === clave ? filaAntes.scrollLeft : 0; E.filaClave = clave;
  E.bandeja.innerHTML = `<div class="ed-tel-opc">${opc}<div class="ed-tel-hist"><button type="button" class="ed-ic" data-ed="deshacer"${E.deshacer.length ? '' : ' disabled'} aria-label="Undo">${IC('deshacer')}</button><button type="button" class="ed-ic" data-ed="rehacer"${E.rehacer.length ? '' : ' disabled'} aria-label="Redo">${IC('rehacer')}</button></div></div>
    <p class="aviso" id="edAviso"></p>
    <div class="ed-tel-bandeja">
      ${PRINCIPALES.map(h => tile(h, E.herr === h[0] && !enRecorte(), `data-ed-herr="${h[0]}"`)).join('')}
      ${tile(['', 'Crop', 'recortar'], enRecorte(), 'data-ed-abrir="recorte"')}
      ${tile(['', 'Rotate', 'girar-der'], false, 'data-ed="girar-der"')}
      ${tile(['', 'Adjustments', 'ajustes'], E.hoja === 'ajustes' || E.hoja === 'filtros', 'data-ed-hoja="ajustes"')}
      ${tile(['', 'Markup', 'gota'], MARKUP.some(x => x[0] === E.herr) && !enRecorte(), 'data-ed-hoja="markup"')}
    </div>`;
  if(xAntes){ const f = E.bandeja.querySelector('.ed-tel-opc .ed-fila-x'); if(f) f.scrollLeft = xAntes; }
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
    // Mientras la foto todavía carga, solo se puede cerrar (girar o recortar antes reventaba y la foto salía girada).
    if((E.cargando || !E.marco) && !q('[data-ed="cerrar"]')) return;
    // Si estaba escribiendo, lo escrito se guarda primero y el botón tocado SÍ hace lo suyo (antes ese toque se perdía).
    if(E.escritura) terminarEscritura(true);
    if((el = q('[data-ed-hoja]'))){ ponerHoja(el.dataset.edHoja === E.hoja && el.closest('#edTel') ? '' : el.dataset.edHoja); return; }
    if((el = q('[data-ed-herr]'))){ const h = el.dataset.edHerr; E.herr = E.herr === h && !el.closest('#edHoja') ? '' : h; E.sel = -1; if(E.abierto === 'recorte'){ E.abierto = ''; colocar(); } if(E.tel && !MARKUP.some(x => x[0] === E.herr)) E.hoja = ''; render(); pintarPanel(); return; }
    if((el = q('[data-ed-forma]'))){ E.forma = el.dataset.edForma; pintarPanel(); return; }
    if((el = q('[data-ed-marca]'))){ E.marca = el.dataset.edMarca; pintarPanel(); return; }
    if((el = q('[data-ed-fondo]'))){ const m = E.sel >= 0 ? E.marcas[E.sel] : null;
      if(m && m.tipo === 'texto'){ E.deshacer.push(estado()); E.rehacer = []; m.fondo = m.fondo === 'ninguno' ? 'lleno' : 'ninguno'; E.textoFondo = m.fondo; render(); }
      else E.textoFondo = E.textoFondo === 'ninguno' ? 'lleno' : 'ninguno';
      pintarPanel(); return; }
    if((el = q('[data-ed-color]'))){ const col = el.dataset.edColor; E.color = col; const m = E.sel >= 0 ? E.marcas[E.sel] : null;
      if(CON_COLOR(m) && m.color !== col){ E.deshacer.push(estado()); E.rehacer = []; m.color = col; render(); }   // la marca escogida cambia de color
      pintarPanel(); return; }
    if((el = q('[data-ed-grosor]'))){ const n = Number(el.dataset.edGrosor); E.ancho = n; const m = E.sel >= 0 ? E.marcas[E.sel] : null;
      if(m && USA_GROSOR(m.tipo) && (m.ancho || 4) !== n){ E.deshacer.push(estado()); E.rehacer = []; m.ancho = n; render(); }   // la marca escogida cambia de grosor
      pintarPanel(); return; }
    if((el = q('[data-ed-mat]'))){ E.mat = el.dataset.edMat; pintarPanel(); return; }
    if((el = q('[data-ed-est]'))){ E.estado = el.dataset.edEst; E.estadoFijo = true; pintarPanel(); return; }
    if((el = q('[data-ed-filtro]'))){ if(E.filtro === el.dataset.edFiltro) return; E.deshacer.push(estado()); E.rehacer = []; E.filtro = el.dataset.edFiltro; render(); pintarPanel(); return; }
    if((el = q('[data-ed-prop]'))){ ponerProporcion(el.dataset.edProp); return; }
    if((el = q('[data-ed-abrir]'))){ const id = el.dataset.edAbrir; const antes = E.abierto; E.abierto = antes === id ? '' : id; E.sel = -1; if(antes === 'recorte' || E.abierto === 'recorte') colocar(); pintarPanel(); return; }
    if((el = q('[data-ed]'))){ const a = el.dataset.ed;
      if(a === 'deshacer') deshacer(); else if(a === 'rehacer') rehacer();
      else if(a === 'cerrar') salir();
      else if(a === 'borrar') borrarSel(); else if(a === 'editar') editarSel(); else if(a === 'soltar'){ E.sel = -1; render(); pintarPanel(); }
      else if(a === 'girar-izq') girar(-1); else if(a === 'girar-der') girar(1);
      else if(a === 'sin-recorte'){ const c0 = E.crop; if(!c0.x && !c0.y && c0.w >= 1 && c0.h >= 1 && E.prop === 'libre') return; E.deshacer.push(estado()); E.rehacer = []; E.crop = RECORTE_TODO(); E.prop = 'libre'; colocar(); pintarPanel(); }
      else if(a === 'reset'){ if(!hayCambios() || !confirm('Remove all marks, adjustments, filters and crop?')) return; E.deshacer.push(estado()); E.rehacer = [];
        const girado = E.rot !== 0; E.marcas = []; E.aj = { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }; E.filtro = 'original'; E.rot = 0; E.crop = RECORTE_TODO(); E.prop = 'libre'; E.sel = -1; if(girado) E.marco = hacerMarco(E.fuente, 0); colocar(); pintarPanel(); }
      else if(a === 'reset-aj'){ if(!Object.values(E.aj).some(Boolean) && E.filtro === 'original') return; E.deshacer.push(estado()); E.rehacer = []; E.aj = { exp:0, bri:0, con:0, sat:0, cal:0, nit:0 }; E.filtro = 'original'; render(); pintarPanel(); }
      else if(a === 'aplicar') guardar(true);
      return; }
  });
  document.addEventListener('input', (e) => {
    if(!E) return;
    if(e.target.id === 'edAncho'){ const n = Number(e.target.value); E.ancho = n; const m = E.sel >= 0 ? E.marcas[E.sel] : null;
      if(m && USA_GROSOR(m.tipo)){ m.ancho = n; if(!E.raf) E.raf = requestAnimationFrame(() => { if(E){ E.raf = 0; render(); } }); }
      return; }
    if(e.target.id === 'edValor'){ E.valor = e.target.value; E.estado = ''; E.estadoFijo = false; const est = estadoHumedad(E.valor);   // número nuevo = estado según el número
      zonas().forEach(z => z.querySelectorAll('[data-ed-est]').forEach(x => x.classList.toggle('on', x.dataset.edEst === est))); return; }
    // Un pintado por cuadro de pantalla aunque el control mande más eventos (calidez y nitidez recorren la foto entera).
    const k = e.target.dataset && e.target.dataset.edAj; if(k){ E.aj[k] = Number(e.target.value); if(!E.raf) E.raf = requestAnimationFrame(() => { if(E){ E.raf = 0; render(); } }); }
  });
  // Sliders: el paso de Undo se guarda al SOLTAR y solo si el valor de verdad cambió (tocarlo sin moverlo no gasta un paso).
  // Siempre el estado de ESE momento (un toque al slider sin moverlo dejaba guardado uno viejo, y el siguiente Undo
  // se llevaba también las marcas hechas en medio).
  const antesDeAjuste = (e) => { if(E && e.target.dataset && (e.target.dataset.edAj || e.target.id === 'edAncho')) E.ajAntes = estado(); };
  document.addEventListener('pointerdown', antesDeAjuste, true); document.addEventListener('keydown', antesDeAjuste, true);
  document.addEventListener('change', (e) => {
    if(!E || !e.target.dataset || !(e.target.dataset.edAj || e.target.id === 'edAncho')) return; const a = E.ajAntes; E.ajAntes = null;
    if(a && (JSON.stringify(a.aj) !== JSON.stringify(E.aj) || JSON.stringify(a.marcas) !== JSON.stringify(E.marcas))){ E.deshacer.push(a); E.rehacer = []; }
    zonas().forEach(z => z.querySelectorAll('[data-ed="deshacer"]').forEach(b => { b.disabled = !E.deshacer.length; }));
    zonas().forEach(z => z.querySelectorAll('[data-ed="rehacer"]').forEach(b => { b.disabled = !E.rehacer.length; }));
  });
}
