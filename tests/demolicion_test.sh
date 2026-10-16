#!/bin/bash
# PROBAR LO DEMOLIDO (15 oct 2026): compila el comparador REAL (ios/App/App/ComparadorDeDemolicion.swift) con el banco
# sintético (tests/demolicion/main.swift) y lo corre: cortes de 2 y 4 ft, 2x4 y 2x6, studs a 16 y 24 in, y los casos
# peligrosos (pared entera con la mancha del agua, insulación puesta, secador delante, espejo, paso abierto, sótano sin
# terminar, sin piso). Error CON SIGNO en cada caso.
# Uso: bash tests/demolicion_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d -t demolicion)"
xcrun swiftc -O -o "$OUT/banco" "$DIR/../ios/App/App/ComparadorDeDemolicion.swift" "$DIR/demolicion/escena.swift" "$DIR/demolicion/main.swift" 2>&1 | grep -E "error" | head -10 || true
"$OUT/banco"
# La grabadora, de punta a punta: grabar mapas como los del iPhone, leerlos de vuelta y dar el MISMO número.
xcrun swiftc -O -o "$OUT/grabacion" "$DIR/../ios/App/App/ComparadorDeDemolicion.swift" "$DIR/../ios/App/App/GrabadoraDeBarrido.swift" "$DIR/demolicion/escena.swift" "$DIR/demolicion_grabacion/main.swift" 2>&1 | grep -E "error" | head -10 || true
"$OUT/grabacion" "$OUT"
