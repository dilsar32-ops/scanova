#!/bin/zsh
# Prueba en la Mac de la geometría pura del escáner (FloorPlanEncoder.swift, entre BEGIN PURO y END PURO):
# el acomodo de cada captura, el parche que solo agrega lo que falta y las paredes ajenas. 14-oct.
# Uso: zsh tests/marcos/correr.sh
set -e
D=${0:A:h}; E=$D/../../ios/App/App/FloorPlanEncoder.swift; T=$(mktemp -d)
a=$(grep -n "struct OutlineGap" $E | cut -d: -f1); b=$(grep -n "// END PURO" $E | cut -d: -f1)
{ echo "import Foundation"; echo "import CoreGraphics"; echo "enum FloorPlanEncoder {"; sed -n "${a},${b}p" $E; echo "}"; } > $T/puro.swift
swiftc -O $T/puro.swift $D/main.swift -o $T/marcos
$T/marcos $D/harold_sala.json $D/harold_cuartos.json
