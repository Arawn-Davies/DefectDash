#!/usr/bin/env bash
# Sign a bundle or binary with the self-signed identity (default "DefectDash Dev", override with SIGN_IDENTITY),
# falling back to an ad-hoc signature with a warning. The identity only has to exist in the keychain; it does
# not have to be trusted, because the Keychain access list is matched on the certificate, not on trust.
#
# Usage: scripts/sign.sh <path>
set -euo pipefail

target=${1:?path to sign}
identity="${SIGN_IDENTITY:-DefectDash Dev}"
id="io.github.arawn-davies.defectdash"

if security find-identity -p codesigning | grep -q "\"$identity\"" \
   && codesign --force --sign "$identity" --identifier "$id" "$target" 2>/dev/null; then
  echo "signed $target with identity \"$identity\""
else
  echo "warning: identity \"$identity\" not usable (run scripts/make-dev-cert.sh); signing ad-hoc, Keychain will re-prompt after each rebuild" >&2
  codesign --force --sign - --identifier "$id" "$target"
  echo "signed $target ad-hoc"
fi
