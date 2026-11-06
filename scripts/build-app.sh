#!/usr/bin/env bash
# Build DefectDash in release mode and assemble + sign build/DefectDash.app.
# SIGN_IDENTITY selects the code-signing identity (default "DefectDash Dev");
# if it is not in the keychain the bundle is signed ad-hoc with a warning.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product DefectDash
bin_dir="$(swift build -c release --product DefectDash --show-bin-path)"

app="build/DefectDash.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DefectDash" "$app/Contents/MacOS/DefectDash"
cp "Sources/DefectDash/Resources/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

IDENTITY="${SIGN_IDENTITY:-DefectDash Dev}"
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier io.github.arawn-davies.defectdash "$app"
  echo "signed $app with identity \"$IDENTITY\""
else
  echo "warning: identity \"$IDENTITY\" not found, signing ad-hoc (Keychain access will re-prompt after each rebuild)" >&2
  codesign --force --sign - --identifier io.github.arawn-davies.defectdash "$app"
  echo "signed $app ad-hoc"
fi
