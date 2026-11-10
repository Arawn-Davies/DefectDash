#!/usr/bin/env bash
# Create a self-signed code-signing certificate "DefectDash Dev" in the login keychain and trust it for
# code signing. Builds then sign with a stable identity, so the Keychain's "Always Allow" for the Asana
# token survives rebuilds and upgrades (an ad-hoc signature changes with every build and is not
# remembered). macOS will ask for your login password once, when the trust setting is written.
#
# Usage: scripts/make-dev-cert.sh [name]   (default name: DefectDash Dev)
set -euo pipefail

name=${1:-DefectDash Dev}
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "identity \"$name\" already exists and is valid for code signing"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" \
  -subj "/CN=$name" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

# Random one-time password for the PKCS#12 bundle; it never leaves this script.
p12pass=$(/usr/bin/openssl rand -hex 16)
# Apple's importer only reads the legacy PKCS#12 encoding (3DES/SHA-1); OpenSSL 3 defaults to AES/SHA-256,
# so use the system LibreSSL explicitly and pin the legacy algorithms.
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/identity.p12" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$p12pass"

# Import the identity (skipped when a previous run already imported it but failed at the trust step).
if ! security find-identity -p codesigning | grep -q "\"$name\""; then
  security import "$work/identity.p12" -k "$keychain" -P "$p12pass" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
else
  echo "identity \"$name\" already imported; setting access and trust"
  security find-certificate -c "$name" -p > "$work/cert.pem"
fi

# Let codesign use the private key non-interactively (asks for your login keychain password on this tty).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$keychain"

# Trust it for code signing. The per-user trust store needs a GUI authorisation dialog; over SSH there is
# none, so fall back to the admin trust store via sudo (asks for your password on this tty).
if ! security add-trusted-cert -p codeSign -k "$keychain" "$work/cert.pem" 2>/dev/null; then
  echo "no GUI session for per-user trust; writing admin trust settings with sudo"
  sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$work/cert.pem"
fi

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "created and trusted identity \"$name\""
  echo "next: make app (or scripts/release.sh) signs with it automatically; re-import the token once with"
  echo "      make import-pat PAT_FILE=<path>  so the Keychain item's access list names the signed app."
else
  echo "identity was imported but is not listed as valid for code signing; check Keychain Access → My Certificates → \"$name\" → Trust → Code Signing" >&2
  exit 1
fi
