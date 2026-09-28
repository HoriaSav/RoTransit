# RoTransit Flutter App

Product overview: repo root [README](../README.md). Full technical spec: [docs/TECHNICAL_SPEC.md](../docs/TECHNICAL_SPEC.md).

Flutter client for Android/iOS:
- Tabs: Map, Timetable, Favorites. Settings opens from the gear on the map.
- Flow: tap a stop on the map (or search by name) -> stop board with scheduled departures -> open a line timetable.
- No routing / trip planning. Brașov data comes from the bundled pack, not the API.
- Local storage: SharedPreferences (favorites, settings) and the extracted pack SQLite file.

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

Without those files a release build fails on purpose, so a debug-signed build never ships. For a local test build only, add `allowDebugRelease=true` to `~/.gradle/gradle.properties` (or pass `--android-project-arg allowDebugRelease=true` to `flutter build`). Do not commit the keystore or `key.properties`.


## Brașov companion pack

`assets/data/brasov_companion.sqlite.gz` is extracted on first launch, and again whenever `pack_version` in `assets/data/brasov_companion.manifest.json` changes. Rebuild from the repo root (needs `otp/gtfs/ro-ratbv.zip`):

```bash
python3 scripts/data/build_brasov_companion_pack.py
```

The script writes the `.gz` and the manifest directly (no separate gzip step). Commit both.
