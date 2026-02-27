// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Enums ────────────────────────────────────────────────────────────────

enum TextSizeOption {
  small('Small', 0.85),
  normal('Default', 1.0),
  large('Large', 1.15),
  extraLarge('Extra Large', 1.3);

  const TextSizeOption(this.label, this.scaleFactor);
  final String label;
  final double scaleFactor;
}

enum MotionLevel {
  full('Full', 1.0),
  reduced('Reduced', 0.3),
  none('None', 0.0);

  const MotionLevel(this.label, this.durationMultiplier);
  final String label;
  final double durationMultiplier;
}

enum ViewDensity {
  focus('Focus', 'One thing at a time — no badges, no counters'),
  comfortable('Comfortable', 'Generous spacing, large cards'),
  compact('Compact', 'Tighter layout, more content visible');

  const ViewDensity(this.label, this.description);
  final String label;
  final String description;
}

// ── State ────────────────────────────────────────────────────────────────

class AccessibilityState {
  final TextSizeOption textSize;
  final MotionLevel motion;
  final bool highContrast;
  final ViewDensity viewDensity;
  final bool hapticsEnabled; // null in prefs → defer to system
  final bool? hapticsOverride; // explicit user choice, or null (use system)
  final bool typingIndicators;
  final ThemeMode themeMode;

  const AccessibilityState({
    this.textSize = TextSizeOption.normal,
    this.motion = MotionLevel.full,
    this.highContrast = false,
    this.viewDensity = ViewDensity.comfortable,
    this.hapticsEnabled = true,
    this.hapticsOverride,
    this.typingIndicators = false,
    this.themeMode = ThemeMode.system,
  });

  /// Whether haptics should actually fire.
  /// Precedence: explicit in-app override > system setting > default true.
  bool shouldUseHaptics(bool systemReduceMotion) {
    if (hapticsOverride != null) return hapticsOverride!;
    if (systemReduceMotion) return false;
    return true;
  }

  AccessibilityState copyWith({
    TextSizeOption? textSize,
    MotionLevel? motion,
    bool? highContrast,
    ViewDensity? viewDensity,
    bool? hapticsEnabled,
    bool? Function()? hapticsOverride,
    bool? typingIndicators,
    ThemeMode? themeMode,
  }) {
    return AccessibilityState(
      textSize: textSize ?? this.textSize,
      motion: motion ?? this.motion,
      highContrast: highContrast ?? this.highContrast,
      viewDensity: viewDensity ?? this.viewDensity,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      hapticsOverride: hapticsOverride != null ? hapticsOverride() : this.hapticsOverride,
      typingIndicators: typingIndicators ?? this.typingIndicators,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

// ── SharedPreferences keys ───────────────────────────────────────────────

class _Keys {
  static const textSize = 'a11y_text_size';
  static const motion = 'a11y_motion';
  static const highContrast = 'a11y_high_contrast';
  static const viewDensity = 'a11y_view_density';
  static const hapticsOverride = 'a11y_haptics_override';
  static const typingIndicators = 'a11y_typing_indicators';
  static const themeMode = 'a11y_theme_mode';
}

// ── Notifier ─────────────────────────────────────────────────────────────

class AccessibilityNotifier extends Notifier<AccessibilityState> {
  @override
  AccessibilityState build() {
    _load();
    return const AccessibilityState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final textSizeName = prefs.getString(_Keys.textSize);
    final motionName = prefs.getString(_Keys.motion);
    final densityName = prefs.getString(_Keys.viewDensity);
    final hapticsRaw = prefs.getBool(_Keys.hapticsOverride);
    final themeModeName = prefs.getString(_Keys.themeMode);

    state = AccessibilityState(
      textSize: TextSizeOption.values.firstWhere(
        (e) => e.name == textSizeName,
        orElse: () => TextSizeOption.normal,
      ),
      motion: MotionLevel.values.firstWhere(
        (e) => e.name == motionName,
        orElse: () => MotionLevel.full,
      ),
      highContrast: prefs.getBool(_Keys.highContrast) ?? false,
      viewDensity: ViewDensity.values.firstWhere(
        (e) => e.name == densityName,
        orElse: () => ViewDensity.comfortable,
      ),
      hapticsOverride: hapticsRaw,
      typingIndicators: prefs.getBool(_Keys.typingIndicators) ?? false,
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == themeModeName,
        orElse: () => ThemeMode.system,
      ),
    );
  }

  Future<void> setTextSize(TextSizeOption value) async {
    state = state.copyWith(textSize: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.textSize, value.name);
  }

  Future<void> setMotion(MotionLevel value) async {
    state = state.copyWith(motion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.motion, value.name);
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Keys.highContrast, value);
  }

  Future<void> setViewDensity(ViewDensity value) async {
    state = state.copyWith(viewDensity: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.viewDensity, value.name);
  }

  Future<void> setHapticsOverride(bool? value) async {
    state = state.copyWith(hapticsOverride: () => value);
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_Keys.hapticsOverride);
    } else {
      await prefs.setBool(_Keys.hapticsOverride, value);
    }
  }

  Future<void> setTypingIndicators(bool value) async {
    state = state.copyWith(typingIndicators: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Keys.typingIndicators, value);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.themeMode, value.name);
  }
}

// ── Provider ─────────────────────────────────────────────────────────────

final accessibilityProvider =
    NotifierProvider<AccessibilityNotifier, AccessibilityState>(
  AccessibilityNotifier.new,
);
