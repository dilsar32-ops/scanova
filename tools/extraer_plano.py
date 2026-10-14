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
         'floorplanAlignRooms', 'floorplanRectifyWalls', 'floorplanRefineGeometry', 'floorplanCloseCorners',
         # reconocer clósets/rincones (su pedido del 14-oct): la misma detección de Field Reports
         'floorplanDetectSubAreas', 'fpReconocerClosets',
         # el nombre dicho al escanear sale en inglés (su pedido del 13-oct)
         'fpNombreDeCuartoEnIngles',
         # los cuartos sin acceso, deducidos por sus paredes y su puerta (13-oct)
         'fpAutoCompletarEspacios',
         # las paredes del cuarto de al lado que se vieron por una abertura vuelven a su dueño (13-oct)
         'fpResolverParedesAjenas']
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
    # Los comentarios no son código: un nombre mencionado en un comentario arrastraba medio Field Reports.
    for t in set(ident.findall(re.sub(r'(?<![:\'"])//[^\n]*', '', defs[n][1]))):
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
# VISTA (su diseño del 14-oct): el estilo de la pantalla ya vive en Field Reports (fpEstiloVista / fpVista):
# paredes unidas, ventanas de doble línea, nombre + sq ft, cadenas de medidas por fuera y el marco con
# encabezado y pie. Scanova solo lo prende para la pantalla y lo apaga para la hoja que se exporta.
assert 'let fpEstiloVista' in out and 'function fpVista()' in out, 'falta el estilo de la vista en Field Reports'
# 14-oct: "que el PDF también lleve ese estilo" -> la imagen que se exporta es la MISMA hoja que la pantalla.
out = out.replace('\nexport { ', "\n  export function ponerVista(limpia){ fpEstiloVista = true; fpSheetExport = false; fpConTablaMedidas = !limpia; }\nexport { ", 1)
# Scanova no dice el nombre de la otra empresa en el sello del plano.
out = out.replace("'Restoration Doctor'", "'Scanova360'")
assert 'Restoration Doctor' not in out and 'RESTORATION DOCTOR' not in out, 'quedo el nombre de la otra empresa'
dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'plano.js')
open(dest, 'w', encoding='utf-8').write(out)
print('piezas', len(partes), 'lineas', out.count('\n'), 'con DOM/almacen:', ', '.join(dom[:40]))
