// Scanova360 · Documents (14-oct): lo que llevan el Dry Log Report y el Equipment Report (sin pantalla).
import fs from 'node:fs';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
// documentos.js importa app.js (pantalla); aquí solo se prueba lo puro, sacado del archivo tal cual.
const D = await import('../docs/documentos.js').catch(e => { console.log('  (no se pudo importar con app.js: ' + e.message + ')'); return null; });
if(!D){ console.log('\ndocumentos: 0 ok, 1 fallas'); process.exit(1); }
const niv = [{ id:'n2', nombre:'Second Floor' }, { id:'n1', nombre:'First Floor' }];
const cua = [{ id:'mb', nombre:'Master Bedroom', nivel_id:'n2' }, { id:'k', nombre:'Kitchen', nivel_id:'n1' }, { id:'h', nombre:'Hallway', nivel_id:'n1' }];
const L = (dia, c, mat, ub, v, foto) => ({ id: dia + c + mat, dia, cuarto_id: c, cuarto_nombre: c, material: mat, ubicacion: ub, valor: v, foto_id: foto || null, created_at: dia + 'T10:00:00Z' });
const E = (dia, c, tipo, n) => ({ dia, cuarto_id: c, tipo, cantidad: n, created_at: dia + 'T10:00:00Z' });
const lect = [L('2026-10-12', 'k', 'Drywall', 'East', 48, 'f1'), L('2026-10-12', 'mb', 'Drywall', 'Closet', 28), L('2026-10-13', 'k', 'Drywall', 'East', 30, 'f2'), L('2026-10-14', 'k', 'Drywall', 'East', 33)];
const m = D.modeloDryLog(niv, cua, lect);
ok('Dry Log: solo los cuartos con lecturas, en el orden de la app (piso de arriba primero)', m.salas.map(s => s.nombre).join() === 'Master Bedroom,Kitchen');
ok('Dry Log: una columna por día con su número', m.dias.map(d => d.n).join() === '1,2,3');
const p = m.salas[1].puntos[0];
ok('Dry Log: cada día su lectura y si bajó o subió contra la anterior', p.celdas[0].valor === 48 && !p.celdas[0].tend && p.celdas[1].tend.tipo === 'baja' && p.celdas[2].tend.tipo === 'sube');
ok('Dry Log: el cambio total del primer al último día', p.cambio === -15);
ok('Dry Log: un día sin lectura queda vacío (no se inventa)', m.salas[0].puntos[0].celdas[1] === null);
ok('Dry Log: las fotos del medidor, en orden', m.lecturasFoto.map(f => f.foto_id).join() === 'f1,f2');
const eq = [E('2026-10-12', 'k', 'Fans', 3), E('2026-10-13', 'k', 'Fans', 2), E('2026-10-12', 'mb', 'none', 0)];
const me = D.modeloEquipo(niv, cua, eq, '2026-10-14');
ok('Equipment: columna "Today" cuando hoy no hubo visita (la cuenta se ve completa)', me.dias.length === 3 && me.dias[2].hoy === true);
ok('Equipment: días de equipo 3 + 2 + 2 = 7 y el total', me.salas.find(s => s.nombre === 'Kitchen').tipos[0].dias === 7 && me.total === 7);
ok('Equipment: lo de un día sin visita se marca como "sigue"', me.salas.find(s => s.nombre === 'Kitchen').tipos[0].celdas[2].visto === false);
ok('Equipment: la regla de los días se dice en el reporte', /removal day is not counted/.test(D.REGLA_DIAS));
// Photo Report y Floor Plan (15-oct): sus secciones en Documents.
{ const fs_ = [{ id: 'a', cuarto_id: 'k', nivel_id: 'n1', tomada_at: '2026-10-12T15:00:00Z' }, { id: 'b', cuarto_id: 'mb', nivel_id: 'n2', tomada_at: '2026-10-13T09:00:00Z' },
    { id: 'c', cuarto_id: 'k', nivel_id: 'n1', tomada_at: '2026-10-12T09:00:00Z', nota: 'Wet drywall' }, { id: 'd', cuarto_id: null, nivel_id: 'n1', subida_at: '2026-10-14T09:00:00Z' },
    { id: 'e', cuarto_id: null, nivel_id: null, subida_at: '2026-10-11T09:00:00Z' }, { id: 'f1', cuarto_id: 'k', nivel_id: 'n1', tomada_at: '2026-10-12T16:00:00Z' }];
  const mf = D.modeloFotos(niv, cua, fs_, lect);
  ok('Photo Report: cuarto por cuarto en el orden del proyecto (piso de arriba primero), después "Whole level" y al final sin cuarto',
    mf.grupos.map(g => D.tituloGrupo(g)).join() === 'Master Bedroom,Kitchen,Whole First Floor,No room');
  ok('Photo Report: dentro de un cuarto, en el orden en que se tomaron', mf.grupos[1].fotos.map(f => f.id).join() === 'c,a,f1');
  ok('Photo Report: cada foto con su número, seguido de principio a fin', mf.grupos.flatMap(g => g.fotos.map(f => f.num)).join() === '1,2,3,4,5,6' && mf.total === 6);
  ok('Photo Report: la foto que prueba una lectura dice cuál lectura es', mf.grupos[1].fotos[2].lectura && mf.grupos[1].fotos[2].lectura.valor === 48);
  const mp = D.modeloPlanos(niv, [{ id: 'p1', nivel_id: 'n1', created_at: '2026-10-12' }, { id: 'p2', nivel_id: 'n1', created_at: '2026-10-14' }, { id: 'p3', nivel_id: 'n2', created_at: '2026-10-13' }]);
  ok('Floor Plan: la hoja más nueva de cada nivel, en el orden de los niveles', mp.map(x => x.nivel + ':' + x.plano.id).join() === 'Second Floor:p3,First Floor:p2'); }
const src = fs.readFileSync(new URL('../docs/documentos.js', import.meta.url), 'utf8');
ok('Send documents: todo en un PDF (portada + índice) o uno por documento', /export async function pdfTodo/.test(src) && /function portadaPdf/.test(src) && /data-doc-todo="uno"/.test(src) && /data-doc-todo="varios"/.test(src));
ok('cada reporte puede ir solo o dentro del de todo junto (las hojas nuevas con SU orientación)', (src.match(/await abrirDoc\(opc, '(portrait|landscape)'\)/g) || []).length >= 4 && !/doc\.addPage\(\);/.test(src));
ok('si la hoja de compartir ya no abre sola (el PDF tardó), queda un botón Share', /NotAllowedError/.test(src) && /data-doc-compartir/.test(src));
ok('la foto se mide ANTES de soltarla (un ImageBitmap cerrado mide 0)', /const iw = im\.width \|\| im\.naturalWidth/.test(src) && !/im\.close\(\);?\s*\n\s*return \{ d, w: Math\.round\(im\.width/.test(src));
ok('el PDF se hace aquí mismo (jsPDF de la app, sin servicio de afuera)', /vendor\/jspdf\.umd\.min\.js/.test(src) && fs.existsSync(new URL('../docs/vendor/jspdf.umd.min.js', import.meta.url)));
ok('Documents ya no dice "built next"', !/Estimates, reports and PDFs for this project will live here/.test(fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8')));
console.log(`\ndocumentos: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
