// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../models/trust_state.dart';
import '../models/trust_tier.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Modal that explains the Harmony State system.
/// Shows current level, progression chart, and tips.
class HarmonyExplainerModal extends StatelessWidget {
  final TrustState trustState;

  const HarmonyExplainerModal({super.key, required this.trustState});

  static void show(BuildContext context, TrustState trustState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HarmonyExplainerModal(trustState: trustState),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 20),

            // Title
            Text('What is Harmony State?', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.navyBlue,
            )),
            const SizedBox(height: 10),
            Text(
              'Your Harmony State is your community contribution score. It affects your reach multiplier — how far your posts travel.',
              style: TextStyle(fontSize: 14, color: SojornColors.postContentLight, height: 1.5),
            ),
            const SizedBox(height: 24),

            // Current state card
            _CurrentStateCard(trustState: trustState),
            const SizedBox(height: 24),

            // Progression chart
            Text('Progression', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
            )),
            const SizedBox(height: 12),
            _ProgressionChart(currentTier: trustState.tier),
            const SizedBox(height: 24),

            // How to increase
            Text('How to Increase Harmony', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
            )),
            const SizedBox(height: 12),
            _TipRow(icon: Icons.check_circle, color: const Color(0xFF4CAF50),
              text: 'Post helpful beacons that get upvoted'),
            _TipRow(icon: Icons.check_circle, color: const Color(0xFF4CAF50),
              text: 'Create posts that receive positive engagement'),
            _TipRow(icon: Icons.check_circle, color: const Color(0xFF4CAF50),
              text: 'Participate in chains constructively'),
            _TipRow(icon: Icons.check_circle, color: const Color(0xFF4CAF50),
              text: 'Join and contribute to groups'),
            const SizedBox(height: 16),

            // What decreases
            Text('What Decreases Harmony', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
            )),
            const SizedBox(height: 12),
            _TipRow(icon: Icons.cancel, color: SojornColors.destructive,
              text: 'Spam or inappropriate content'),
            _TipRow(icon: Icons.cancel, color: SojornColors.destructive,
              text: 'Beacons that get downvoted as false'),
            _TipRow(icon: Icons.cancel, color: SojornColors.destructive,
              text: 'Repeated community guideline violations'),
          ],
        ),
      ),
    );
  }
}

class _CurrentStateCard extends StatelessWidget {
  final TrustState trustState;
  const _CurrentStateCard({required this.trustState});

  @override
  Widget build(BuildContext context) {
    final tier = trustState.tier;
    final score = trustState.harmonyScore;
    final multiplier = _multiplierForTier(tier);
    final nextTier = _nextTier(tier);
    final nextThreshold = _thresholdForTier(nextTier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.navyBlue.withValues(alpha: 0.06),
            AppTheme.brightNavy.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _colorForTier(tier).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_graph, color: _colorForTier(tier), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current: ${tier.displayName}', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
                    )),
                    Text('Score: $score', style: TextStyle(
                      fontSize: 13, color: SojornColors.textDisabled,
                    )),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _colorForTier(tier).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${multiplier}x reach', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _colorForTier(tier),
                )),
              ),
            ],
          ),
          if (nextTier != null) ...[
            const SizedBox(height: 14),
            // Progress bar to next tier
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Next: ${nextTier.displayName}', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: SojornColors.textDisabled,
                    )),
                    Text('$score / $nextThreshold', style: TextStyle(
                      fontSize: 12, color: SojornColors.textDisabled,
                    )),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (score / nextThreshold).clamp(0.0, 1.0),
                    backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(_colorForTier(tier)),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _multiplierForTier(TrustTier tier) {
    switch (tier) {
      case TrustTier.new_user: return '1.0';
      case TrustTier.established: return '1.5';
      case TrustTier.trusted: return '2.0';
    }
  }

  TrustTier? _nextTier(TrustTier tier) {
    switch (tier) {
      case TrustTier.new_user: return TrustTier.established;
      case TrustTier.established: return TrustTier.trusted;
      case TrustTier.trusted: return null;
    }
  }

  int _thresholdForTier(TrustTier? tier) {
    switch (tier) {
      case TrustTier.established: return 100;
      case TrustTier.trusted: return 500;
      default: return 100;
    }
  }

  Color _colorForTier(TrustTier tier) {
    switch (tier) {
      case TrustTier.new_user: return AppTheme.egyptianBlue;
      case TrustTier.established: return AppTheme.royalPurple;
      case TrustTier.trusted: return const Color(0xFF4CAF50);
    }
  }
}

class _ProgressionChart extends StatelessWidget {
  final TrustTier currentTier;
  const _ProgressionChart({required this.currentTier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.navyBlue.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _LevelRow(label: 'New', range: '0–100', multiplier: '1.0x',
            color: AppTheme.egyptianBlue, isActive: currentTier == TrustTier.new_user),
          const SizedBox(height: 10),
          _LevelRow(label: 'Established', range: '100–500', multiplier: '1.5x',
            color: AppTheme.royalPurple, isActive: currentTier == TrustTier.established),
          const SizedBox(height: 10),
          _LevelRow(label: 'Trusted', range: '500+', multiplier: '2.0x',
            color: const Color(0xFF4CAF50), isActive: currentTier == TrustTier.trusted),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final String label;
  final String range;
  final String multiplier;
  final Color color;
  final bool isActive;

  const _LevelRow({
    required this.label, required this.range,
    required this.multiplier, required this.color, required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: color, width: 2) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(
          fontSize: 14, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? AppTheme.navyBlue : SojornColors.textDisabled,
        ))),
        Text(range, style: TextStyle(fontSize: 12, color: SojornColors.textDisabled)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.12) : AppTheme.navyBlue.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(multiplier, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: isActive ? color : SojornColors.textDisabled,
          )),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _TipRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(
            fontSize: 13, color: SojornColors.postContentLight, height: 1.4,
          ))),
        ],
      ),
    );
  }
}
