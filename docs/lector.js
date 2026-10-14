// Scanova360 · NUESTRO lector de números de medidor (14-oct). Su regla: "no puedo pagar por esto" — así que no
// hay servicio de afuera: todo corre en el teléfono (o la compu), gratis y sin internet.
// Las pantallas de los medidores de humedad son de 7 rayitas (como una calculadora). El lector:
//  1. Toma solo el cuadro guía de la cámara (donde el técnico pone la pantallita) y lo pasa a grises.
//  2. Separa lo oscuro de lo claro con un umbral LOCAL (aguanta sombra y brillo de un lado).
//  3. Junta las manchas en "letras" (las rayitas de un mismo número se tocan en lo ancho).
//  4. A cada número le revisa sus 7 rayitas (a arriba, b/c derecha, d abajo, e/f izquierda, g en medio) y busca
//     qué número forman. Los medidores escriben inclinado: se prueba enderezar varios ángulos y se queda con el mejor.
//  5. El punto decimal es una manchita abajo entre dos números. El "%" y las letras no cuentan.
// Si algo no se entiende, NO se inventa: regresa null y el técnico escribe el número (siempre lo confirma).
// Todo es puro (recibe { data, width, height } como ImageData), para poder probarlo sin pantalla.

// ---------- 1. grises y recorte ----------
export function grises(img, caja){
  const { width: W, height: H, data } = img;
  const x0 = Math.max(0, Math.floor(caja ? caja.x : 0)), y0 = Math.max(0, Math.floor(caja ? caja.y : 0));
  const w = Math.min(W - x0, Math.floor(caja ? caja.w : W)), h = Math.min(H - y0, Math.floor(caja ? caja.h : H));
  // Se trabaja a ~160 px de alto: suficiente para las rayitas y rápido en cualquier teléfono.
  const esc = Math.min(1, 160 / Math.max(1, h)), ow = Math.max(8, Math.round(w * esc)), oh = Math.max(8, Math.round(h * esc));
  const g = new Float32Array(ow * oh), paso = 1 / esc;
  for(let y = 0; y < oh; y++) for(let x = 0; x < ow; x++){
    // promedio del bloque (no solo un pixel): quita el ruido de la foto
    let s = 0, n = 0;
    const sx = x0 + Math.floor(x * paso), sy = y0 + Math.floor(y * paso), ex = Math.min(x0 + w, Math.floor(sx + paso) || sx + 1), ey = Math.min(y0 + h, Math.floor(sy + paso) || sy + 1);
    for(let yy = sy; yy < Math.max(ey, sy + 1); yy++) for(let xx = sx; xx < Math.max(ex, sx + 1); xx++){ const i = (yy * W + xx) * 4; s += data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114; n++; }
    g[y * ow + x] = n ? s / n : 255;
  }
  // Suavizado (dos pasadas de 3x3): el ruido de la cámara rompía las rayitas en puntitos.
  for(let p = 0; p < 0; p++){
    const src = g.slice();
    for(let y = 0; y < oh; y++) for(let x = 0; x < ow; x++){
      let s2 = 0, n2 = 0;
      for(let dy = -1; dy <= 1; dy++) for(let dx = -1; dx <= 1; dx++){ const yy = y + dy, xx = x + dx; if(yy >= 0 && yy < oh && xx >= 0 && xx < ow){ s2 += src[yy * ow + xx]; n2++; } }
      g[y * ow + x] = s2 / n2;
    }
  }
  return { g, w: ow, h: oh };
}
// Limpieza de la máscara: cada pixel toma lo que diga la mayoría de sus 9 vecinos (quita puntitos, tapa huequitos).
function mayoria(M){
  const { m, w, h } = M, out = new Uint8Array(w * h);
  for(let y = 0; y < h; y++) for(let x = 0; x < w; x++){
    let c = 0; for(let dy = -1; dy <= 1; dy++) for(let dx = -1; dx <= 1; dx++){ const yy = y + dy, xx = x + dx; if(yy >= 0 && yy < h && xx >= 0 && xx < w) c += m[yy * w + xx]; }
    out[y * w + x] = c >= 5 ? 1 : 0;
  }
  return { ...M, m: out };
}

// ---------- 2. oscuro / claro con umbral local ----------
export function umbral(G, k){
  const { g, w, h } = G, r = Math.max(4, Math.round(h / 6)), inte = new Float64Array((w + 1) * (h + 1));
  for(let y = 0; y < h; y++){ let fila = 0; for(let x = 0; x < w; x++){ fila += g[y * w + x]; inte[(y + 1) * (w + 1) + x + 1] = inte[y * (w + 1) + x + 1] + fila; } }
  let min = 255, max = 0; for(let i = 0; i < g.length; i++){ if(g[i] < min) min = g[i]; if(g[i] > max) max = g[i]; }
  const contraste = max - min, m = new Uint8Array(w * h);
  if(contraste < 25) return { m, w, h, contraste };
  for(let y = 0; y < h; y++) for(let x = 0; x < w; x++){
    const ax = Math.max(0, x - r), ay = Math.max(0, y - r), bx = Math.min(w, x + r + 1), by = Math.min(h, y + r + 1);
    const suma = inte[by * (w + 1) + bx] - inte[ay * (w + 1) + bx] - inte[by * (w + 1) + ax] + inte[ay * (w + 1) + ax];
    const media = suma / ((bx - ax) * (by - ay));
    m[y * w + x] = g[y * w + x] < media - Math.max(contraste * (k || 0.12), 6) ? 1 : 0;
  }
  return { m, w, h, contraste };
}

// ---------- 3. manchas y letras ----------
export function manchas(M){
  const { m, w, h } = M, et = new Int32Array(w * h), out = [], pila = [];
  let n = 0;
  for(let i = 0; i < m.length; i++){
    if(!m[i] || et[i]) continue;
    n++; let x0 = w, y0 = h, x1 = 0, y1 = 0, area = 0, borde = false; pila.push(i); et[i] = n;
    while(pila.length){
      const j = pila.pop(), x = j % w, y = (j - x) / w; area++;
      if(x < x0) x0 = x; if(x > x1) x1 = x; if(y < y0) y0 = y; if(y > y1) y1 = y;
      if(x === 0 || y === 0 || x === w - 1 || y === h - 1) borde = true;
      const vec = [j - 1, j + 1, j - w, j + w];
      if(x === 0) vec[0] = -1; if(x === w - 1) vec[1] = -1;
      for(const v of vec) if(v >= 0 && v < m.length && m[v] && !et[v]){ et[v] = n; pila.push(v); }
    }
    out.push({ x0, y0, x1, y1, area, borde, id: n });
  }
  return out;
}
// Las rayitas de un número NO se tocan (en la pantalla hay una separación chiquita entre ellas). Para saber qué
// rayitas son del mismo número se mide la altura de las rayitas paradas: un número mide como 2.5 de ellas, y la
// separación entre números es mucho más grande que la separación entre rayitas.
export function letras(lista, w, h){
  const ok = lista.filter(b => !b.borde && b.area >= 3 && (b.y1 - b.y0 + 1) < h * 0.9 && (b.x1 - b.x0 + 1) < w * 0.6);
  const paradas = ok.filter(b => (b.y1 - b.y0 + 1) >= 1.6 * (b.x1 - b.x0 + 1) && (b.y1 - b.y0 + 1) >= h * 0.08).map(b => b.y1 - b.y0 + 1).sort((a, b) => a - b);
  if(!paradas.length) return [];
  const segH = paradas[Math.floor(paradas.length * 0.75)];   // las más altas (los "1" y las rayitas de lado)
  // La franja de los números: de la rayita parada más alta a la más baja (las de buen tamaño). Lo que quede fuera
  // —los iconos de arriba (pila, gota), las letras de abajo (MODE)— no es parte de la lectura.
  const fuertes = ok.filter(b => (b.y1 - b.y0 + 1) >= 1.6 * (b.x1 - b.x0 + 1) && (b.y1 - b.y0 + 1) >= segH * 0.6 && (b.y1 - b.y0 + 1) <= segH * 1.6);
  const v0 = Math.min(...fuertes.map(b => b.y0)), v1 = Math.max(...fuertes.map(b => b.y1));
  // Lo que mide un número: de punta a punta de las rayitas paradas, más la raya de arriba y la de abajo
  // (que quedan afuera por su grueso y la separación). Medido, no supuesto: con separación grande un número
  // llega a medir 3.5 rayitas paradas.
  const alto = Math.max(segH * 2, (v1 - v0 + 1) * 1.25), tol = Math.max(2, alto * 0.1);
  const f0 = v0 - alto * 0.18, f1 = v1 + alto * 0.18;
  const enFranja = ok.filter(b => (b.y0 + b.y1) / 2 >= f0 && (b.y0 + b.y1) / 2 <= f1);
  // Los puntitos (el decimal, manchas) no ayudan a juntar: un punto entre dos números los pegaría en uno solo.
  // Un punto es chico y casi cuadrado; una raya cortita (la de arriba de un 7) es alargada y sí cuenta.
  const chico = (b) => { const bw = b.x1 - b.x0 + 1, bh = b.y1 - b.y0 + 1; return bh < alto * 0.22 && bw < alto * 0.22 && bw <= bh * 1.6 && bh <= bw * 1.6; };
  const piezas = enFranja.filter(b => !chico(b)).sort((a, b) => a.x0 - b.x0);
  // Del mismo número: una al lado de la otra, cerquita en lo alto (el iconito de la pila arriba NO) y sin pasar el alto de un número.
  const cabe = (G, b) => b.x0 <= G.x1 + tol && b.x1 >= G.x0 - tol && b.y0 <= G.y1 + alto * 0.3 && b.y1 >= G.y0 - alto * 0.3 && Math.max(G.y1, b.y1) - Math.min(G.y0, b.y0) <= alto * 1.35;
  const juntar = (G, b) => { G.x0 = Math.min(G.x0, b.x0); G.x1 = Math.max(G.x1, b.x1); G.y0 = Math.min(G.y0, b.y0); G.y1 = Math.max(G.y1, b.y1); G.area += b.area; };
  const grupos = [];
  for(const b of piezas){ const g = grupos.find(G => cabe(G, b)); if(g) juntar(g, b); else grupos.push({ x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1, area: b.area }); }
  // Segunda vuelta: dos grupos que ya se enciman son el mismo número.
  for(let otra = true; otra;){ otra = false;
    for(let i = 0; i < grupos.length && !otra; i++) for(let j = i + 1; j < grupos.length && !otra; j++)
      if(cabe(grupos[i], grupos[j])){ juntar(grupos[i], grupos[j]); grupos.splice(j, 1); otra = true; } }
  enFranja.filter(chico).forEach(b => grupos.push({ x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1, area: b.area, punto: true }));
  grupos.alto = alto;   // lo que debe medir un número (sale de las rayitas paradas)
  const r = grupos.sort((a, b) => a.x0 - b.x0); r.alto = alto; r.fuertes = fuertes; return r;
}

// ---------- 4. las 7 rayitas ----------
const NUM = { abcdef: '0', bc: '1', abdeg: '2', abcdg: '3', bcfg: '4', acdfg: '5', acdefg: '6', cdefg: '6', abc: '7', abcf: '7', abcdefg: '8', abcdfg: '9', abcfg: '9' };
// Qué tanto de cada zona está oscuro (0 a 1).
export function zonas(M, L){
  const { m, w } = M, ww = L.x1 - L.x0 + 1, hh = L.y1 - L.y0 + 1;
  const zona = (fx0, fx1, fy0, fy1) => { let s = 0, n = 0;
    for(let y = Math.floor(L.y0 + fy0 * hh); y <= Math.min(L.y1, Math.ceil(L.y0 + fy1 * hh)); y++)
      for(let x = Math.floor(L.x0 + fx0 * ww); x <= Math.min(L.x1, Math.ceil(L.x0 + fx1 * ww)); x++){ s += m[y * w + x]; n++; }
    return n ? s / n : 0; };
  return { a: zona(0.25, 0.75, 0, 0.12), d: zona(0.25, 0.75, 0.88, 1), g: zona(0.25, 0.75, 0.44, 0.56),
           f: zona(0, 0.22, 0.14, 0.42), b: zona(0.78, 1, 0.14, 0.42), e: zona(0, 0.22, 0.58, 0.86), c: zona(0.78, 1, 0.58, 0.86) };
}
export function leerDigito(M, L){
  const ww = L.x1 - L.x0 + 1, hh = L.y1 - L.y0 + 1;
  if(ww / hh < 0.33){   // angosto: el 1 (si es una raya parada que llena el alto)
    let s = 0, n = 0; for(let y = L.y0; y <= L.y1; y++){ let fila = 0; for(let x = L.x0; x <= L.x1; x++) fila |= M.m[y * M.w + x]; s += fila; n++; }
    return s / n > 0.7 ? { d: '1', seguro: 1 } : null;
  }
  // Prendida o apagada: se comparan las 7 entre sí (no contra un número fijo). Se busca el salto más grande entre
  // las apagadas y las prendidas; si no hay un salto claro, el número queda en duda y no se adivina.
  const z = zonas(M, L), ks = 'abcdefg'.split(''), vs = ks.map(k => z[k]).sort((a, b) => a - b);
  let corte = 0.3, salto = 0;
  if(vs[0] >= 0.3) { corte = vs[0] / 2; salto = vs[0]; }                 // todas prendidas: el 8
  else for(let i = 0; i < 6; i++){ const g = vs[i + 1] - vs[i]; if(g > salto && vs[i + 1] >= 0.22){ salto = g; corte = (vs[i] + vs[i + 1]) / 2; } }
  if(salto < 0.15) return null;
  const clave = ks.filter(k => z[k] > corte).join('');
  const d = NUM[clave]; if(!d) return null;
  return { d, seguro: Math.min(1, salto / 0.5) };
}

// Inclinar la máscara (los medidores escriben cursiva): x' = x + s·(y − centro).
export function enderezar(M, s){
  if(!s) return M;
  const { m, w, h } = M, out = new Uint8Array(w * h), cy = h / 2;
  for(let y = 0; y < h; y++){ const dx = Math.round(s * (y - cy)); for(let x = 0; x < w; x++){ const sx = x + dx; if(sx >= 0 && sx < w) out[y * w + x] = m[y * w + sx]; } }
  return { m: out, w, h };
}

// ---------- 5. leer la pantalla ----------
// Por qué no se pudo (solo para mejorar el lector con el banco de pruebas).
export const MOTIVOS = {};
const no = (k) => { MOTIVOS[k] = (MOTIVOS[k] || 0) + 1; return null; };
export function _leerMascara(M){ return leerMascara(M); }
function leerMascara(M){
  const todas = manchas(M);
  // Una pantalla de verdad da rayitas sólidas. Si lo oscuro son puros puntitos sueltos (la orilla rasposa del
  // medidor, ruido), esta forma de verla no sirve: de ahí salían números falsos.
  const puntitos = todas.filter(b => !b.borde && b.area < 8).length;
  if(puntitos > M.w * M.h * 0.0015) return no('ruidoso');
  const ls = letras(todas, M.w, M.h); if(!ls.length || !ls.alto) return no('m1');
  const est = ls.alto, altoDe = (L) => L.y1 - L.y0 + 1, centro = (L) => (L.y0 + L.y1) / 2;
  // Candidatos a número: del tamaño de un número (ni una rayita suelta ni una raya del borde más alta).
  const cand = ls.filter(L => !L.punto && altoDe(L) >= est * 0.6 && altoDe(L) <= est * 1.45);
  if(!cand.length) return no('m2');
  const med = (xs) => { const o = xs.slice().sort((a, b) => a - b); return o[Math.floor(o.length / 2)]; };
  // La medida la pone el número más alto: el 1, el 4 y el 7 son un poco más bajitos (no llevan raya arriba o abajo).
  const ref = Math.max(...cand.map(altoDe)), cy = med(cand.map(centro));
  let linea = cand.filter(L => altoDe(L) >= ref * 0.62 && Math.abs(centro(L) - cy) <= ref * 0.22);
  // Se queda con el grupo más largo de números seguidos (sin huecos de más de 1.5 números).
  const tramos = []; linea.forEach(L => { const t = tramos[tramos.length - 1]; if(t && L.x0 - t[t.length - 1].x1 <= ref * 1.5) t.push(L); else tramos.push([L]); });
  linea = tramos.sort((a, b) => b.length - a.length)[0] || [];
  // Los medidores de humedad dan a lo mucho 3 cifras (999) y un decimal: algo más largo no es una lectura.
  if(!linea.length || linea.length > 3) return no('m3');
  // Ninguna rayita parada de buen tamaño puede quedar fuera de los números leídos: si quedó una, se perdió un
  // número (un "1" de la orilla, un 7 bajito) y la lectura saldría corta. Mejor no dar nada.
  const dentroDe = (b) => linea.some(L => b.x0 >= L.x0 - 2 && b.x1 <= L.x1 + 2);
  if((ls.fuertes || []).some(b => !dentroDe(b))) return no('m4');
  // Tampoco puede quedar un pedazo suelto (una raya de arriba que se despegó) entre los números o pegado a ellos:
  // un 7 sin su raya de arriba parece 1.
  const x0l = linea[0].x0 - ref * 0.5, x1l = linea[linea.length - 1].x1 + ref * 0.15;
  if(ls.some(L => !L.punto && !linea.includes(L) && L.x1 >= x0l && L.x0 <= x1l && centro(L) >= cy - ref * 0.75 && centro(L) <= cy + ref * 0.75)) return no('suelto');
  const leidos = linea.map(L => ({ L, r: leerDigito(M, L) }));
  // El ritmo: en la pantalla los números van a distancias iguales (se mide de orilla derecha a orilla derecha; el 1
  // también se pega a la derecha). Una raya del borde que parezca "1" no cae en ese ritmo.
  const anchoN = Math.max(...linea.map(L => L.x1 - L.x0 + 1)), der = linea.map(L => L.x1), pasos = der.slice(1).map((x, i) => x - der[i]);
  if(pasos.length >= 2 && Math.max(...pasos) > Math.min(...pasos) * 1.35) return no('m5');
  if(pasos.length === 1 && (pasos[0] < anchoN * 1.0 || pasos[0] > anchoN * 1.9)) return no('m6');
  if(linea.length === 1 && (linea[0].x1 - linea[0].x0 + 1) / altoDe(linea[0]) < 0.33) return no('m7');   // un "1" solito: puede ser una raya
  // Un número que no se entiende NUNCA se quita en silencio (daría otro número): no se pudo, el técnico lo escribe.
  if(leidos.some(x => !x.r)) return no('m8');
  // Forma de número: ni muy ancho ni muy flaco (salvo el 1).
  if(leidos.some(x => x.r.d !== '1' && ((x.L.x1 - x.L.x0 + 1) / altoDe(x.L) < 0.3 || (x.L.x1 - x.L.x0 + 1) / altoDe(x.L) > 0.9))) return no('m9');
  const base = Math.max(...linea.map(L => L.y1));
  // El punto decimal: manchita chica pegada a la línea de abajo, entre dos números.
  const puntos = ls.filter(L => L.punto && L.y1 >= base - ref * 0.2 && L.y0 > base - ref * 0.35);
  let texto = '', seguro = 1;
  leidos.forEach((x, i) => {
    texto += x.r.d; seguro = Math.min(seguro, x.r.seguro);
    const sig = leidos[i + 1];
    if(sig && !texto.includes('.') && puntos.some(p => p.x0 >= x.L.x1 - ref * 0.15 && p.x1 <= sig.L.x0 + ref * 0.15)) texto += '.';
  });
  if(seguro < 0.2) return no('m10');   // alguna rayita quedó en duda
  if(/\.\d\d/.test(texto)) return no('decimales');   // dos o más decimales: no es de un medidor de humedad
  // Los números leídos tienen que explicar la mayoría de lo oscuro del cuadro. Si sobra mucha tinta sin explicar,
  // se leyó media pantalla (el ángulo equivocado) y el número saldría mal.
  const dentro = (b) => { const x = (b.x0 + b.x1) / 2, y = (b.y0 + b.y1) / 2; return linea.some(L => x >= L.x0 - 1 && x <= L.x1 + 1 && y >= L.y0 - 1 && y <= L.y1 + 1); };
  let tinta = 0, cubierta = 0;
  // No cuentan: lo que va a la derecha de los números (la unidad, %) ni los iconos de arriba a un lado.
  const iniX = linea[0].x0, finX = linea[linea.length - 1].x1, topY = Math.min(...linea.map(L => L.y0));
  todas.forEach(b => { if(b.borde || b.area < 8) return;
    const x = (b.x0 + b.x1) / 2, y = (b.y0 + b.y1) / 2;
    if(x > finX + ref * 0.1 && y > topY + ref * 0.5 && (b.y1 - b.y0 + 1) < ref * 0.55) return;   // la unidad (%): chica y abajo
    if(y < topY && x < iniX - ref * 0.15) return;
    tinta += b.area; if(dentro(b)) cubierta += b.area; });
  const cubre = tinta ? cubierta / tinta : 0;
  if(cubre < 0.55) return no('cubre');
  return { texto, seguro, digitos: leidos.length, cubre };
}
export const INCLINACIONES = [0, 0.06, 0.12, 0.18, 0.24, 0.3, -0.06];
// Girar la imagen en grises unos grados (la foto casi nunca sale derecha).
export function girar(G, grados){
  if(!grados) return G;
  const { g, w, h } = G, out = new Float32Array(w * h), a = grados * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), cx = w / 2, cy = h / 2;
  let fondo = 0; for(let i = 0; i < g.length; i++) fondo += g[i]; fondo /= g.length;
  for(let y = 0; y < h; y++) for(let x = 0; x < w; x++){
    const sx = cx + (x - cx) * c - (y - cy) * s, sy = cy + (x - cx) * s + (y - cy) * c;
    const x0 = Math.floor(sx), y0 = Math.floor(sy);
    if(x0 < 0 || y0 < 0 || x0 >= w - 1 || y0 >= h - 1){ out[y * w + x] = fondo; continue; }
    const fx = sx - x0, fy = sy - y0, i = y0 * w + x0;
    out[y * w + x] = g[i] * (1 - fx) * (1 - fy) + g[i + 1] * fx * (1 - fy) + g[i + w] * (1 - fx) * fy + g[i + w + 1] * fx * fy;
  }
  return { g: out, w, h };
}
export const GIROS = [0, 3, -3];
export function leerPantalla(img, caja){
  const G = grises(img, caja);
  let mejor = null;
  // Las dos formas: números oscuros sobre fondo claro (lo normal) y números claros sobre fondo oscuro (pantalla con luz).
  // Se prueban varios giros, cortes e inclinaciones y se queda con la lectura más completa.
  const Ginv = { ...G, g: G.g.map(v => 255 - v) };
  for(const giro of GIROS) for(const G0 of [G, Ginv]) for(const k of [0.12, 0.2]){
    const M = umbral(girar(G0, giro), k); if(M.contraste < 25) return null;
    for(const s of INCLINACIONES){
      const r = leerMascara(enderezar(M, s)); if(!r) continue;
      const puntaje = r.digitos * 2 + r.seguro + r.cubre - Math.abs(s) * 0.5 - Math.abs(giro) * 0.05;
      if(!mejor || puntaje > mejor.puntaje) mejor = { ...r, puntaje };
    }
  }
  if(!mejor) return null;
  const valor = Number(mejor.texto);
  if(!isFinite(valor) || valor > 1000) return null;
  return { texto: mejor.texto, valor, seguro: Math.round(mejor.seguro * 100) / 100 };
}
