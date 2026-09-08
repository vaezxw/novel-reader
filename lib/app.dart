import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

class InkShelfApp extends StatelessWidget {
  const InkShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨架',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeShell(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.35,
                ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class InkShelfRoot extends StatelessWidget {
  const InkShelfRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: InkShelfApp());
  }
}
