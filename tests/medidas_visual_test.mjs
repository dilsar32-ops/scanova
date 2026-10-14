// Prueba VISUAL de la hoja que se exporta (13-oct, su pedido): las medidas de las paredes de adentro van en
// ROJO dentro de la pared con dos puntitas, y ningún número choca con una flechita, un nombre u otro número.
import fs from 'node:fs';
const PL = await import('../docs/planos.js');
const num = v => +v;
let pass = 0, fail = 0;
const ok = (l, c, d) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l + (d ? ' -- ' + JSON.stringify(d).slice(0, 300) : '')); } };
function cajasTexto(svg){
  const res = [];
  for(const m of svg.matchAll(/<text([^>]*)>([^<]*)<\/text>/g)){
    const at = m[1], t = m[2].replace(/&[a-z#0-9]+;/g, 'x');
    const g = k => { const r = at.match(new RegExp(' ' + k + '="([^"]*)"')); return r ? r[1] : null; };
    let x = num(g('x')), y = num(g('y')); const fs_ = num(g('font-size') || 16);
    if(!isFinite(x) || !isFinite(y)) continue;
    const w = 0.58 * fs_ * t.length, h = fs_ * 0.9;
    const anchor = g('text-anchor') || 'start', base = g('dominant-baseline');
    let x0 = anchor === 'middle' ? -w/2 : anchor === 'end' ? -w : 0;
    let y0 = base === 'central' || base === 'middle' ? -h/2 : -h * 0.8;
    const dy = num(g('dy') || 0); y0 += dy;
    const rot = (at.match(/rotate\(([-\d.]+)/) || [])[1];
    const a = rot ? num(rot) * Math.PI/180 : 0;
    const pts = [[x0, y0], [x0+w, y0], [x0+w, y0+h], [x0, y0+h]].map(([px, py]) => [x + px*Math.cos(a) - py*Math.sin(a), y + px*Math.sin(a) + py*Math.cos(a)]);
    res.push({ t: m[2], rojo: /fill="#ff3b30"/.test(at), pts });
  }
  return res;
}
function flechas(svg){
  const res = [];
  for(const g of svg.matchAll(/<g class="fp-extent"[^>]*>([\s\S]*?)<\/g>/g))
    for(const p of g[1].matchAll(/points="([^"]*)"/g)) res.push({ pts: p[1].trim().split(/\s+/).map(q => q.split(',').map(Number)) });
  return res;
}
// separación de ejes (SAT) entre dos polígonos convexos
function choca(A, B, holgura = 0){
  const ejes = P => P.map((p, i) => { const q = P[(i+1) % P.length]; const ex = q[0]-p[0], ey = q[1]-p[1]; const L = Math.hypot(ex, ey) || 1; return [-ey/L, ex/L]; });
  for(const [nx, ny] of [...ejes(A), ...ejes(B)]){
    const pa = A.map(p => p[0]*nx + p[1]*ny), pb = B.map(p => p[0]*nx + p[1]*ny);
    if(Math.max(...pa) + holgura < Math.min(...pb) || Math.max(...pb) + holgura < Math.min(...pa)) return false;
  }
  return true;
}

for(const f of ['harold_4cuartos.json', 'plano_real.json']){
  const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/' + f, import.meta.url), 'utf8')); const data = JSON.parse(JSON.stringify(raw.data || raw)); delete data._handEdited;
  const hoja = PL.svgDelPlano(data, { cliente: 'x' }, false), pantalla = PL.svgDelPlano(data, { cliente: 'x' }, true);
  const T = cajasTexto(hoja), F = flechas(hoja), rojos = T.filter(x => x.rojo), otros = T.filter(x => !x.rojo);
  const choques = [];
  for(const r of rojos){
    for(const fl of F) if(fl.pts.length >= 3 && choca(r.pts, fl.pts, 1)) choques.push(r.t + ' / flecha');
    for(const o of otros) if(choca(r.pts, o.pts, 1)) choques.push(r.t + ' / ' + o.t);
  }
  for(let i = 0; i < rojos.length; i++) for(let j = i+1; j < rojos.length; j++) if(choca(rojos[i].pts, rojos[j].pts, 1)) choques.push(rojos[i].t + ' / ' + rojos[j].t);
  ok(f + ': la hoja que se exporta trae medidas de adentro en rojo', rojos.length >= 4, rojos.length);
  ok(f + ': ningún número choca con una flechita, un nombre u otro número', !choques.length, choques);
  ok(f + ': la pantalla sigue limpia (sin medidas de adentro)', !/fill="#ff3b30"/.test(pantalla));
}
console.log(`medidas visual: ${pass} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
