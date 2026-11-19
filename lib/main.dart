import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Trava em retrato: simplifica o cálculo das posições dos códigos na tela.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LeitorApp());
}

class LeitorApp extends StatelessWidget {
  const LeitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leitor de Códigos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}
