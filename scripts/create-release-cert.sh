#!/usr/bin/env bash
#
# Create the long-lived, self-signed "Segue Release" code-signing certificate
# used for public builds, and export a password-protected .p12 as a backup.
# Adapted from clipy-secure/scripts/create-release-cert.sh.
#
# Why self-signed: there is no Apple Developer ID, by choice. The release zip
# is signed with this one identity forever, so Homebrew keeps the app's
# un-quarantined state across `brew upgrade` and the README can publish one
# certificate leaf hash for verifying downloads. Rotating it costs every user
# one Gatekeeper re-approval, so create it once and never lose the .p12.
#
# ⚠️  RUNNING THIS IS A PASSWORD-PROMPT STEP. `security import` and
#     `security add-trusted-cert` prompt for your Mac login password and
#     change the login keychain. Run it yourself, at the keyboard — never
#     from an unattended agent.
#
# What it produces:
#   - an identity "Segue Release" in your login keychain (valid 20 years)
#   - <output>.p12   password-protected backup (store in your password manager)
#   - prints the certificate leaf SHA-1 to record in the README
#
# Usage:
#   scripts/create-release-cert.sh [--out PATH] [--p12-password PASS] [--no-backup]
set -euo pipefail

IDENTITY="Segue Release"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OUT="Segue-Release"
P12_PASSWORD=""
NO_BACKUP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --p12-password) P12_PASSWORD="$2"; shift 2 ;;
        --no-backup) NO_BACKUP=1; shift ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists in the keychain."
    echo "If you need to re-export it, do so from Keychain Access — do NOT create a second one."
    exit 0
fi

if [[ "$NO_BACKUP" == "0" && -z "$P12_PASSWORD" ]]; then
    read -r -s -p "Choose a password to protect the exported .p12: " P12_PASSWORD
    echo
    [[ -n "$P12_PASSWORD" ]] || { echo "error: a .p12 password is required." >&2; exit 2; }
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CNF

echo "==> Generating self-signed certificate (valid 20 years)"
openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

# The Security framework only accepts PKCS#12 built with legacy SHA1/3DES.
echo "==> Packaging as PKCS#12 for the keychain"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/cert.p12" -name "$IDENTITY" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout pass:temp 2>/dev/null

echo "==> Importing into the login keychain (may prompt for your password)"
security import "$WORKDIR/cert.p12" -k "$KEYCHAIN" -P temp -A >/dev/null

echo "==> Trusting it for code signing (may prompt for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

if [[ "$NO_BACKUP" == "0" ]]; then
    echo "==> Exporting password-protected backup .p12 to $OUT.p12"
    openssl pkcs12 -export \
        -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
        -out "$OUT.p12" -name "$IDENTITY" \
        -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
        -passout pass:"$P12_PASSWORD" 2>/dev/null
fi

LEAF_SHA="$(openssl x509 -in "$WORKDIR/cert.pem" -noout -fingerprint -sha1 \
    | sed 's/.*=//; s/://g' | tr '[:upper:]' '[:lower:]')"

echo
echo "Done."
echo "  Identity:           $IDENTITY (in your login keychain)"
if [[ "$NO_BACKUP" == "0" ]]; then
    echo "  Backup (keep safe): $OUT.p12  (store in your password manager, then delete it from disk)"
else
    echo "  Backup:             none written. Export one from Keychain Access when ready."
fi
echo "  Cert leaf (SHA-1):  $LEAF_SHA  (put it in README.md under 'Verifying a download')"
