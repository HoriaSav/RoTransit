import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../shell/main_shell.dart';
import '../state/session_provider.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session != null) {
      return const MainShell();
    }
    final textTheme = Theme.of(context).textTheme;

    const legalBaseStyle = TextStyle(
      fontSize: 11,
      height: 1.35,
      color: AppTheme.authLegalText,
      fontWeight: FontWeight.w500,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.authScreenBackground,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FAF6), Color(0xFFF4F6EF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height -
                          MediaQuery.paddingOf(context).vertical -
                          88,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: AppTheme.authLogoRadius,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x220A4FB8),
                                    blurRadius: 20,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: AppTheme.authLogoRadius,
                                child: Image.asset(
                                  'assets/app_icon.png',
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'RoTransit',
                              style: textTheme.headlineMedium?.copyWith(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Navigate your city with mathematical\nprecision.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 18,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: AppTheme.authCardBackground,
                            borderRadius: AppTheme.authCardRadius,
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                          child: Column(
                            children: [
                              _AuthPillButton(
                                icon: const Icon(
                                    Icons.g_mobiledata_rounded, size: 28),
                                label: 'Sign in with Google',
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF131722),
                                borderColor: const Color(0xFFE7EAF0),
                                onPressed: () => ref
                                    .read(sessionProvider.notifier)
                                    .signInGoogle(),
                              ),
                              const SizedBox(height: 18),
                              _AuthPillButton(
                                icon: const Icon(Icons.apple, size: 24),
                                label: 'Sign in with Apple ID',
                                backgroundColor: AppTheme.authDarkButton,
                                foregroundColor: Colors.white,
                                onPressed: () => ref
                                    .read(sessionProvider.notifier)
                                    .signInApple(),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 22),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18),
                                      child: Text(
                                        'OR',
                                        style: textTheme.labelLarge?.copyWith(
                                          fontSize: 12,
                                          color: const Color(0xFF9096A1),
                                          letterSpacing: 2.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _AuthPillButton(
                                icon: const Icon(
                                    Icons.arrow_forward_rounded, size: 24),
                                label: 'Continue as Guest',
                                iconAtEnd: true,
                                backgroundColor: AppTheme.authPrimaryBlue,
                                foregroundColor: Colors.white,
                                onPressed: () => ref
                                    .read(sessionProvider.notifier)
                                    .continueAsGuest(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  32,
                  4,
                  32,
                  10 + MediaQuery.paddingOf(context).bottom,
                ),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: legalBaseStyle,
                    children: [
                      TextSpan(text: 'By continuing, you agree to our '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(
                          color: AppTheme.authPrimaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy.',
                        style: TextStyle(
                          color: AppTheme.authPrimaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthPillButton extends StatefulWidget {
  const _AuthPillButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
    this.iconAtEnd = false,
  });

  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final Color? borderColor;
  final bool iconAtEnd;

  @override
  State<_AuthPillButton> createState() => _AuthPillButtonState();
}

class _AuthPillButtonState extends State<_AuthPillButton> {
  static const _animDuration = Duration(milliseconds: 160);
  static const Curve _animCurve = Curves.easeOutCubic;

  bool _pressed = false;

  List<BoxShadow> _depthShadows() {
    if (_pressed) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          offset: const Offset(0, 2),
          blurRadius: 8,
          spreadRadius: -1,
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.07),
        offset: const Offset(0, 2),
        blurRadius: 6,
        spreadRadius: -1,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.18),
        offset: const Offset(0, 8),
        blurRadius: 22,
        spreadRadius: -4,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.label,
      style: TextStyle(
        fontSize: 20,
        height: 1.1,
        fontWeight: FontWeight.w800,
        color: widget.foregroundColor,
      ),
    );
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedSlide(
        duration: _animDuration,
        curve: _animCurve,
        offset: _pressed ? const Offset(0, 0.04) : Offset.zero,
        child: AnimatedScale(
          duration: _animDuration,
          curve: _animCurve,
          scale: _pressed ? 0.985 : 1.0,
          child: AnimatedContainer(
            duration: _animDuration,
            curve: _animCurve,
            decoration: BoxDecoration(
              borderRadius: AppTheme.authPillRadius,
              boxShadow: _depthShadows(),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 68,
              child: ElevatedButton(
                onPressed: widget.onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.backgroundColor,
                  foregroundColor: widget.foregroundColor,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.authPillRadius,
                    side: BorderSide(
                      color: widget.borderColor ?? Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: widget.iconAtEnd
                      ? [text, const SizedBox(width: 10), widget.icon]
                      : [widget.icon, const SizedBox(width: 10), text],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
