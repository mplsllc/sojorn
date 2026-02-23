// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile_privacy_settings.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Privacy Dashboard — a single-screen overview of all privacy settings
/// with inline toggles and visual status indicators.
class PrivacyDashboardScreen extends ConsumerStatefulWidget {
  const PrivacyDashboardScreen({super.key});

  @override
  ConsumerState<PrivacyDashboardScreen> createState() => _PrivacyDashboardScreenState();
}

class _PrivacyDashboardScreenState extends ConsumerState<PrivacyDashboardScreen> {
  ProfilePrivacySettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final settings = await api.getPrivacySettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save(ProfilePrivacySettings updated) async {
    setState(() {
      _settings = updated;
      _isSaving = true;
    });
    try {
      final api = ref.read(apiServiceProvider);
      await api.updatePrivacySettings(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBg,
        surfaceTintColor: SojornColors.transparent,
        title: const Text('Privacy Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _settings == null
              ? Center(child: Text('Could not load settings', style: TextStyle(color: SojornColors.textDisabled)))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // Privacy score summary
                    _PrivacyScoreCard(settings: _settings!),
                    const SizedBox(height: 20),

                    // Account Visibility
                    _SectionTitle(title: 'Account Visibility'),
                    const SizedBox(height: 8),
                    _ToggleTile(
                      icon: Icons.lock_outline,
                      title: 'Private Profile',
                      subtitle: 'Only followers can see your posts',
                      value: _settings!.isPrivate,
                      onChanged: (v) => _save(_settings!.copyWith(isPrivate: v)),
                    ),
                    _ToggleTile(
                      icon: Icons.search,
                      title: 'Appear in Search',
                      subtitle: 'Let others find you by name or handle',
                      value: _settings!.showInSearch,
                      onChanged: (v) => _save(_settings!.copyWith(showInSearch: v)),
                    ),
                    _ToggleTile(
                      icon: Icons.recommend,
                      title: 'Appear in Suggestions',
                      subtitle: 'Show in "People you may know"',
                      value: _settings!.showInSuggestions,
                      onChanged: (v) => _save(_settings!.copyWith(showInSuggestions: v)),
                    ),
                    _ToggleTile(
                      icon: Icons.circle,
                      title: 'Activity Status',
                      subtitle: 'Show when you\'re online',
                      value: _settings!.showActivityStatus,
                      onChanged: (v) => _save(_settings!.copyWith(showActivityStatus: v)),
                    ),
                    const SizedBox(height: 20),

                    // Content Controls
                    _SectionTitle(title: 'Content Controls'),
                    const SizedBox(height: 8),
                    _ChoiceTile(
                      icon: Icons.article_outlined,
                      title: 'Default Post Visibility',
                      value: _settings!.defaultVisibility,
                      options: const {'public': 'Public', 'followers': 'Followers', 'private': 'Only Me'},
                      onChanged: (v) => _save(_settings!.copyWith(defaultVisibility: v)),
                    ),
                    _ToggleTile(
                      icon: Icons.link,
                      title: 'Allow Chains',
                      subtitle: 'Let others reply-chain to your posts',
                      value: _settings!.allowChains,
                      onChanged: (v) => _save(_settings!.copyWith(allowChains: v)),
                    ),
                    const SizedBox(height: 20),

                    // Interaction Controls
                    _SectionTitle(title: 'Interaction Controls'),
                    const SizedBox(height: 8),
                    _ChoiceTile(
                      icon: Icons.chat_bubble_outline,
                      title: 'Who Can Message',
                      value: _settings!.whoCanMessage,
                      options: const {'everyone': 'Everyone', 'followers': 'Followers', 'nobody': 'Nobody'},
                      onChanged: (v) => _save(_settings!.copyWith(whoCanMessage: v)),
                    ),
                    _ChoiceTile(
                      icon: Icons.comment_outlined,
                      title: 'Who Can Comment',
                      value: _settings!.whoCanComment,
                      options: const {'everyone': 'Everyone', 'followers': 'Followers', 'nobody': 'Nobody'},
                      onChanged: (v) => _save(_settings!.copyWith(whoCanComment: v)),
                    ),
                    _ChoiceTile(
                      icon: Icons.person_add_outlined,
                      title: 'Follow Requests',
                      value: _settings!.followRequestPolicy,
                      options: const {'everyone': 'Auto-accept', 'manual': 'Manual Approval'},
                      onChanged: (v) => _save(_settings!.copyWith(followRequestPolicy: v)),
                    ),
                    const SizedBox(height: 20),

                    // Data & Encryption
                    _SectionTitle(title: 'Data & Encryption'),
                    const SizedBox(height: 8),
                    _InfoTile(
                      icon: Icons.shield_outlined,
                      title: 'End-to-End Encryption',
                      subtitle: 'Capsule messages are always E2EE',
                      badge: 'Active',
                      badgeColor: const Color(0xFF4CAF50),
                    ),
                    _InfoTile(
                      icon: Icons.vpn_key_outlined,
                      title: 'ALTCHA Verification',
                      subtitle: 'Proof-of-work protects your account',
                      badge: 'Active',
                      badgeColor: const Color(0xFF4CAF50),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}

// ── Privacy Score Card ────────────────────────────────────────────────────
class _PrivacyScoreCard extends StatelessWidget {
  final ProfilePrivacySettings settings;
  const _PrivacyScoreCard({required this.settings});

  int _calculateScore() {
    int score = 50; // base
    if (settings.isPrivate) score += 15;
    if (!settings.showActivityStatus) score += 5;
    if (!settings.showInSuggestions) score += 5;
    if (settings.whoCanMessage == 'followers') score += 5;
    if (settings.whoCanMessage == 'nobody') score += 10;
    if (settings.whoCanComment == 'followers') score += 5;
    if (settings.whoCanComment == 'nobody') score += 10;
    if (settings.defaultVisibility == 'followers') score += 5;
    if (settings.defaultVisibility == 'private') score += 10;
    if (settings.followRequestPolicy == 'manual') score += 5;
    return score.clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final score = _calculateScore();
    final label = score >= 80 ? 'Fort Knox' : score >= 60 ? 'Well Protected' : score >= 40 ? 'Balanced' : 'Open';
    final color = score >= 80 ? const Color(0xFF4CAF50) : score >= 60 ? const Color(0xFF2196F3) : score >= 40 ? const Color(0xFFFFC107) : const Color(0xFFFF9800);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.03)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60, height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 5,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text('$score', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color,
                )),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Privacy Level: $label', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
                )),
                const SizedBox(height: 4),
                Text(
                  'Your data is encrypted. Adjust settings below to control who sees what.',
                  style: TextStyle(fontSize: 12, color: SojornColors.textDisabled, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700,
      color: AppTheme.navyBlue.withValues(alpha: 0.6),
      letterSpacing: 0.5,
    ));
  }
}

// ── Toggle Tile ───────────────────────────────────────────────────────────
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon, required this.title,
    required this.subtitle, required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTheme.navyBlue,
          ),
        ],
      ),
    );
  }
}

// ── Choice Tile (segmented) ───────────────────────────────────────────────
class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _ChoiceTile({
    required this.icon, required this.title,
    required this.value, required this.options, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: options.entries.map((e) => ButtonSegment(
                value: e.key,
                label: Text(e.value, style: const TextStyle(fontSize: 11)),
              )).toList(),
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info Tile (read-only with badge) ──────────────────────────────────────
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;

  const _InfoTile({
    required this.icon, required this.title,
    required this.subtitle, required this.badge, required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: badgeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(badge, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor,
            )),
          ),
        ],
      ),
    );
  }
}
