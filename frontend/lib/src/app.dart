import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import 'core/state/locale_provider.dart';
import 'core/state/theme_mode_provider.dart';
import 'core/theme/app_extra_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/main_shell.dart';

class RoTransitApp extends ConsumerWidget {
  const RoTransitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: 'RoTransit',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedAppLocales,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        final extra = Theme.of(context).extension<AppExtraColors>() ??
            AppExtraColors.light;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final style = isDark
            ? SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor: extra.shellFrame,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                systemNavigationBarColor: extra.shellFrame,
                systemNavigationBarIconBrightness: Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: style,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainShell(),
    );
  }
}
