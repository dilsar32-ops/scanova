// Scanova · fotos: lo puro (agrupar por día, avance de la tanda, la foto en la rejilla, huellas).
import * as F from '../docs/fotos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
// Los días se agrupan en la hora LOCAL del aparato (el día de la cuadrilla), así que las fechas
// de prueba se construyen en hora local para que la prueba dé lo mismo en cualquier zona.
const L = (y, m, d, h, mi) => new Date(y, m - 1, d, h, mi).toISOString();
const fotos = [
  { id:'a', created_by:'u1', subida_at:L(2026,10,11,18,0), tomada_at:L(2026,10,11,17,55) },
  { id:'b', created_by:'u2', subida_at:L(2026,10,11,18,5), tomada_at:L(2026,10,11,18,2) },
  { id:'c', created_by:'u1', subida_at:L(2026,10,10,15,0), tomada_at:L(2026,10,10,14,40) },
  { id:'d', created_by:'u1', subida_at:L(2026,10,12,1,0), tomada_at:null },
];
const dias = F.porDia(fotos);
ok('porDia: un grupo por día, el más reciente primero', dias.length === 3 && dias[0].fotos[0].id === 'd' && dias[2].fotos[0].id === 'c');
ok('porDia: dentro del día la más reciente primero; sin tomada_at usa subida_at', dias[1].fotos.map(f => f.id).join() === 'b,a' && F.fechaFoto(fotos[3]) === fotos[3].subida_at);
ok('porDia: título legible en español y con mayúscula', /^[A-ZÁ]/.test(dias[0].titulo) && /2026/.test(dias[0].titulo));
ok('porDia: lista vacía o nula no truena', F.porDia(null).length === 0 && F.porDia([]).length === 0);
ok('claveDia: basura = sin-fecha', F.claveDia('nada') === 'sin-fecha' && /^\d{4}-\d{2}-\d{2}$/.test(F.claveDia('2026-10-11T17:55:00Z')));
const tanda = [ { estado:'lista' }, { estado:'lista' }, { estado:'fallo' }, { estado:'repetida' }, { estado:'subiendo' }, { estado:'cola' } ];
const r = F.resumenTanda(tanda);
ok('resumenTanda: cuenta cada estado', r.total === 6 && r.listas === 2 && r.fallidas === 1 && r.repetidas === 1 && r.enCurso === 2);
ok('textoAvance: mientras sube dice cuál va de cuántas', F.textoAvance(r) === 'Uploading 5 of 6…');
ok('textoAvance: al terminar resume subidas, repetidas y fallidas', F.textoAvance({ total:4, listas:2, fallidas:1, repetidas:1, enCurso:0 }) === '2 photos uploaded · 1 already there · 1 could not upload');
ok('textoAvance: singulares y vacío', F.textoAvance({ total:1, listas:1, fallidas:0, repetidas:0, enCurso:0 }) === '1 photo uploaded' && F.textoAvance({ total:0 }) === '');
const h = F.fotoHtml({ id:'x"y' }, 'https://r2/x', 'Amilcar Gonzalez');
ok('fotoHtml: botón con el id escapado, la imagen y las iniciales de quien la tomó', /data-foto="x&quot;y"/.test(h) && /<img src="https:\/\/r2\/x"/.test(h) && />AG</.test(h));
ok('fotoHtml: sin url deja el hueco; sin nombre no pone iniciales', /ffoto-vacia/.test(F.fotoHtml({ id:'z' }, '', '')) && /class="fquien" title=""><\/span>/.test(F.fotoHtml({ id:'z' }, '', '')));
ok('esImagen: por tipo o por extensión; un PDF no', F.esImagen({ type:'image/jpeg', name:'a.jpg' }) && F.esImagen({ type:'', name:'IMG_1.HEIC' }) && !F.esImagen({ type:'application/pdf', name:'a.pdf' }) && !F.esImagen(null));
ok('hexDe: bytes a hex', F.hexDe(new Uint8Array([0, 15, 255]).buffer) === '000fff');
ok('horaTxt/diaTxt: basura no truena', F.horaTxt('nada') === '' && F.diaTxt('nada') === 'Sin fecha');
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
