#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND="$ROOT/frontend"
FLUTTER_SDK="${FLUTTER_SDK:-$HOME/.local/flutter}"
ANDROID_SDK="${ANDROID_SDK:-$HOME/Android/Sdk}"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}"

echo "==> RoTransit Android Studio setup"
echo "    Project:  $FRONTEND"
echo "    Flutter:  $FLUTTER_SDK"
echo "    Android:  $ANDROID_SDK"
echo "    Java:     $JAVA_HOME"

if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
  echo "ERROR: Flutter not found at $FLUTTER_SDK"
  echo "Install Flutter or set FLUTTER_SDK to your SDK path."
  exit 1
fi

if [[ ! -d "$ANDROID_SDK" ]]; then
  echo "ERROR: Android SDK not found at $ANDROID_SDK"
  echo "Install Android Studio or set ANDROID_SDK."
  exit 1
fi

mkdir -p "$FRONTEND/android"
cat > "$FRONTEND/android/local.properties" <<EOF
sdk.dir=$ANDROID_SDK
flutter.sdk=$FLUTTER_SDK
EOF

# Machine-specific JDK path goes in the user-level Gradle properties, not the repo.
GRADLE_PROPS="${GRADLE_USER_HOME:-$HOME/.gradle}/gradle.properties"
mkdir -p "$(dirname "$GRADLE_PROPS")"
if grep -q '^org.gradle.java.home=' "$GRADLE_PROPS" 2>/dev/null; then
  sed -i "s|^org.gradle.java.home=.*|org.gradle.java.home=$JAVA_HOME|" "$GRADLE_PROPS"
else
  echo "org.gradle.java.home=$JAVA_HOME" >> "$GRADLE_PROPS"
fi

export PATH="$FLUTTER_SDK/bin:$ANDROID_SDK/platform-tools:$PATH"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export JAVA_HOME

"$FLUTTER_SDK/bin/flutter" config --jdk-dir="$JAVA_HOME" --android-sdk="$ANDROID_SDK"
"$FLUTTER_SDK/bin/flutter" pub get --directory="$FRONTEND"

echo
echo "==> Verifying toolchain"
"$FLUTTER_SDK/bin/flutter" doctor

echo
echo "==> Connected devices"
"$FLUTTER_SDK/bin/flutter" devices

echo
cat <<INSTRUCTIONS

Setup complete.

Open in Android Studio:
  1. File → Open → $FRONTEND
     (open the frontend folder, not the android/ folder and not the repo root)
  2. Settings → Languages & Frameworks → Flutter
     Flutter SDK path: $FLUTTER_SDK
  3. Settings → Build, Execution, Deployment → Build Tools → Gradle
     Gradle JDK: java-21-openjdk (or "21")
  4. Enable USB debugging on your phone, connect via USB
  5. Select your device in the toolbar and press Run (main.dart)

The app talks to https://api.horiasavin.me by default.
For a local backend on the emulator, add:
  --dart-define=API_BASE_URL=http://10.0.2.2:8080

INSTRUCTIONS
