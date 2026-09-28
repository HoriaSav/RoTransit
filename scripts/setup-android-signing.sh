#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/frontend/android/app"
KEY_PROPS="$ROOT/frontend/android/key.properties"
STORE_FILE="$APP_DIR/upload-keystore.jks"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}"
KEYTOOL="${KEYTOOL:-$JAVA_HOME/bin/keytool}"

if [[ ! -x "$KEYTOOL" ]]; then
  KEYTOOL="$(command -v keytool || true)"
fi
if [[ -z "$KEYTOOL" || ! -x "$KEYTOOL" ]]; then
  echo "ERROR: keytool not found. Install JDK 21 or set JAVA_HOME / KEYTOOL."
  exit 1
fi

mkdir -p "$APP_DIR"

if [[ -f "$STORE_FILE" && -f "$KEY_PROPS" ]]; then
  echo "Upload keystore already present (gitignored)."
  echo "    $STORE_FILE"
  echo "    $KEY_PROPS"
  echo "Back those up before a Play upload. Rebuild with:"
  echo "    cd frontend && flutter build apk --release"
  exit 0
fi

if [[ -f "$STORE_FILE" || -f "$KEY_PROPS" ]]; then
  echo "ERROR: partial signing files exist. Keep both or remove both, then re-run."
  echo "    store: $STORE_FILE"
  echo "    props: $KEY_PROPS"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl not found (needed to generate the keystore password)."
  exit 1
fi
PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
# Passed to keytool via the environment so it never shows up in `ps`.
export RT_KS_PASS="$PASSWORD"

"$KEYTOOL" -genkeypair -v \
  -keystore "$STORE_FILE" \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass:env RT_KS_PASS \
  -keypass:env RT_KS_PASS \
  -dname "CN=RoTransit, OU=RoTransit, O=RoTransit, L=Brasov, ST=Brasov, C=RO"

cat > "$KEY_PROPS" <<EOF
storePassword=$PASSWORD
keyPassword=$PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
EOF

chmod 600 "$KEY_PROPS" "$STORE_FILE"
echo "Created gitignored upload keystore and key.properties."
echo "Back them up; Play Console needs the same key for updates."
echo "    $STORE_FILE"
echo "    $KEY_PROPS"
echo "Then: cd frontend && flutter build apk --release"
