#!/usr/bin/env bash
# Builds the Flutter web app and bundles it into assets/web/web_app.zip.
# The game server serves it over HTTP on the room port, so players can join
# from any browser by scanning the room QR code - no install needed.
#
# Run from the repo root:  ./tool/bundle_web_app.sh
# Then rebuild the app so the asset is included.
set -euo pipefail

flutter build web

mkdir -p assets/web
rm -f assets/web/web_app.zip
(cd build/web && zip -qr ../../assets/web/web_app.zip .)

echo "Created assets/web/web_app.zip"
echo "Rebuild the app (flutter run / flutter build) to embed it."
