# Builds the Flutter web app and bundles it into assets/web/web_app.zip.
# The game server serves it over HTTP on the room port, so players can join
# from any browser by scanning the room QR code - no install needed.
#
# Run from the repo root:  .\tool\bundle_web_app.ps1
# Then rebuild the app so the asset is included.

$ErrorActionPreference = 'Stop'

$zip = "assets/web/web_app.zip"

# Must happen BEFORE `flutter build web`: pubspec.yaml declares assets/web/
# as an asset folder, so a stale zip left here gets bundled into the new
# web build as one of its own assets — nesting last run's zip inside this
# run's zip. Left unfixed, every run adds another full copy on top of all
# the previous ones (35MB -> 70MB -> 105MB -> ... -> the 175MB this was
# found at), inflating both web_app.zip itself and the Android APK it's
# embedded into.
if (Test-Path $zip) { Remove-Item $zip }

flutter build web
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null

Compress-Archive -Path build/web/* -DestinationPath $zip
Write-Host "Created $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
Write-Host "Rebuild the app (flutter run / flutter build) to embed it."
