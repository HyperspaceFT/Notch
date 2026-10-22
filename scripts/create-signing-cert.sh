#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in the login keychain. When it
# is there, scripts/build-app.sh signs with it instead of ad hoc: the signature
# then stays the same across builds, so macOS keeps the Accessibility access
# Notch was granted instead of treating every build as a new app.
#
# Usage: scripts/create-signing-cert.sh
# Env:   SIGN_IDENTITY overrides the certificate name (default: Notch Local Signing);
#        use the same value for the build.
set -euo pipefail

NAME="${SIGN_IDENTITY:-Notch Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate \"$NAME\" is already in the login keychain."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "==> Creating \"$NAME\" (self-signed, valid for 10 years)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.conf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# `security import` needs a password-protected PKCS#12; this one only lives in $TMP.
PASSWORD="$(uuidgen)"
/usr/bin/openssl pkcs12 -export -name "$NAME" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout "pass:$PASSWORD" -out "$TMP/cert.p12"

echo "==> Importing into the login keychain"
# -T lets codesign use the private key without asking each time.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

echo "Done. Builds are now signed with \"$NAME\"."
