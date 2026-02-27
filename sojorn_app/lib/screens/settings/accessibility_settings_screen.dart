// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/accessibility_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../home/full_screen_shell.dart';

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(accessibilityProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final body = SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(SojornSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'Display',
            subtitle: 'Text and visual preferences',
            children: [
              _AppearanceTile(a11y: a11y, ref: ref),
              _TextSizeTile(a11y: a11y, ref: ref),
              _HighContrastTile(a11y: a11y, ref: ref),
            ],
          ),
          const SizedBox(height: SojornSpacing.lg),
          _buildSection(
            title: 'Motion',
            subtitle: 'Animation and movement',
            children: [
              _MotionTile(a11y: a11y, ref: ref),
            ],
          ),
          const SizedBox(height: SojornSpacing.lg),
          _buildSection(
            title: 'Layout',
            subtitle: 'Information density',
            children: [
              _ViewDensityTile(a11y: a11y, ref: ref),
            ],
          ),
          const SizedBox(height: SojornSpacing.lg),
          _buildSection(
            title: 'Interaction',
            subtitle: 'Feedback and indicators',
            children: [
              _HapticsTile(a11y: a11y, ref: ref, context: context),
              _TypingIndicatorTile(a11y: a11y, ref: ref),
            ],
          ),
          const SizedBox(height: SojornSpacing.lg),
          _buildSection(
            title: 'Data & Storage',
            subtitle: 'Bandwidth and media loading',
            children: [
              const _DataSaverTile(),
              const _AutoPlayTile(),
            ],
          ),
          const SizedBox(height: SojornSpacing.lg * 2),
          _buildResetButton(ref),
          const SizedBox(height: SojornSpacing.lg),
        ],
      ),
    );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppTheme.scaffoldBg,
          elevation: 0,
          surfaceTintColor: SojornColors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Accessibility',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: body,
      );
    }

    return FullScreenShell(
      titleText: 'Accessibility',
      body: body,
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.textTheme.headlineSmall),
        Text(
          subtitle,
          style: AppTheme.textTheme.labelSmall
              ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: SojornSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.borderSubtle.withValues(alpha: AppTheme.isDark ? 0.5 : 0.1),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildResetButton(WidgetRef ref) {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          final notifier = ref.read(accessibilityProvider.notifier);
          notifier.setThemeMode(ThemeMode.system);
          notifier.setTextSize(TextSizeOption.normal);
          notifier.setMotion(MotionLevel.full);
          notifier.setHighContrast(false);
          notifier.setViewDensity(ViewDensity.comfortable);
          notifier.setHapticsOverride(null);
          notifier.setTypingIndicators(false);
        },
        icon: Icon(Icons.restart_alt, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
        label: Text(
          'Reset to defaults',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

// ── Appearance (Light / Dark / System) ───────────────────────────────────

class _AppearanceTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _AppearanceTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6, color: AppTheme.navyBlue, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance', style: AppTheme.textTheme.bodyLarge),
                    Text(
                      'Light, dark, or follow your device',
                      style: AppTheme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.navyText.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.settings_suggest, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode, size: 16),
              ),
            ],
            selected: {a11y.themeMode},
            onSelectionChanged: (set) =>
                ref.read(accessibilityProvider.notifier).setThemeMode(set.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return SojornColors.basicWhite;
                }
                return AppTheme.navyText;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.brightNavy;
                }
                return null;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Text Size ────────────────────────────────────────────────────────────

class _TextSizeTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _TextSizeTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.text_fields, color: AppTheme.navyBlue, size: 22),
      title: Text('Text Size', style: AppTheme.textTheme.bodyLarge),
      subtitle: Text(
        a11y.textSize.label,
        style: AppTheme.textTheme.bodySmall
            ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
      ),
      trailing: SizedBox(
        width: 180,
        child: Slider(
          value: TextSizeOption.values.indexOf(a11y.textSize).toDouble(),
          min: 0,
          max: (TextSizeOption.values.length - 1).toDouble(),
          divisions: TextSizeOption.values.length - 1,
          label: a11y.textSize.label,
          activeColor: AppTheme.brightNavy,
          onChanged: (v) {
            ref
                .read(accessibilityProvider.notifier)
                .setTextSize(TextSizeOption.values[v.round()]);
          },
        ),
      ),
    );
  }
}

// ── High Contrast ────────────────────────────────────────────────────────

class _HighContrastTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _HighContrastTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(Icons.contrast, color: AppTheme.navyBlue, size: 22),
      title: Text('High Contrast', style: AppTheme.textTheme.bodyLarge),
      subtitle: Text(
        'Stronger borders and darker text',
        style: AppTheme.textTheme.bodySmall
            ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
      ),
      value: a11y.highContrast,
      activeTrackColor: AppTheme.brightNavy,
      onChanged: (v) =>
          ref.read(accessibilityProvider.notifier).setHighContrast(v),
    );
  }
}

// ── Motion ───────────────────────────────────────────────────────────────

class _MotionTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _MotionTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.animation, color: AppTheme.navyBlue, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Motion', style: AppTheme.textTheme.bodyLarge),
                    Text(
                      'Controls animation speed throughout the app',
                      style: AppTheme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.navyText.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<MotionLevel>(
            segments: MotionLevel.values
                .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                .toList(),
            selected: {a11y.motion},
            onSelectionChanged: (set) =>
                ref.read(accessibilityProvider.notifier).setMotion(set.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return SojornColors.basicWhite;
                }
                return AppTheme.navyText;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.brightNavy;
                }
                return null;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── View Density ─────────────────────────────────────────────────────────

class _ViewDensityTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _ViewDensityTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.view_agenda_outlined, color: AppTheme.navyBlue, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Information Density', style: AppTheme.textTheme.bodyLarge),
                    Text(
                      'How much content fits on screen',
                      style: AppTheme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.navyText.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RadioGroup<ViewDensity>(
            groupValue: a11y.viewDensity,
            onChanged: (v) {
              if (v != null) {
                ref.read(accessibilityProvider.notifier).setViewDensity(v);
              }
            },
            child: Column(
              children: ViewDensity.values.map(
                (d) => RadioListTile<ViewDensity>(
                  value: d,
                  title: Text(d.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    d.description,
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Haptics ──────────────────────────────────────────────────────────────

class _HapticsTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;
  final BuildContext context;

  const _HapticsTile({
    required this.a11y,
    required this.ref,
    required this.context,
  });

  @override
  Widget build(BuildContext outerContext) {
    final systemReduceMotion =
        MediaQuery.of(context).disableAnimations;
    final effectiveHaptics = a11y.shouldUseHaptics(systemReduceMotion);

    // Determine the display state
    String subtitle;
    if (a11y.hapticsOverride != null) {
      subtitle = a11y.hapticsOverride! ? 'On (your choice)' : 'Off (your choice)';
    } else if (systemReduceMotion) {
      subtitle = 'Off (following system Reduce Motion)';
    } else {
      subtitle = 'On (following system setting)';
    }

    return Column(
      children: [
        SwitchListTile(
          secondary:
              Icon(Icons.vibration, color: AppTheme.navyBlue, size: 22),
          title: Text('Haptic Feedback', style: AppTheme.textTheme.bodyLarge),
          subtitle: Text(
            subtitle,
            style: AppTheme.textTheme.bodySmall
                ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
          ),
          value: effectiveHaptics,
          activeTrackColor: AppTheme.brightNavy,
          onChanged: (v) =>
              ref.read(accessibilityProvider.notifier).setHapticsOverride(v),
        ),
        if (a11y.hapticsOverride != null)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => ref
                    .read(accessibilityProvider.notifier)
                    .setHapticsOverride(null),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Reset to system default',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.egyptianBlue,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Typing Indicators ────────────────────────────────────────────────────

class _TypingIndicatorTile extends StatelessWidget {
  final AccessibilityState a11y;
  final WidgetRef ref;

  const _TypingIndicatorTile({required this.a11y, required this.ref});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary:
          Icon(Icons.more_horiz, color: AppTheme.navyBlue, size: 22),
      title:
          Text('Typing Indicators', style: AppTheme.textTheme.bodyLarge),
      subtitle: Text(
        'Show when others are typing in chat. Some people find these anxiety-inducing.',
        style: AppTheme.textTheme.bodySmall
            ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
      ),
      value: a11y.typingIndicators,
      activeTrackColor: AppTheme.brightNavy,
      onChanged: (v) =>
          ref.read(accessibilityProvider.notifier).setTypingIndicators(v),
    );
  }
}

// ── Data Saver ──────────────────────────────────────────────────────────

class _DataSaverTile extends ConsumerWidget {
  const _DataSaverTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final userSettings = settings.user;
    final isOn = userSettings?.dataSaverMode ?? false;

    return SwitchListTile(
      secondary: Icon(Icons.data_saver_on, color: AppTheme.navyBlue, size: 22),
      title: Text('Low Data Mode', style: AppTheme.textTheme.bodyLarge),
      subtitle: Text(
        isOn
            ? 'Images hidden, auto-refresh reduced'
            : 'Load all media normally',
        style: AppTheme.textTheme.bodySmall
            ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
      ),
      value: isOn,
      activeTrackColor: AppTheme.brightNavy,
      onChanged: userSettings == null
          ? null
          : (v) => ref
              .read(settingsProvider.notifier)
              .updateUser(userSettings.copyWith(dataSaverMode: v)),
    );
  }
}

// ── Auto-Play Videos ────────────────────────────────────────────────────

class _AutoPlayTile extends ConsumerWidget {
  const _AutoPlayTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final userSettings = settings.user;
    final isOn = userSettings?.autoPlayVideos ?? true;

    return SwitchListTile(
      secondary:
          Icon(Icons.play_circle_outline, color: AppTheme.navyBlue, size: 22),
      title: Text('Auto-Play Videos', style: AppTheme.textTheme.bodyLarge),
      subtitle: Text(
        isOn ? 'Videos play automatically in feeds' : 'Tap to play videos',
        style: AppTheme.textTheme.bodySmall
            ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)),
      ),
      value: isOn,
      activeTrackColor: AppTheme.brightNavy,
      onChanged: userSettings == null
          ? null
          : (v) => ref
              .read(settingsProvider.notifier)
              .updateUser(userSettings.copyWith(autoPlayVideos: v)),
    );
  }
}
