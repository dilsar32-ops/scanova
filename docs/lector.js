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

// Interruptores para medir cada regla nueva por separado (pruebas).
export const AJ = { fila: true, chico: true, ancho: true, ruido: true, pduda: true, pfinal: false, cubreF: true, sder: true };

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
  let fuertes = ok.filter(b => (b.y1 - b.y0 + 1) >= 1.6 * (b.x1 - b.x0 + 1) && (b.y1 - b.y0 + 1) >= segH * 0.6 && (b.y1 - b.y0 + 1) <= segH * 1.6);
  // Fotos de verdad (14-oct): la pantalla trae DOS renglones (la lectura grande y la temperatura chiquita abajo) y
  // una gráfica de barras a un lado. La lectura es el renglón de los números MÁS ALTOS: sus rayitas paradas miden
  // lo mismo entre sí y caben en una franja de ~3 rayitas. Se busca esa franja y, dentro de ella, el bloque con más
  // rayitas (la gráfica de barras queda aparte, separada por un hueco).
  {
    const altos = fuertes.map(b => b.y1 - b.y0 + 1).sort((a, b) => a - b), top = altos[Math.floor(altos.length * 0.9)] || segH;
    const grandes = fuertes.filter(b => (b.y1 - b.y0 + 1) >= top * 0.72);
    const ven = top * 3.1;
    let mejorV = null;
    for(const s of grandes){ const a = s.y0, dentro = grandes.filter(b => b.y0 >= a - 1 && b.y1 <= a + ven);
      const peso = dentro.reduce((t, b) => t + (b.y1 - b.y0 + 1), 0); if(!mejorV || peso > mejorV.peso) mejorV = { dentro, peso }; }
    let fila = mejorV ? mejorV.dentro.slice().sort((a, b) => a.x0 - b.x0) : [];
    const brecha = top * 2.4, bloques = [];
    fila.forEach(b => { const t = bloques[bloques.length - 1]; if(t && b.x0 - Math.max(...t.map(q => q.x1)) <= brecha) t.push(b); else bloques.push([b]); });
    const bloque = bloques.sort((p, q) => q.length - p.length)[0];
    // Solo se deja fuera lo que claramente es otra cosa: más chico (el renglón de abajo), lejos a un lado (la
    // gráfica de barras) o fuera de la franja. Si sobra una rayita parecida y cercana, puede ser un número que se
    // perdió: entonces no se recorta nada y la revisión de abajo (m4) decide.
    if(AJ.fila && bloque && bloque.length >= 2 && fuertes.length > bloque.length){
      const hs = bloque.map(b => b.y1 - b.y0 + 1).sort((a, b) => a - b), hMed = hs[hs.length >> 1];
      const kx0 = Math.min(...bloque.map(b => b.x0)), kx1 = Math.max(...bloque.map(b => b.x1));
      const ky0 = Math.min(...bloque.map(b => b.y0)), ky1 = Math.max(...bloque.map(b => b.y1));
      const ajeno = (b) => (b.y1 - b.y0 + 1) < hMed * 0.8 || b.x1 < kx0 - brecha || b.x0 > kx1 + brecha || (b.y0 + b.y1) / 2 < ky0 - hMed * 0.5 || (b.y0 + b.y1) / 2 > ky1 + hMed * 0.5;
      if(fuertes.every(b => bloque.includes(b) || ajeno(b))) fuertes = bloque;
    }
  }
  const v0 = Math.min(...fuertes.map(b => b.y0)), v1 = Math.max(...fuertes.map(b => b.y1));
  // Lo que mide un número: de punta a punta de las rayitas paradas, más la raya de arriba y la de abajo
  // (que quedan afuera por su grueso y la separación). Medido, no supuesto: con separación grande un número
  // llega a medir 3.5 rayitas paradas.
  const alto = Math.max(segH * 2, (v1 - v0 + 1) * 1.25), tol = Math.max(2, alto * 0.1);
  const f0 = v0 - alto * 0.18, f1 = v1 + alto * 0.18;
  // Y a lo ancho, solo junto al bloque de números (la gráfica de barras de un lado no entra).
  const bx0 = Math.min(...fuertes.map(b => b.x0)) - alto * 0.5, bx1 = Math.max(...fuertes.map(b => b.x1)) + alto * 0.6;
  const enFranja = ok.filter(b => (b.y0 + b.y1) / 2 >= f0 && (b.y0 + b.y1) / 2 <= f1 && (!AJ.ancho || ((b.x0 + b.x1) / 2 >= bx0 && (b.x0 + b.x1) / 2 <= bx1)));
  // Los puntitos (el decimal, manchas) no ayudan a juntar: un punto entre dos números los pegaría en uno solo.
  // Un punto es chico y casi cuadrado; una raya cortita (la de arriba de un 7) es alargada y sí cuenta.
  // (en las fotos de verdad el punto sale alargado, como coma: se deja que sea un poco más alto que ancho)
  const chico = (b) => { const bw = b.x1 - b.x0 + 1, bh = b.y1 - b.y0 + 1; return bh < alto * 0.22 && bw < alto * 0.22 && bw <= bh * 1.6 && bh <= bw * (AJ.chico ? 2.4 : 1.6); };
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
// (Sin el "7 con patita" abcf: en una foto de verdad un 0 con reflejo abajo da justo abcf, y salía 85.7 por 85.0.)
const NUM = { abcdef: '0', bc: '1', abdeg: '2', abcdg: '3', bcfg: '4', acdfg: '5', acdefg: '6', cdefg: '6', abc: '7', abcdefg: '8', abcdfg: '9', abcfg: '9' };
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
  // (las letritas de los iconos de arriba también son puntitos: aquí solo se corta lo muy rasposo; lo fino se
  // revisa más abajo, nada más cerca de los números)
  if(puntitos > M.w * M.h * (AJ.ruido ? 0.006 : 0.0015)) return no('ruidoso');
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
  { // Ruido junto a los números: ahí sí, una pantalla de verdad está limpia.
    const rx0 = linea[0].x0 - ref * 0.6, rx1 = linea[linea.length - 1].x1 + ref * 0.6, ry0 = cy - ref * 0.75, ry1 = cy + ref * 0.75;
    const cerca = todas.filter(b => !b.borde && b.area < 8 && (b.x0 + b.x1) / 2 >= rx0 && (b.x0 + b.x1) / 2 <= rx1 && (b.y0 + b.y1) / 2 >= ry0 && (b.y0 + b.y1) / 2 <= ry1).length;
    if(AJ.ruido && cerca > Math.max(3, (rx1 - rx0) * (ry1 - ry0) * 0.0025)) return no('ruidoso');
  }
  const dentroDe = (b) => linea.some(L => b.x0 >= L.x0 - 2 && b.x1 <= L.x1 + 2);
  if((ls.fuertes || []).some(b => !dentroDe(b))) return no('m4');
  // Tampoco puede quedar un pedazo suelto (una raya de arriba que se despegó) entre los números o pegado a ellos:
  // un 7 sin su raya de arriba parece 1.
  const x0l = linea[0].x0 - ref * 0.5, x1l = linea[linea.length - 1].x1 + ref * 0.15;
  if(ls.some(L => !L.punto && !linea.includes(L) && L.x1 >= x0l && L.x0 <= x1l && centro(L) >= cy - ref * 0.75 && centro(L) <= cy + ref * 0.75)) return no('suelto');
  // Ni a la derecha del último número: piezas que suben a la mitad de arriba del renglón son un número roto que no
  // se reconoció (99.9 leído "99"). La unidad (%) no cuenta: va abajo.
  if(AJ.sder){ const ult = linea[linea.length - 1], topL = Math.min(...linea.map(L => L.y0));
    if(todas.some(b => !b.borde && b.area >= 8 && b.x0 > ult.x1 && b.x0 <= ult.x1 + ref * 1.1 && b.y0 < cy - ref * 0.15 && b.y1 > topL + ref * 0.1 && (b.y1 - b.y0 + 1) >= ref * 0.25)) return no('suelto-der'); }
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
  // Entre dos números sin punto no puede quedar nada abajo: si hay una manchita ahí que no se reconoció como punto,
  // el número saldría sin su decimal (99.9 leído 999). Mejor no dar nada.
  { const tinta = todas.filter(b => !b.borde && b.area >= 3);
    for(let i = 0; i + 1 < leidos.length; i++){
      const A = leidos[i].L, B = leidos[i + 1].L, ya = (A.y0 + A.y1) / 2;
      const yaHay = puntos.some(p => p.x0 >= A.x1 - ref * 0.15 && p.x1 <= B.x0 + ref * 0.15);
      if(yaHay || !AJ.pduda) continue;
      if(tinta.some(b => { const x = (b.x0 + b.x1) / 2, y = (b.y0 + b.y1) / 2; return x > A.x1 + 1 && x < B.x0 - 1 && y > ya + ref * 0.15 && y < base + ref * 0.15; })) return no('punto-duda');
    } }
  if(/\.\d\d/.test(texto)) return no('decimales');   // dos o más decimales: no es de un medidor de humedad
  // Un punto después del último número: falta el decimal (se perdió un número). No se da "99" por 99.9.
  if(AJ.pfinal){ const ult = leidos[leidos.length - 1].L; if(puntos.some(p => p.x0 >= ult.x1 - ref * 0.15 && p.x0 <= ult.x1 + ref * 0.6)) return no('punto-final'); }
  // Los números leídos tienen que explicar la mayoría de lo oscuro del cuadro. Si sobra mucha tinta sin explicar,
  // se leyó media pantalla (el ángulo equivocado) y el número saldría mal.
  const dentro = (b) => { const x = (b.x0 + b.x1) / 2, y = (b.y0 + b.y1) / 2; return linea.some(L => x >= L.x0 - 1 && x <= L.x1 + 1 && y >= L.y0 - 1 && y <= L.y1 + 1); };
  let tinta = 0, cubierta = 0;
  // No cuentan: lo que va a la derecha de los números (la unidad, %) ni los iconos de arriba a un lado.
  const iniX = linea[0].x0, finX = linea[linea.length - 1].x1, topY = Math.min(...linea.map(L => L.y0));
  // Solo cuenta la tinta del renglón leído y lo que está pegado a él: los iconos de arriba, la gráfica de barras y
  // el renglón chico de abajo (la temperatura) son otra cosa (fotos de verdad, 14-oct). Un número que se perdió
  // de este renglón sí queda adentro y sí se nota.
  const botY = base;
  todas.forEach(b => { if(b.borde || b.area < 8) return;
    const x = (b.x0 + b.x1) / 2, y = (b.y0 + b.y1) / 2;
    if(AJ.cubreF && (y < topY - ref * 0.3 || y > botY + ref * 0.3 || x < iniX - ref * 0.8 || x > finX + ref * 1.3)) return;
    if(x > finX + ref * 0.1 && y > topY + ref * 0.5 && (b.y1 - b.y0 + 1) < ref * 0.55) return;   // la unidad (%): chica y abajo
    if(y < topY && x < iniX - ref * 0.15) return;
    tinta += b.area; if(dentro(b)) cubierta += b.area; });
  const cubre = tinta ? cubierta / tinta : 0;
  if(cubre < 0.55) return no('cubre');
  return { texto, seguro, digitos: leidos.length, cubre };
}
export const INCLINACIONES = [0, 0.06, 0.12, 0.18, 0.24, 0.3, -0.06, -0.12, -0.18, -0.24, -0.3];
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

// ---------- 6. la pantallita dentro del cuadro (fotos de verdad, 14-oct) ----------
// En las fotos reales (CompanyCam, medidor GENERAL) el cuadro guía agarra también el cuerpo del medidor: su textura
// llenaba la máscara de puntitos y el lector se rendía ("ruidoso"). La pantallita es la mancha clara más grande del
// cuadro: se busca, se mide qué tan chueca está (sus momentos) y se recorta ya derecha, para leer solo eso.
function otsu(g){
  const hist = new Float64Array(256); for(let i = 0; i < g.length; i++) hist[Math.max(0, Math.min(255, g[i] | 0))]++;
  let total = g.length, suma = 0; for(let i = 0; i < 256; i++) suma += i * hist[i];
  let sB = 0, wB = 0, mejor = 0, t = 128;
  for(let i = 0; i < 256; i++){ wB += hist[i]; if(!wB) continue; const wF = total - wB; if(!wF) break; sB += i * hist[i];
    const mB = sB / wB, mF = (suma - sB) / wF, v = wB * wF * (mB - mF) * (mB - mF); if(v > mejor){ mejor = v; t = i; } }
  return t;
}
export function buscarPanel(img, caja, G){
  // Lo que separa la pantallita de lo que la rodea es el COLOR (verde con luz contra plástico gris, o clara contra
  // cuerpo negro), no lo claro: en gris el plástico brilla igual que la pantalla. Se mide qué tan lejos está cada
  // punto del color de la orilla del cuadro (el cuerpo del medidor) y se queda lo que se aleja.
  const { width: W, data } = img, { w, h } = G;
  const x0 = Math.max(0, Math.floor(caja ? caja.x : 0)), y0 = Math.max(0, Math.floor(caja ? caja.y : 0));
  const wc = Math.min(W - x0, Math.floor(caja ? caja.w : W)), k = wc / w;
  const rgb = new Float32Array(w * h * 3);
  for(let y = 0; y < h; y++) for(let x = 0; x < w; x++){
    const i = (Math.min(img.height - 1, Math.floor(y0 + (y + 0.5) * k)) * W + Math.min(W - 1, Math.floor(x0 + (x + 0.5) * k))) * 4;
    rgb[(y * w + x) * 3] = data[i]; rgb[(y * w + x) * 3 + 1] = data[i + 1]; rgb[(y * w + x) * 3 + 2] = data[i + 2];
  }
  const anillo = [[], [], []], ox = Math.max(1, Math.round(w * 0.06)), oy = Math.max(1, Math.round(h * 0.06));
  for(let y = 0; y < h; y++) for(let x = 0; x < w; x++) if(x < ox || y < oy || x >= w - ox || y >= h - oy) for(let c = 0; c < 3; c++) anillo[c].push(rgb[(y * w + x) * 3 + c]);
  const med = anillo.map(a => { a.sort((p, q) => p - q); return a[a.length >> 1]; });
  const f = new Float32Array(w * h);
  for(let i = 0; i < w * h; i++){ const dr = rgb[i * 3] - med[0], dg = rgb[i * 3 + 1] - med[1], db = rgb[i * 3 + 2] - med[2]; f[i] = Math.min(255, Math.sqrt(dr * dr + dg * dg + db * db)); }
  let fmax = 0; for(let i = 0; i < f.length; i++) if(f[i] > fmax) fmax = f[i];
  if(fmax < 40) return null;   // nada se distingue de la orilla
  const t = Math.max(30, otsu(f)), m = new Uint8Array(w * h);
  for(let i = 0; i < f.length; i++) m[i] = f[i] > t ? 1 : 0;
  // Los números (oscuros) también se alejan del color de la orilla en otra dirección: se cierran los huecos de la
  // pantalla rellenando por renglón y columna lo que queda entre dos partes de la mancha (cerradura).
  const cerrar = (mm) => { const o = mm.slice(); const r = Math.max(2, Math.round(h * 0.05));
    for(let y = 0; y < h; y++) for(let x = 0; x < w; x++){ if(mm[y * w + x]) continue;
      let iz = false, de = false, ar = false, ab = false;
      for(let d = 1; d <= r && !(iz && de && ar && ab); d++){ if(x - d >= 0 && mm[y * w + x - d]) iz = true; if(x + d < w && mm[y * w + x + d]) de = true; if(y - d >= 0 && mm[(y - d) * w + x]) ar = true; if(y + d < h && mm[(y + d) * w + x]) ab = true; }
      if((iz && de) || (ar && ab)) o[y * w + x] = 1; }
    return o; };
  const mc = cerrar(m);
  const et = new Int32Array(w * h), pila = []; let mejor = null, n = 0;
  for(let i = 0; i < mc.length; i++){
    if(!mc[i] || et[i]) continue; n++;
    let area = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, ax0 = w, ax1 = 0, ay0 = h, ay1 = 0; pila.push(i); et[i] = n;
    while(pila.length){
      const j = pila.pop(), x = j % w, y = (j - x) / w; area++; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y;
      if(x < ax0) ax0 = x; if(x > ax1) ax1 = x; if(y < ay0) ay0 = y; if(y > ay1) ay1 = y;
      for(const v of [x > 0 ? j - 1 : -1, x < w - 1 ? j + 1 : -1, j - w, j + w]) if(v >= 0 && v < mc.length && mc[v] && !et[v]){ et[v] = n; pila.push(v); }
    }
    const bordes = (ax0 === 0) + (ay0 === 0) + (ax1 === w - 1) + (ay1 === h - 1);
    if(area < w * h * 0.08 || bordes >= 3) continue;
    if(!mejor || area > mejor.area) mejor = { id: n, area, cx: sx / area, cy: sy / area, mxx: sxx / area, myy: syy / area, mxy: sxy / area };
  }
  const m2 = mc;
  if(!mejor) return null;
  const { cx, cy } = mejor, u20 = mejor.mxx - cx * cx, u02 = mejor.myy - cy * cy, u11 = mejor.mxy - cx * cy;
  let ang = 0.5 * Math.atan2(2 * u11, u20 - u02);
  if(ang > Math.PI / 4) ang -= Math.PI / 2; else if(ang < -Math.PI / 4) ang += Math.PI / 2;   // la pantalla va parada o acostada; el texto, derecho
  const c = Math.cos(ang), s = Math.sin(ang), us = [], vs = [];
  for(let i = 0; i < m2.length; i++) if(et[i] === mejor.id){ const x = i % w, y = (i - x) / w; us.push((x - cx) * c + (y - cy) * s); vs.push(-(x - cx) * s + (y - cy) * c); }
  const pct = (a, p) => { a.sort((p1, p2) => p1 - p2); return a[Math.min(a.length - 1, Math.max(0, Math.floor(a.length * p)))]; };
  const u0 = pct(us, 0.01), u1 = pct(us, 0.99), v0 = pct(vs, 0.01), v1 = pct(vs, 0.99);
  // Un rectángulo lleno de verdad: lo claro debe cubrir buena parte de su caja (los números le hacen huecos).
  const relleno = mejor.area / Math.max(1, (u1 - u0) * (v1 - v0));
  if(relleno < 0.5) return null;
  return { cx, cy, ang, u0, u1, v0, v1 };
}
// Recorta la pantallita ya derecha, de la foto original (no del cuadro chico), a ~160 px de alto.
export function recortarPanel(img, caja, G, P){
  const { width: W, height: H, data } = img;
  const x0 = Math.max(0, Math.floor(caja ? caja.x : 0)), y0 = Math.max(0, Math.floor(caja ? caja.y : 0));
  const wc = Math.min(W - x0, Math.floor(caja ? caja.w : W));
  const k = wc / G.w;   // pixeles de la foto por pixel del cuadro chico
  const mu = (P.u1 - P.u0) * 0.03, mv = (P.v1 - P.v0) * 0.03;   // un poquito hacia adentro: fuera la orilla del marco
  const pu0 = P.u0 + mu, pu1 = P.u1 - mu, pv0 = P.v0 + mv, pv1 = P.v1 - mv;
  const altoFoto = (pv1 - pv0) * k, oh = Math.max(16, Math.min(160, Math.round(altoFoto))), esc = oh / altoFoto;
  const ow = Math.max(16, Math.round((pu1 - pu0) * k * esc)), g = new Float32Array(ow * oh);
  const c = Math.cos(P.ang), s = Math.sin(P.ang), paso = 1 / esc, sub = Math.max(1, Math.min(4, Math.round(paso)));
  const lum = (x, y) => { const xi = Math.max(0, Math.min(W - 1, x | 0)), yi = Math.max(0, Math.min(H - 1, y | 0)), i = (yi * W + xi) * 4; return data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114; };
  for(let y = 0; y < oh; y++) for(let x = 0; x < ow; x++){
    let suma = 0;
    for(let a = 0; a < sub; a++) for(let b = 0; b < sub; b++){
      const u = pu0 + (x + (b + 0.5) / sub) / (esc * k), v = pv0 + (y + (a + 0.5) / sub) / (esc * k);
      const gx = P.cx + u * c - v * s, gy = P.cy + u * s + v * c;   // en el cuadro chico
      suma += lum(x0 + gx * k, y0 + gy * k);
    }
    g[y * ow + x] = suma / (sub * sub);
  }
  return { g, w: ow, h: oh };
}
// Qué tan chueco va el texto: se prueban ángulos y gana el que deja los renglones más parejos (lo oscuro se amontona
// en pocas filas). Así se endereza un escaneo; aquí, la pantallita.
export function inclinacionTexto(G){
  const M = umbral(G, 0.12), pts = [];
  for(let y = 0; y < M.h; y++) for(let x = 0; x < M.w; x++) if(M.m[y * M.w + x]) pts.push(x - M.w / 2, y - M.h / 2);
  if(pts.length < 40) return 0;
  let mejor = 0, mejorV = -1, cero = 0;
  for(let g = -20; g <= 20; g += 1){
    const a = g * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), off = M.w + M.h, hist = new Float64Array(2 * off + 2);
    for(let i = 0; i < pts.length; i += 2){ const yy = Math.round(-pts[i] * s + pts[i + 1] * c) + off; hist[yy]++; }
    let v = 0; for(let i = 0; i < hist.length; i++) v += hist[i] * hist[i];
    if(g === 0) cero = v;
    if(v > mejorV){ mejorV = v; mejor = g; }
  }
  // Solo se gira si de verdad empareja mucho más que derecho (con pocos números el conteo engaña).
  return mejorV > cero * 1.15 ? mejor : 0;
}
export let VOTOS = null; export function _votos(v){ VOTOS = v; }
export function _leerG(G0s, giros){ return leerG(G0s, giros); }
// Prueba muchas formas de ver la pantalla (giros, cortes, cursivas) y se queda con la lectura más completa, contando
// también cuántas formas la repiten.
function leerG(G0s, giros){
  let mejor = null; const cuenta = {};
  for(const giro of giros) for(const G0 of G0s) for(const k of [0.12, 0.2]){
    const M = umbral(girar(G0, giro), k); if(M.contraste < 25) continue;
    for(const s of INCLINACIONES){
      const r = leerMascara(enderezar(M, s)); if(!r) continue;
      const puntaje = r.digitos * 2 + r.seguro + r.cubre - Math.abs(s) * 0.5 - Math.abs(giro) * 0.05;
      cuenta[r.texto] = (cuenta[r.texto] || 0) + 1; if(VOTOS) VOTOS.push(r.texto);
      if(!mejor || puntaje > mejor.puntaje) mejor = { ...r, puntaje, como: { giro, k, s, inv: G0s.indexOf(G0) } };
    }
  }
  if(mejor){ mejor.votos = cuenta[mejor.texto]; mejor.otros = Math.max(0, ...Object.entries(cuenta).filter(([t]) => t !== mejor.texto).map(([, n]) => n)); }
  return mejor;
}
// La regla de las fotos de verdad (14-oct, 26 fotos de CompanyCam con la caja puesta de 20 formas distintas): una
// lectura buena se repite al ver la pantalla de varias formas; una mala sale de una sola. Se pide que la misma lectura
// salga al menos 4 veces y el doble que cualquier otra, y que tenga 2 cifras o más (un número suelto puede ser
// cualquier rayita; los medidores muestran el decimal: 7.0, no 7). Con esto: 0 lecturas malas en 540 intentos.
export const MIN_VOTOS = 4;
function firme(r){ return !!r && r.digitos >= 2 && r.votos >= MIN_VOTOS && r.votos >= 2 * r.otros; }
export let SIN_PANTALLA = true;
export function leerPantalla(img, caja){
  const G = grises(img, caja);
  const listo = (r) => { if(!r) return null; const valor = Number(r.texto); if(!isFinite(valor) || valor > 1000) return null;
    return { texto: r.texto, valor, seguro: Math.round(r.seguro * 100) / 100 }; };
  // Primero la pantallita sola (lo normal en una foto de verdad). Si se encontró la pantalla pero no se entiende, NO
  // se buscan números en el resto del cuadro: ahí salían lecturas falsas (un "8" del cuerpo del medidor). El técnico
  // lo escribe.
  const P = buscarPanel(img, caja, G);
  if(P){
    const Gp = recortarPanel(img, caja, G, P), t = inclinacionTexto(Gp);
    const giros = [...new Set([t, t + 2, t - 2, 0, 3, -3])];
    const r = leerG([Gp, { ...Gp, g: Gp.g.map(v => 255 - v) }], giros);
    return firme(r) ? listo(r) : null;
  }
  // Sin pantalla clara (lo normal cuando la pantalla llena la caja): todo el cuadro, solo números oscuros sobre fondo
  // claro. Al revés salían "1.1" de las orillas de una madera; y una lectura de puros unos (11, 1.1) aquí no se cree:
  // cualquier orilla parada parece un 1.
  if(!SIN_PANTALLA) return null;
  const t = inclinacionTexto(G);
  const r = leerG([G], [...new Set([t, t + 2, t - 2, 0, 3, -3])]);
  if(r && /^[1.]+$/.test(r.texto)) return null;
  return firme(r) ? listo(r) : null;
}
