# RoTransit Flutter App

Product overview: repo root [README](../README.md). Full technical spec: [docs/TECHNICAL_SPEC.md](../docs/TECHNICAL_SPEC.md).

Flutter client for Android/iOS:
- Tabs: Search, Bus, Favorites, Settings
- Flow: Search -> Map bottom sheet list/details -> Save journey
- Local-first storage: SQLite (saved trips, recents, offline pack)

## Backend base URL

| Target | `API_BASE_URL` |
|--------|----------------|
| Physical phone | `https://api.horiasavin.me` (default) |
| Android emulator (local backend) | `http://10.0.2.2:8085` |

```bash
# Physical device (default — no extra flags needed)
flutter run

# Emulator against a local backend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8085
```

## Run from Android Studio

1. One-time from the repo root: `./scripts/setup-android-studio.sh`
2. In Android Studio: **File → Open** → this `frontend` folder (not `android/` and not the repo root).
3. Set Flutter SDK to `$HOME/.local/flutter` and Gradle JDK to **21**.
4. Connect a phone with USB debugging, pick it in the toolbar, Run `main.dart`.

## First run (CLI)

1. Install Flutter SDK (Dart-only is not enough).
2. From this `frontend` folder: `flutter pub get`
3. Run tests: `flutter test`

## Signed Android release

`applicationId` is `com.rotransit.app`. Play uploads need a real upload keystore, not the debug key.

1. From the repo root: `./scripts/setup-android-signing.sh`
2. Back up gitignored `frontend/android/app/upload-keystore.jks` and `frontend/android/key.properties`. Losing them blocks app updates.
3. From this `frontend` folder:

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

Without those files, Gradle still signs `--release` with the debug key so local runs work. Do not commit the keystore or `key.properties`.


## Brașov companion pack

`assets/data/brasov_companion.sqlite.gz` is extracted on first launch. Rebuild with:

```bash
python3 ../scripts/data/build_brasov_companion_pack.py
gzip -kf ../frontend/assets/data/brasov_companion.sqlite
# keep the .gz in assets; raw sqlite is optional
```
