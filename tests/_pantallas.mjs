// Fabrica pantallas de medidor de PRUEBA (no son fotos reales): 7 rayitas, cursiva, borrosas, con ruido,
// sombra, el "%" y el punto decimal. Sirven para medir el lector de números (tests/lector_test.mjs).
const SEG = { 0: 'abcdef', 1: 'bc', 2: 'abged', 3: 'abgcd', 4: 'fgbc', 5: 'afgcd', 6: 'afgedc', 7: 'abc', 8: 'abcdefg', 9: 'abcdfg' };
export function azar(semilla){ let s = semilla >>> 0 || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }
function poligonos(d, x, y, w, h, t){
  const P = {
    a: [[x + t, y], [x + w - t, y], [x + w - 2 * t, y + t], [x + 2 * t, y + t]],
    d: [[x + 2 * t, y + h - t], [x + w - 2 * t, y + h - t], [x + w - t, y + h], [x + t, y + h]],
    g: [[x + t, y + h / 2 - t / 2], [x + w - t, y + h / 2 - t / 2], [x + w - t, y + h / 2 + t / 2], [x + t, y + h / 2 + t / 2]],
    f: [[x, y + t], [x + t, y + 2 * t], [x + t, y + h / 2 - t], [x, y + h / 2 - t / 2]],
    e: [[x, y + h / 2 + t / 2], [x + t, y + h / 2 + t], [x + t, y + h - 2 * t], [x, y + h - t]],
    b: [[x + w, y + t], [x + w, y + h / 2 - t / 2], [x + w - t, y + h / 2 - t], [x + w - t, y + 2 * t]],
    c: [[x + w, y + h / 2 + t / 2], [x + w, y + h - t], [x + w - t, y + h - 2 * t], [x + w - t, y + h / 2 + t]],
  };
  return (SEG[d] || '').split('').map(k => P[k]);
}
const dentro = (px, py, pol) => { let c = false; for(let i = 0, j = pol.length - 1; i < pol.length; j = i++){ const [xi, yi] = pol[i], [xj, yj] = pol[j]; if(((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi)) c = !c; } return c; };
// texto: '18.5', '40'… ; op: { inclina, gira, borroso, ruido, sombra, gap, pct, fondo, tinta, invertida }
export function pantalla(texto, op, R){
  const W = 640, H = 480, img = new Uint8ClampedArray(W * H * 4);
  const fondo = op.fondo || [168, 180, 160], tinta = op.tinta || [28, 32, 28];
  const formas = [];   // [pol, color]
  const caja = { x: 150, y: 130, w: 340, h: 200 };
  formas.push([[[0, 0], [W, 0], [W, H], [0, H]], [45, 45, 45]]);                         // cuerpo del medidor
  formas.push([[[caja.x, caja.y], [caja.x + caja.w, caja.y], [caja.x + caja.w, caja.y + caja.h], [caja.x, caja.y + caja.h]], fondo]);
  const dh = 110, dw = 58, t = op.grosor || 11, gap = op.gap || 0;
  const chars = texto.split(''); const nd = chars.filter(c => c !== '.').length;
  let x = caja.x + caja.w / 2 - (nd * (dw + 22)) / 2 - (op.pct ? 22 : 0), y = caja.y + 45;
  for(const ch of chars){
    if(ch === '.'){ const cx = x - 12, cy = y + dh - 5; formas.push([[[cx - 6, cy - 6], [cx + 6, cy - 6], [cx + 6, cy + 6], [cx - 6, cy + 6]], tinta]); continue; }
    poligonos(ch, x, y, dw, dh, t).forEach(p => {
      // las rayitas de una pantalla de verdad no se tocan: se encogen un poquito
      if(gap){ const cx = p.reduce((a, q) => a + q[0], 0) / p.length, cy = p.reduce((a, q) => a + q[1], 0) / p.length; p = p.map(([px, py]) => [cx + (px - cx) * (1 - gap), cy + (py - cy) * (1 - gap)]); }
      formas.push([p, tinta]);
    });
    x += dw + 22;
  }
  if(op.pct){ const px = x + 4, py = y + dh - 50; formas.push([[[px, py + 48], [px + 6, py + 48], [px + 36, py], [px + 30, py]], tinta]); formas.push([[[px, py], [px + 10, py], [px + 10, py + 10], [px, py + 10]], tinta]); formas.push([[[px + 26, py + 38], [px + 36, py + 38], [px + 36, py + 48], [px + 26, py + 48]], tinta]); }
  // iconos chicos arriba (pila, gota) como en los medidores
  formas.push([[[caja.x + 20, caja.y + 14], [caja.x + 44, caja.y + 14], [caja.x + 44, caja.y + 26], [caja.x + 20, caja.y + 26]], tinta]);
  const inc = op.inclina || 0, gira = (op.gira || 0) * Math.PI / 180, ccx = W / 2, ccy = H / 2, yc = y + dh / 2;
  const plano = new Uint8ClampedArray(W * H * 3);
  formas.forEach(([pol, c], k) => {
    const sh = k >= 2 ? inc : 0;
    const xs = pol.map(q => q[0]), ys = pol.map(q => q[1]);
    const bx0 = Math.max(0, Math.floor(Math.min(...xs) - Math.abs(sh) * dh)), bx1 = Math.min(W - 1, Math.ceil(Math.max(...xs) + Math.abs(sh) * dh));
    const by0 = Math.max(0, Math.floor(Math.min(...ys))), by1 = Math.min(H - 1, Math.ceil(Math.max(...ys)));
    for(let py = by0; py <= by1; py++) for(let px = bx0; px <= bx1; px++)
      if(dentro(px + sh * (py - yc), py, pol)){ const i = (py * W + px) * 3; plano[i] = c[0]; plano[i + 1] = c[1]; plano[i + 2] = c[2]; }
  });
  const cg = Math.cos(gira), sg = Math.sin(gira);
  for(let py = 0; py < H; py++) for(let px = 0; px < W; px++){
    const rx = Math.round(ccx + (px - ccx) * cg + (py - ccy) * sg), ry = Math.round(ccy - (px - ccx) * sg + (py - ccy) * cg);
    const i = (py * W + px) * 4, j = (ry >= 0 && ry < H && rx >= 0 && rx < W) ? (ry * W + rx) * 3 : -1;
    const luz = 1 + (op.sombra || 0) * ((px / W) - 0.5);
    for(let c = 0; c < 3; c++) img[i + c] = Math.max(0, Math.min(255, (j >= 0 ? plano[j + c] : 45) * luz + (R() - 0.5) * (op.ruido || 0)));
    img[i + 3] = 255;
  }
  if(op.invertida) for(let i = 0; i < img.length; i += 4) for(let c = 0; c < 3; c++) img[i + c] = 255 - img[i + c];
  // borroso: caja de 3x3 tantas veces como diga
  for(let b = 0; b < (op.borroso || 0); b++){
    const src = new Uint8ClampedArray(img);
    for(let py = 1; py < H - 1; py++) for(let px = 1; px < W - 1; px++) for(let c = 0; c < 3; c++){
      let s = 0; for(let dy = -1; dy <= 1; dy++) for(let dx = -1; dx <= 1; dx++) s += src[((py + dy) * W + px + dx) * 4 + c];
      img[(py * W + px) * 4 + c] = s / 9;
    }
  }
  // la guía de la cámara: un poco más grande que la pantallita (el técnico no apunta perfecto)
  const m = op.margen == null ? 30 : op.margen;
  return { img: { data: img, width: W, height: H }, guia: { x: caja.x - m + (op.corre || 0), y: caja.y - m, w: caja.w + 2 * m, h: caja.h + 2 * m } };
}
export function valorAzar(R){
  const r = R();
  if(r < 0.35) return String(Math.floor(R() * 100));                 // 0-99
  if(r < 0.7) return (Math.floor(R() * 300) / 10).toFixed(1);        // 0.0-29.9
  return String(Math.floor(R() * 900) + 100).slice(0, 3);            // 100-999 (escala de referencia)
}
