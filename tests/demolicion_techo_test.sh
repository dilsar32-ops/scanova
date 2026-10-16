#!/bin/bash
# LO DEMOLIDO EN EL TECHO, EN 3D (15 oct 2026): un cuarto con su techo de drywall, vigas (2x8 cada 16, 2x10 cada 24) o
# ático (cerchas), huecos de todas las formas (en medio, pegados a la pared, en la esquina, dos, en L, todo el techo,
# uno chico de inspección) y los controles que nunca cuentan (lámparas empotradas, rejilla, abanico, la mancha del agua).
# El teléfono camina mirando para arriba; el comparador del techo (ComparadorDeTecho.swift) junta los huecos.
# Uso: bash tests/demolicion_techo_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d -t techo)"
xcrun swiftc -O -o "$OUT/techo" "$DIR/../ios/App/App/ComparadorDeTecho.swift" "$DIR/demolicion/escena.swift" \
  "$DIR/demolicion_techo/techo.swift" "$DIR/demolicion_techo/main.swift" 2>&1 | grep -E "error" | head -10 || true
"$OUT/techo" prueba
