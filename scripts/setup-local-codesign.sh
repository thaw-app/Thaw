#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity in the login keychain so
# Debug rebuilds keep the same designated requirement. Ad-hoc ("-") signing
# changes the CDHash on every build, which forces macOS to re-prompt for
# Accessibility / Screen Recording. A fixed local cert avoids that.
set -euo pipefail

NAME="Thaw Local Codesign"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${ROOT}/.local-codesign"
mkdir -p "${STATE_DIR}"

if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"${NAME}\"" >/dev/null; then
  echo "Codesigning identity already installed: ${NAME}"
  security find-identity -v -p codesigning | grep -F "${NAME}" || true
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/thaw-codesign.XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

cat > "${TMP}/cert.conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_codesign

[dn]
CN = ${NAME}
O = Thaw Local Development
OU = Debug

[v3_codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 \
  -keyout "${TMP}/key.pem" \
  -out "${TMP}/cert.pem" \
  -days 3650 \
  -nodes \
  -config "${TMP}/cert.conf"

# Keep a copy for re-import / trust repair; not a secret beyond the keychain.
cp "${TMP}/cert.pem" "${STATE_DIR}/thaw-local-codesign.cer.pem"

openssl pkcs12 -export \
  -out "${TMP}/cert.p12" \
  -inkey "${TMP}/key.pem" \
  -in "${TMP}/cert.pem" \
  -passout pass:thaw-local

security unlock-keychain -p "" "${KEYCHAIN}" 2>/dev/null || true

security import "${TMP}/cert.p12" \
  -k "${KEYCHAIN}" \
  -P thaw-local \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productsign

# Allow codesign to use the private key without a GUI prompt in this session.
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "${KEYCHAIN}" 2>/dev/null || true

# Prefer user-keychain trust; fall back to system (may prompt for password).
if ! security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "${KEYCHAIN}" \
  "${TMP}/cert.pem" 2>/dev/null
then
  echo "User-keychain trust failed; trying System keychain (may ask for your password)…"
  sudo security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "${TMP}/cert.pem"
fi

echo
echo "Installed codesigning identity:"
security find-identity -v -p codesigning | grep -F "${NAME}" || {
  echo "error: identity not visible to codesign after import" >&2
  exit 1
}

echo
echo "Done. Use scripts/run-debug.sh to build and launch with this identity."
echo "First launch after switching from ad-hoc may still ask for permissions once;"
echo "later rebuilds with this same identity should keep them."
