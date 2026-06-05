import 'package:flutter/material.dart';

import 'src/home_shell.dart';
import 'src/theme.dart';

void main() {
  runApp(const KounApp());
}

class KounApp extends StatelessWidget {
  const KounApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'koun',
      theme: KounTheme.dark,
      darkTheme: KounTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
