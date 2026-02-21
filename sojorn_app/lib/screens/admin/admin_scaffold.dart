// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminScaffold extends StatelessWidget {
  final Widget child;
  final int selectedIndex;

  const AdminScaffold({
    super.key,
    required this.child,
    required this.selectedIndex,
  });

  static const _routes = [
    '/admin',
    '/admin/moderation',
    '/admin/users',
    '/admin/content-tools',
  ];

  static ThemeData _adminTheme() {
    const bg = Color(0xFF0B0F1A);
    const surface = Color(0xFF121826);
    const panel = Color(0xFF0F1626);
    const accent = Color(0xFF58A6FF);
    const muted = Color(0xFF9AA4BF);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: Color(0xFF7C3AED),
        surface: surface,
        onSurface: const Color(0xFFFFFFFF),
        error: Color(0xFFE11D48),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        elevation: 0,
        surfaceTintColor: const Color(0x00000000),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF1F2937)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1F2937),
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFFFFFFF),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFFCBD5F5),
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: muted,
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: panel,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(color: accent),
        unselectedIconTheme: IconThemeData(color: muted),
        unselectedLabelTextStyle: TextStyle(color: muted),
        indicatorColor: Color(0xFF1E293B),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
        dataTextStyle: const TextStyle(
          color: Color(0xFFCBD5F5),
        ),
        headingRowColor: WidgetStateProperty.all(panel),
        dividerThickness: 1,
      ),
    );
  }

  void _onDestinationSelected(BuildContext context, int index) {
    if (index < 0 || index >= _routes.length) return;
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _adminTheme(),
      child: Builder(
        builder: (context) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final bool extendedRail = constraints.maxWidth >= 1100;

              return Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (index) =>
                            _onDestinationSelected(context, index),
                        extended: extendedRail,
                        minWidth: 72,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.insights),
                            label: Text('Dashboard'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.policy),
                            label: Text('Moderation Queue'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.people_alt_outlined),
                            label: Text('User Base'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.build_circle_outlined),
                            label: Text('Content Tools'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
