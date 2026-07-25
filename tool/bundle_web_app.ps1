# Builds the Flutter web app and bundles it into assets/web/web_app.zip.
# The game server serves it over HTTP on the room port, so players can join
# from any browser by scanning the room QR code - no install needed.
#
# Run from the repo root:  .\tool\bundle_web_app.ps1
# Then rebuild the app so the asset is included.

$ErrorActionPreference = 'Stop'

flutter build web
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$zip = "assets/web/web_app.zip"
if (Test-Path $zip) { Remove-Item $zip }
New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null

Compress-Archive -Path build/web/* -DestinationPath $zip
Write-Host "Created $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
Write-Host "Rebuild the app (flutter run / flutter build) to embed it."
