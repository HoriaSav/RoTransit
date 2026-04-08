import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/theme_mode_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/main_shell.dart';

class RoTransitApp extends ConsumerWidget {
  const RoTransitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'BrasovTravel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        final style = Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark.copyWith(
                systemNavigationBarColor: const Color(0xFFF2F2F2),
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
