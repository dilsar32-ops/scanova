#!/usr/bin/env python3
"""Pone ?v=<BUILD> a TODAS las importaciones de la app (docs/*.js, index.html), para que al publicar el navegador
nunca mezcle archivos nuevos con viejos guardados (esa mezcla dejó la página en blanco el 13 oct 2026).
Uso: python3 tools/versionar.py 2026-10-13-4   (lo corre la publicación; también actualiza config.js y version.txt)"""
import re, sys, pathlib
build = sys.argv[1]
docs = pathlib.Path(__file__).resolve().parent.parent / 'docs'
assert re.fullmatch(r'\d{4}-\d{2}-\d{2}-\d+', build), 'build con forma 2026-10-13-4'
v = '?v=' + build
cambios = 0
# 1) importaciones entre módulos: from './x.js' / from './x.js?v=...'
pat = re.compile(r"""(from\s+['"]\./[A-Za-z0-9_\-]+\.js)(\?v=[^'"]*)?(['"])""")
for f in sorted(docs.glob('*.js')):
    s = f.read_text(encoding='utf-8'); n = pat.sub(lambda m: m.group(1) + v + m.group(3), s)
    if f.name == 'config.js': n = re.sub(r"APP_BUILD = '[^']*'", "APP_BUILD = '" + build + "'", n)
    if n != s: f.write_text(n, encoding='utf-8'); cambios += 1
# 2) index.html: la hoja de estilo y el módulo principal
idx = docs / 'index.html'; s = idx.read_text(encoding='utf-8')
n = re.sub(r'href="estilo\.css(\?v=[^"]*)?"', 'href="estilo.css' + v + '"', s)
n = re.sub(r'src="app\.js(\?v=[^"]*)?"', 'src="app.js' + v + '"', n)
if n != s: idx.write_text(n, encoding='utf-8'); cambios += 1
(docs / 'version.txt').write_text(build + '\n', encoding='utf-8')
# 2b) la página de Google (otra página, sus propias importaciones ../x.js)
g = docs / 'google' / 'index.html'
if g.exists():
    s = g.read_text(encoding='utf-8')
    n = re.sub(r"""(from\s+['"]\.\./[A-Za-z0-9_\-]+\.js)(\?v=[^'"]*)?(['"])""", lambda m: m.group(1) + v + m.group(3), s)
    if n != s: g.write_text(n, encoding='utf-8'); cambios += 1
# 3) comprobar: ninguna importación sin versión, y todas con la MISMA versión (si no, un módulo se cargaría dos veces)
for f in sorted(docs.glob('*.js')):
    for m in re.finditer(r"""from\s+['"](\./[^'"]+)['"]""", f.read_text(encoding='utf-8')):
        assert m.group(1).endswith(v), f'{f.name}: {m.group(1)} sin la versión {build}'
print(f'versionado {build}: {cambios} archivos tocados')
