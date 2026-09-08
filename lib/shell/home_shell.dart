import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/settings/settings_page.dart';
import '../features/shelf/shelf_page.dart';
import '../features/sources/sources_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    ShelfPage(),
    SourcesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.books),
            selectedIcon: Icon(PhosphorIconsFill.books),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.planet),
            selectedIcon: Icon(PhosphorIconsFill.planet),
            label: '书源',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.slidersHorizontal),
            selectedIcon: Icon(PhosphorIconsFill.slidersHorizontal),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
