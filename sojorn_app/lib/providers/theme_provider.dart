// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeMode {
  basic,
  pop,
}

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.basic;
  }

  static const String _themeKey = 'app_theme';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_themeKey);
    if (themeName != null) {
      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => ThemeMode.basic,
      );
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  () => ThemeNotifier(),
);
