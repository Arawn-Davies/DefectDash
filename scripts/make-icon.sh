#!/usr/bin/env bash
# Rasterise assets/icon.svg into Sources/DefectDash/Resources/AppIcon.icns and assets/*.png
# using only stock macOS tools (AppKit via a Swift script, sips, iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swift scripts/render-svg.swift assets/icon.svg 1024 1024 "$tmp/icon-1024.png"
swift scripts/render-svg.swift assets/logo.svg 1500 320 assets/logo.png
cp "$tmp/icon-1024.png" assets/icon.png

set="$tmp/AppIcon.iconset"
mkdir -p "$set"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$tmp/icon-1024.png" --out "$set/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$tmp/icon-1024.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Sources/DefectDash/Resources
iconutil -c icns "$set" -o Sources/DefectDash/Resources/AppIcon.icns
echo "wrote Sources/DefectDash/Resources/AppIcon.icns, assets/icon.png, assets/logo.png"
