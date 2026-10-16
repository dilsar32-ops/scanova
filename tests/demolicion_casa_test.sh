#!/bin/bash
# LO DEMOLIDO EN UNA CASA 3D CON LA UBICACIÓN (16 oct 2026): un cuarto de verdad (4 paredes, esquinas con su stud,
# puertas y ventanas con su marco), cortes parciales de todas las formas, el teléfono caminando dentro del cuarto, el
# error de la ubicación, y lo que mide el comparador pasado al plano (desde qué esquina, cuánto). Varias corridas por caso.
# Uso: bash tests/demolicion_casa_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d -t casa)"
xcrun swiftc -O -o "$OUT/casa" "$DIR/../ios/App/App/ComparadorDeDemolicion.swift" "$DIR/../ios/App/App/DemolicionEnPlano.swift" \
  "$DIR/demolicion/escena.swift" "$DIR/demolicion_casa/casa.swift" "$DIR/demolicion_casa/main.swift" 2>&1 | grep -E "error" | head -10 || true
"$OUT/casa" prueba
