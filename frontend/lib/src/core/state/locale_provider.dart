import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BCP-47 language codes supported by the app.
const supportedAppLanguageCodes = ['en', 'ro', 'de'];

const supportedAppLocales = [
  Locale('en'),
  Locale('ro'),
  Locale('de'),
];

final localeProvider = StateNotifierProvider<LocaleController, Locale>(
  (ref) => LocaleController()..load(),
);

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('en'));

  static const _key = 'app_locale_code';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null && supportedAppLanguageCodes.contains(code)) {
      state = Locale(code);
    }
  }

  Future<void> setLanguageCode(String languageCode) async {
    if (!supportedAppLanguageCodes.contains(languageCode)) return;
    state = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, languageCode);
  }
}

String languageLabelForCode(AppLocalizations l10n, String code) {
  return switch (code) {
    'ro' => l10n.languageRomanian,
    'de' => l10n.languageGerman,
    _ => l10n.languageEnglish,
  };
}
