#!/bin/bash
# 17-oct: el nombre dicho/escrito en la cámara se empareja con los cuartos del proyecto (struct CuartosDelProyecto, sacado del Swift).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/RoomScanViewController.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
OUT="$(mktemp -t cuartos).swift"
python3 - "$RAIZ/ios/App/App/RoomScanViewController.swift" "$OUT" <<'PYEOF'
import io, sys
src = io.open(sys.argv[1], encoding='utf-8').read()
i = src.index('struct CuartosDelProyecto {'); j = src.index('{', i); d = 0; k = j
while True:
    c = src[k]
    if c == '{': d += 1
    elif c == '}':
        d -= 1
        if d == 0: break
    k += 1
prueba = r'''
import Foundation
''' + src[i:k+1] + r'''
typealias C = CuartosDelProyecto
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool) { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l) } }
func tr(_ s: String) -> String { ["cocina": "Kitchen", "sala": "Living Room", "recamara principal": "Master Bedroom"][C.normal(s)] ?? s }
let p = ["Kitchen", "Master Bedroom", "Bedroom 1", "Bedroom 2", "Living Room", "Hallway"]
ok("master -> Master Bedroom", C.emparejar("master", con: p) == "Master Bedroom")
ok("kitchen -> Kitchen", C.emparejar("kitchen", con: p) == "Kitchen")
ok("KITCHEN. con mayúsculas/puntos", C.emparejar(" KITCHEN. ", con: p) == "Kitchen")
ok("cocina (traducido) -> Kitchen", C.emparejar("Cocina", con: p, traducir: tr) == "Kitchen")
ok("living -> Living Room", C.emparejar("living", con: p) == "Living Room")
ok("bedroom 2 -> Bedroom 2", C.emparejar("bedroom 2", con: p) == "Bedroom 2")
ok("bedroom 3 NO se junta con otro", C.emparejar("bedroom 3", con: p) == nil)
ok("bedroom (ambiguo) se queda lo dicho", C.emparejar("bedroom", con: p) == nil)
ok("room solo (relleno) no empareja", C.emparejar("room", con: p) == nil)
ok("garage (no está) = nil", C.emparejar("garage", con: p) == nil)
ok("hall -> Hallway (prefijo corto no, 4+ sí)", C.emparejar("hall", con: p) == "Hallway")
ok("Master Bedroom no se vuelve Bedroom", C.emparejar("Master Bedroom", con: ["Bedroom", "Kitchen"]) == nil)
ok("acentos: baño -> Baño", C.emparejar("bano", con: ["Baño"]) == "Baño")
ok("bedroom contra solo Master Bedroom = nil", C.emparejar("bedroom", con: ["Master Bedroom"]) == nil)
ok("bathroom contra solo Master Bathroom = nil", C.emparejar("bathroom", con: ["Master Bathroom"]) == nil)
ok("closet contra solo Master Closet = nil", C.emparejar("closet", con: ["Master Bedroom", "Master Closet"]) == nil)
ok("bedroom contra solo Bedroom 2 = nil (sin número)", C.emparejar("bedroom", con: ["Bedroom 2"]) == nil)
ok("master ya usado en este escaneo = nil", C.emparejar("master", con: ["Master Bedroom"], usados: ["Master Bedroom"]) == nil)
ok("igual exacto sí aunque ya esté usado", C.emparejar("master bedroom", con: ["Master Bedroom"], usados: ["Master Bedroom"]) == "Master Bedroom")
ok("lista vacía = nil (como antes)", C.emparejar("kitchen", con: []) == nil)
ok("botones: proyecto primero, sin repetir", C.botones(proyecto: ["Kitchen", "Master Bedroom"], deSiempre: ["Living Room", "kitchen"]) == ["Kitchen", "Master Bedroom", "Living Room"])
ok("disponibles: quita lo ya puesto", C.disponibles(proyecto: p, usados: ["kitchen", "Hallway"]) == ["Master Bedroom", "Bedroom 1", "Bedroom 2", "Living Room"])
ok("disponibles: el activo se queda", C.disponibles(proyecto: ["Kitchen", "Hallway"], usados: ["Kitchen"], conservar: "Kitchen") == ["Kitchen", "Hallway"])
ok("disponibles: nada usado = todos", C.disponibles(proyecto: ["Kitchen"], usados: []) == ["Kitchen"])
ok("sugerencias: liv -> Living Room", C.sugerencias("liv", en: p) == ["Living Room"])
ok("sugerencias: bed -> los 3 bedrooms", C.sugerencias("bed", en: p) == ["Master Bedroom", "Bedroom 1", "Bedroom 2"])
ok("sugerencias: KIT con mayúsculas", C.sugerencias("KIT", en: p) == ["Kitchen"])
ok("sugerencias: vacío = todos", C.sugerencias("  ", en: p) == p)
ok("sugerencias: garage = ninguna", C.sugerencias("garage", en: p).isEmpty)
print("\n\(pasan) pasan, \(fallan) fallan"); if fallan > 0 { exit(1) }
'''
io.open(sys.argv[2], 'w', encoding='utf-8').write(prueba)
PYEOF
swiftc -o "${OUT%.swift}" "$OUT" 2>&1 | grep -v warning || true
"${OUT%.swift}"
