# RoTransit app

The Flutter app for Android and iOS. For what RoTransit is and why, see the [project README](../README.md). The full technical spec is in [docs/TECHNICAL_SPEC.md](../docs/TECHNICAL_SPEC.md).

## Features

- **Map:** opens at street level around your location. Stop pins show from zoom 15 up, and stations can be searched by name.
- **Stop board:** scheduled departures for a stop (schedule times, not live GPS), with favourite and open-line actions.
- **Timetable:** lines grouped as Urban, Rural and TE (optional). Pick a line and a stop to see its week timetable. When the bundled data has ended, a notice replaces the departures.
- **Favourites:** starred stops and lines.
- **Settings** (gear on the map): city, language (English, Romanian, German), dark mode, TE lines, fares, and the date of the timetable data.

There is no account, no routing and no trip planning.

## Where the data comes from

- **Brașov timetables** come from the bundled pack in `assets/data/`, which is extracted to a local SQLite file on first launch. Boards and timetables work offline.
- **The backend** is only used for the city list in Settings. Station search runs on the local pack. The base URL is set with `API_BASE_URL` (default `https://api.horiasavin.me`, the first-version backend). The app doesn't use `backend_v2` yet.
- **Favourites and settings** are stored in SharedPreferences.

| Target | `API_BASE_URL` |
|--------|----------------|
| Physical phone | `https://api.horiasavin.me` (default) |
| Android emulator with a local backend | `http://10.0.2.2:8085` |

## Structure

```
lib/
  main.dart
  l10n/            ARB files and generated localizations (en, ro, de)
  src/core/        config, network, location, map tiles, theme, shared state and UI
  src/features/
    map/           map, stop pins, station search, stop board, companion pack loading
    saved/         Timetable and Favourites tabs
    favorites/     favourite stops and lines storage
    routes/        API client models
    settings/      Settings screen
    shell/         tabs, header and back navigation
  src/local/       local database
test/              unit and widget tests
```

## Run

Needs Flutter 3.27 (the `path` override in `pubspec.yaml` depends on it; CI uses 3.27.4).

```bash
flutter pub get
flutter run
# emulator against a local backend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8085
```

From Android Studio: run `./scripts/setup-android-studio.sh` once from the repo root, open this `frontend` folder (not `android/` or the repo root), set Gradle JDK 21, pick a device and run `main.dart`.

## Test

```bash
flutter analyze
TZ=Europe/Bucharest flutter test
```

The stop board tests check day arithmetic across Brașov's DST changes, which is why CI runs them in `Europe/Bucharest`.

## Signed Android release

`applicationId` is `com.rotransit.app`. Play uploads need a real upload keystore, not the debug key.

1. From the repo root: `./scripts/setup-android-signing.sh`
2. Back up the gitignored `android/app/upload-keystore.jks` and `android/key.properties`. Losing them blocks app updates.
3. Build with `flutter build apk --release` or `flutter build appbundle --release`.

Without those files a release build fails on purpose, so a debug-signed build never ships. For a local test build only, add `allowDebugRelease=true` to `~/.gradle/gradle.properties` (or pass `--android-project-arg allowDebugRelease=true`). Never commit the keystore or `key.properties`.

## Brașov companion pack

`assets/data/brasov_companion.sqlite.gz` is extracted on first launch, and again whenever `pack_version` in `assets/data/brasov_companion.manifest.json` changes. To rebuild it from the repo root (needs `otp/gtfs/ro-ratbv.zip`):

```bash
python3 scripts/data/build_brasov_companion_pack.py
```

The script writes the `.gz` and the manifest directly. Commit both.
