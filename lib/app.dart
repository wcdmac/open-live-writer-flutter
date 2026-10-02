import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'state/app_state.dart';
import 'views/home_page.dart';

/// Material app shell with an adaptive light/dark theme.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Only rebuilds (and recreates MaterialApp) when the persisted color
    // scheme preference changes — every other AppState notification (refresh,
    // theme probe, account switch) is intentionally ignored so the whole
    // app doesn't re-mount on a routine post-list reload.
    final themeMode = context.select<AppState, ThemeMode>((a) => a.themeMode);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E6FD9),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E6FD9),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Open Live Writer',
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}
