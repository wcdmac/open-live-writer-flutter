import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
