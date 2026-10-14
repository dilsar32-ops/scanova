#!/bin/bash
# PUBLICAR EL APARATO DE SCANOVA360 POR ENLACE (13 oct 2026), en la MISMA página que
# Field Reports: https://dilsar32-ops.github.io/amg-reportes/app/ (botón "Instalar Scanova360").
# Los teléfonos registrados en la cuenta de Apple de la empresa lo instalan desde Safari.
# Antes: subir CURRENT_PROJECT_VERSION en ios/App/App.xcodeproj/project.pbxproj.
# Uso:  ios/distribucion/publicar.sh <clon-de-amg-reportes> <carpeta-de-trabajo>
set -e
R="$(cd "$(dirname "$0")/../.." && pwd)"; PAGES="$1"; W="${2:-/tmp/scanova-adhoc}"
[ -d "$PAGES/.git" ] || { echo "falta el clon de Pages: $PAGES"; exit 1; }
rm -rf "$W/App.xcarchive" "$W/export"; mkdir -p "$W"
cd "$R/ios/App"
xcodebuild -workspace App.xcworkspace -scheme App -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "$W/App.xcarchive" archive -allowProvisioningUpdates -derivedDataPath "$W/dd" > "$W/archive.log" 2>&1 || { tail -20 "$W/archive.log"; exit 1; }
xcodebuild -exportArchive -archivePath "$W/App.xcarchive" -exportPath "$W/export" -exportOptionsPlist "$R/ios/distribucion/export.plist" -allowProvisioningUpdates > "$W/export.log" 2>&1 || { tail -20 "$W/export.log"; exit 1; }
sed -i '' 's#<string>App</string>#<string>Scanova360</string>#' "$W/export/manifest.plist"
mkdir -p "$PAGES/app/scanova"
# La versión que el aviso de la página compara (la del CURRENT_PROJECT_VERSION de este aparato).
BUILD=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$R/ios/App/App.xcodeproj/project.pbxproj" | head -1 | grep -o '[0-9]*$')
printf '%s\n' "$BUILD" > "$PAGES/app/scanova/version.txt"
cp "$W/export/App.ipa" "$PAGES/app/scanova/Scanova360.ipa"; cp "$W/export/manifest.plist" "$PAGES/app/scanova/manifest.plist"
ICONO="$R/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
sips -z 57 57 "$ICONO" --out "$PAGES/app/scanova/icono-57.png" >/dev/null; sips -z 512 512 "$ICONO" --out "$PAGES/app/scanova/icono-512.png" >/dev/null
echo "Listo en $PAGES/app/scanova. Ahora: cd $PAGES && git add -A && git commit && git push"
