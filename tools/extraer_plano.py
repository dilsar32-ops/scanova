#!/usr/bin/env python3
"""Copia de Field Reports (www/index.html) SOLO el código que dibuja el plano, para Scanova360.
No toca Field Reports. Arma el cierre de dependencias desde las raíces y escribe docs/plano.js.
Uso: python3 tools/extraer_plano.py [ruta a field-report-ios-app]"""
import re, sys, os, json
FR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Downloads/field-report-ios-app')
src = open(os.path.join(FR, 'www', 'index.html'), encoding='utf-8').read()
ROOTS = ['buildFloorplanSvg', 'buildFloorplanSvgUnmerged', 'floorplanLevels', 'fpRoomDisplayAreaSqFt',
         'fpDisplayTotalAreaSqFt', 'fpOrderedRoomPolygon', 'fpPolygonAreaSqFt', 'fpFeetInches',
         'fpPlanMeasurements', 'fpRoomMeasurements', 'floorplanIsExteriorWall',
         # lo que Field Reports le hace a cada escaneo al recibirlo: enderezarlo, escuadrarlo, cerrar esquinas
         'floorplanAlignRooms', 'floorplanRectifyWalls', 'floorplanRefineGeometry', 'floorplanCloseCorners']
ROOTS += [r for r in (sys.argv[2].split(',') if len(sys.argv) > 2 else []) if r]
defs = {}   # nombre -> (orden, texto)
SIG = re.compile(r'\n  (?=[A-Za-z_$/])')
def bloque(i):
    # Estilo del archivo: cada declaración de primer nivel empieza con 2 espacios; termina donde empieza la siguiente.
    m = SIG.search(src, src.index('\n', i))
    return m.start() + 1 if m else len(src)
for m in re.finditer(r'\n  (?:async )?function ([A-Za-z0-9_$]+)\(', src):
    i = m.start() + 1; defs.setdefault(m.group(1), (i, src[i:bloque(i)]))
for m in re.finditer(r'\n  (?:const|let|var) ([A-Za-z0-9_$]+)\s*=', src):
    i = m.start() + 1; n = m.group(1)
    if n not in defs: defs[n] = (i, src[i:bloque(i)])
ident = re.compile(r'[A-Za-z_$][A-Za-z0-9_$]*')
need, cola = set(), list(ROOTS)
while cola:
    n = cola.pop()
    if n in need or n not in defs: continue
    need.add(n)
    for t in set(ident.findall(defs[n][1])):
        if t in defs and t not in need: cola.append(t)
falta = [r for r in ROOTS if r not in defs]
if falta: raise SystemExit('no encontré: ' + ', '.join(falta))
# Piezas que en Field Reports leen la pantalla o el almacén del teléfono: en Scanova van en versión pura.
REEMPLAZOS = {
  'esc': "  function esc(str){ return String(str == null ? '' : str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\"/g, '&quot;').replace(/'/g, '&#39;'); }\n",
  '$': "  const $ = (sel, el) => { const d = el || (typeof document !== 'undefined' ? document : null); return d && d.querySelector ? d.querySelector(sel) : null; };\n",
  'fpLoadLabelLearning': "  function fpLoadLabelLearning(){ return []; }\n",
  'fpJobInfo': "  function fpJobInfo(){ return FP_JOB_SCANOVA; }\n  let FP_JOB_SCANOVA = { client:'', address:'', date:'', claim:'', tech:'', phone:'' };\n  export function ponerTrabajo(j){ FP_JOB_SCANOVA = Object.assign({ client:'', address:'', date:'', claim:'', tech:'', phone:'' }, j || {}); }\n",
}
for n, t in REEMPLAZOS.items():
    if n in need: defs[n] = (defs[n][0], t)
partes = sorted((defs[n][0], n, defs[n][1]) for n in need)
dom = [n for _, n, t in partes if re.search(r'\bdocument\.|\$\(|\$\$\(|localStorage', t)]
cab = ('// GENERADO por tools/extraer_plano.py desde Field Reports (no editar a mano: se vuelve a generar).\n'
       '// Dibuja el plano igual que Field Reports. ' + str(len(partes)) + ' piezas.\n'
       '/* eslint-disable */\nconst document = (typeof globalThis !== "undefined" && globalThis.document) || undefined;\n')
out = cab + '\n'.join(t.rstrip() + ('' if t.rstrip().endswith((';', '}')) else ';') for _, n, t in partes)
out += '\nexport { ' + ', '.join(ROOTS) + ' };\n'
# VISTA LIMPIA (su pedido del 13-oct): en la pantalla se ve SOLO el plano, lo más grande posible —
# paredes, puertas, ventanas y el nombre + medida de cada cuarto. Las medidas de cada pared, el sello,
# la leyenda, la brújula y el margen ancho son de la hoja del PDF/exportar, que no cambia.
VISTA = [
  ("const pad = 3.0;", "const pad = FP_VISTA_LIMPIA ? 1.0 : 3.0;", 2),
  ("if(effLen >= 0.25 && !seenNear('dim', midX, midY)){", "if(!FP_VISTA_LIMPIA && effLen >= 0.25 && !seenNear('dim', midX, midY)){", 1),
  ("s += fpCompassAndScale(svgW, svgH, scale);", "if(!FP_VISTA_LIMPIA) s += fpCompassAndScale(svgW, svgH, scale);", 1),
  ("out += fpCompassAndScale(svgW, svgH, scale);", "if(!FP_VISTA_LIMPIA) out += fpCompassAndScale(svgW, svgH, scale);", 1),
  ('out += `<rect x="1" y="1" width="${svgW-2}" height="${svgH-2}"', 'if(!FP_VISTA_LIMPIA) out += `<rect x="1" y="1" width="${svgW-2}" height="${svgH-2}"', 1),
  ("if(fpMeasurePrefs.openings){", "if(fpMeasurePrefs.openings && !FP_VISTA_LIMPIA){", 2),
  ('y="${labelY-48*k}"', 'y="${labelY-(FP_VISTA_LIMPIA ? 32 : 48)*k}"', 1),
  ('y="${labelY-14*k}"', 'y="${labelY+(FP_VISTA_LIMPIA ? 2 : -14)*k}"', 1),
  ('+ `<text x="${labelX}" y="${labelY+18*k}"', '+ (FP_VISTA_LIMPIA ? \'\' : `<text x="${labelX}" y="${labelY+18*k}"', 1),
  ('${areaTxt}</text>`', '${areaTxt}</text>`)', 1),
  # En la vista limpia el plano entra entero en la pantalla del teléfono: el nombre del cuarto crece
  # hasta donde quepa DENTRO de su cuarto (nunca se sale), para que se pueda leer sin acercar.
  ("const k = kAuto * (room._labelScale || 1);", "const k = FP_VISTA_LIMPIA ? fpKVista(label, dimTxt, rb, X, Y, labelX, labelY) : kAuto * (room._labelScale || 1);", 1),
]
for a, b, n in VISTA:
    assert out.count(a) == n, ('vista limpia: esperaba %d de %r, hay %d' % (n, a, out.count(a)))
    out = out.replace(a, b)
out = out.replace('\nexport { ', "\n  let FP_VISTA_LIMPIA = false;\n  function fpKVista(label, dimTxt, rb, X, Y, lx, ly){ const w = 2 * Math.min(lx - X(rb.minX), X(rb.maxX) - lx) * 0.88, h = 2 * Math.min(ly - Y(rb.minY), Y(rb.maxY) - ly) * 0.8; const ancho = Math.max(0.64 * 30 * String(label).replace(/&[a-z#0-9]+;/g, 'x').length, 0.6 * 23 * String(dimTxt).length); return Math.max(0.5, Math.min(2.4, w / ancho, h / 70)); }\n  export function ponerVista(limpia){ FP_VISTA_LIMPIA = !!limpia; fpSheetExport = !!limpia; }\nexport { ", 1)
# Scanova no dice el nombre de la otra empresa en el sello del plano.
out = out.replace("'Restoration Doctor'", "'Scanova360'")
assert 'Restoration Doctor' not in out and 'RESTORATION DOCTOR' not in out, 'quedo el nombre de la otra empresa'
dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'plano.js')
open(dest, 'w', encoding='utf-8').write(out)
print('piezas', len(partes), 'lineas', out.count('\n'), 'con DOM/almacen:', ', '.join(dom[:40]))
