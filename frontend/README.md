# RoTransit Flutter App

Flutter client for Android/iOS:
- Auth: Guest, Google, Apple (Firebase Auth)
- Tabs: Search, Map, Saved, Settings
- Flow: Search -> Map bottom sheet list/details -> Save journey
- Local-first storage: SQLite + sync queue to backend

## Backend base URL

| Target | `API_BASE_URL` |
|--------|----------------|
| Android emulator (local) | `http://10.0.2.2:8085` (default) |
| Physical phone (home server) | `https://api.horiasavin.me` |

```bash
# Physical device against the Cloudflare tunnel
flutter run --dart-define=API_BASE_URL=https://api.horiasavin.me
```

## First run

1. Install Flutter SDK (Dart-only is not enough).
2. From this `frontend` folder:
   - `flutter create . --platforms=android,ios`
   - `flutter pub get`
3. Configure Firebase for Android + iOS and add generated config files.
4. Run tests: `flutter test`
