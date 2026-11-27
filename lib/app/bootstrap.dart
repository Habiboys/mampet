import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/app_providers.dart';
import 'app_update_gate.dart';
import 'router.dart';
import 'theme.dart';

class MamPetApp extends ConsumerStatefulWidget {
  final bool onboardingDone;
  final bool showSplash;

  const MamPetApp({
    super.key,
    required this.onboardingDone,
    this.showSplash = true,
  });

  @override
  ConsumerState<MamPetApp> createState() => _MamPetAppState();
}

class _MamPetAppState extends ConsumerState<MamPetApp> {
  late final GoRouter _router;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _router = createMamPetRouter(
      onboardingDone: widget.onboardingDone,
      showSplash: widget.showSplash,
      navigatorKey: _navigatorKey,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  ThemeMode _resolveThemeMode(String? setting) {
    switch (setting) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    return MaterialApp.router(
      title: 'MamPet',
      debugShowCheckedModeBanner: false,
      theme: MamPetTheme.light(),
      darkTheme: MamPetTheme.dark(),
      themeMode: _resolveThemeMode(settings?.themeMode),
      routerConfig: _router,
      builder: (context, child) => AppUpdateGate(
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
