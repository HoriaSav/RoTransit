import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:rotransit/src/core/theme/app_theme.dart';
import 'package:rotransit/src/features/map/data/companion_catalog.dart';
import 'package:rotransit/src/features/settings/presentation/settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pack_manifest.dart';
import 'support/pack_test_env.dart';

void main() {
  usePackTestEnv(prefix: 'rotransit_settings_');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'RoTransit',
      packageName: 'ro.rotransit',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('Settings shows the bundled pack data_as_of and no download row',
      (tester) async {
    // Extract the real bundled pack (real I/O outside fake async).
    await tester.runAsync(() => CompanionCatalog.instance.meta());

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsTab(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.text('Brașov data as of'), findsOneWidget);
    expect(find.text(bundledDataAsOf()), findsOneWidget);
    expect(bundledDataAsOf(), '2026-02-23');
    expect(find.text('—'), findsNothing, reason: 'meta must have loaded');

    final everything = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n')
        .toLowerCase();
    expect(everything, isNot(contains('download')));
    expect(everything, isNot(contains('offline pack')));
  });
}
