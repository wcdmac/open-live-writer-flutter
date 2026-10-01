import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Without these, an uncaught framework or async error paints the grey
  // error screen and leaves no diagnostics anywhere.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('OLW framework error: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('OLW uncaught async error: $error\n$stack');
    // Report as handled so one bad future does not tear the app down.
    return true;
  };

  runApp(const OpenLiveWriterApp());
}

class OpenLiveWriterApp extends StatelessWidget {
  const OpenLiveWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: const AppShell(),
    );
  }
}
