#!/bin/bash
# LA MALLA POR CUARTO (16 oct 2026): la ubicación trae un error (giro + movimiento, de pulgadas a pies) y el láser ve
# algunas paredes del cuarto (con ruido, recortadas, con caras de muebles y la del cuarto de al lado). MallaDelCuarto.swift
# afina la ubicación de ese cuarto: ¿las esquinas de la malla caen donde están? Y la memoria de cada pared (la tele).
# Uso: bash tests/malla_cuarto_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
A="$DIR/../ios/App/App"
OUT="$(mktemp -d -t malla)"
xcrun swiftc -O -o "$OUT/malla" "$DIR/malla_cuarto/main.swift" "$A/MallaDelCuarto.swift" "$A/DemolicionEnPlano.swift" \
  "$A/ComparadorDeDemolicion.swift" "$A/ComparadorDeTecho.swift" 2>&1 | grep -E "error" | head -10 || true
"$OUT/malla"
