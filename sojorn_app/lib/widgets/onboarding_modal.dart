// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 3-screen swipeable onboarding modal shown on first app launch.
/// Stores completion in SharedPreferences so it only shows once.
class OnboardingModal extends StatefulWidget {
  const OnboardingModal({super.key});

  static const _prefKey = 'onboarding_completed';

  /// Shows the onboarding modal if the user hasn't completed it yet.
  /// Call this from HomeShell.initState via addPostFrameCallback.
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return;
    if (!context.mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) => const OnboardingModal(),
    );
  }

  /// Resets the onboarding flag so it shows again (for Settings → "Show Tutorial Again").
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  @override
  State<OnboardingModal> createState() => _OnboardingModalState();
}

class _OnboardingModalState extends State<OnboardingModal> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    AnalyticsService.instance.event('onboarding_completed');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingModal._prefKey, true);
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    if (_currentPage < 2) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) {
                      AnalyticsService.instance.event('onboarding_step', value: '${i + 1}');
                      setState(() => _currentPage = i);
                    },
                    children: const [
                      _WelcomePage(),
                      _FeaturesPage(),
                      _HarmonyPage(),
                    ],
                  ),
                ),
                // Page indicator + button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) => Container(
                          width: _currentPage == i ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _currentPage == i
                                ? AppTheme.navyBlue
                                : AppTheme.navyBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                      ),
                      const SizedBox(height: 20),
                      // CTA button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.navyBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: Text(
                            _currentPage == 2 ? 'Get Started' : 'Next',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (_currentPage < 2) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _complete,
                          child: Text('Skip', style: TextStyle(
                            color: AppTheme.navyBlue.withValues(alpha: 0.5),
                            fontSize: 13,
                          )),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Screen 1: Welcome ─────────────────────────────────────────────────────
class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 8),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.navyBlue, AppTheme.brightNavy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 28),
          Text('Welcome to Sojorn!', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.navyBlue,
          ), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Text(
            'Let\'s learn about all the features available to you.',
            style: TextStyle(
              fontSize: 14, color: AppTheme.postContentLight, height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          Icon(Icons.lock_outline, size: 28, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Screen 2: Four Ways to Connect ────────────────────────────────────────
class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 8),
      child: Column(
        children: [
          Text('Four Ways to Connect', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.navyBlue,
          )),
          const SizedBox(height: 24),
          _FeatureRow(
            icon: Icons.article_outlined,
            color: const Color(0xFF2196F3),
            title: 'Posts',
            subtitle: 'Share thoughts with your circle',
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.play_circle_outline,
            color: const Color(0xFF9C27B0),
            title: 'Quips',
            subtitle: 'Short videos, your stories',
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.forum_outlined,
            color: const Color(0xFFFF9800),
            title: 'Chains',
            subtitle: 'Deep conversations, threaded replies',
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.sensors,
            color: const Color(0xFF4CAF50),
            title: 'Beacons',
            subtitle: 'Local alerts and real-time updates',
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(
                fontSize: 12, color: AppTheme.textDisabled,
              )),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Screen 3: Build Your Harmony ──────────────────────────────────────────
class _HarmonyPage extends StatelessWidget {
  const _HarmonyPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 8),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_graph, color: Color(0xFF4CAF50), size: 36),
          ),
          const SizedBox(height: 24),
          Text('Build Your Harmony', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.navyBlue,
          )),
          const SizedBox(height: 14),
          Text(
            'Your Harmony State grows as you contribute positively. Higher harmony means greater reach.',
            style: TextStyle(
              fontSize: 14, color: AppTheme.postContentLight, height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Mini progression chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                _HarmonyLevel(label: 'New', range: '0–100', multiplier: '1.0x', isActive: true),
                const SizedBox(height: 8),
                _HarmonyLevel(label: 'Trusted', range: '100–500', multiplier: '1.5x', isActive: false),
                const SizedBox(height: 8),
                _HarmonyLevel(label: 'Pillar', range: '500+', multiplier: '2.0x', isActive: false),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _HarmonyLevel extends StatelessWidget {
  final String label;
  final String range;
  final String multiplier;
  final bool isActive;

  const _HarmonyLevel({
    required this.label,
    required this.range,
    required this.multiplier,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF4CAF50) : AppTheme.navyBlue.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppTheme.navyBlue : AppTheme.textDisabled,
          )),
        ),
        Text(range, style: TextStyle(fontSize: 11, color: AppTheme.textDisabled)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                : AppTheme.navyBlue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(multiplier, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: isActive ? const Color(0xFF4CAF50) : AppTheme.textDisabled,
          )),
        ),
      ],
    );
  }
}
