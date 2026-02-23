// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/trust_tier.dart';
import '../../models/trust_state.dart';
import '../../theme/tokens.dart';

/// Compact trust tier badge — shows emoji + tier name.
/// Used on profile headers, post cards, and hover cards.
///
/// Usage:
///   TierBadge(tier: profile.trustTier)
///   TierBadge.fromState(trustState)
///   TierBadge(tier: tier, showProgress: true, harmonyScore: 47)
class TierBadge extends StatelessWidget {
  final TrustTier tier;
  final bool compact;       // true = emoji only, false = emoji + name
  final bool showProgress;  // show score/progress toward next tier
  final int? harmonyScore;

  const TierBadge({
    super.key,
    required this.tier,
    this.compact = false,
    this.showProgress = false,
    this.harmonyScore,
  });

  factory TierBadge.fromState(TrustState state, {bool compact = false, bool showProgress = false}) {
    return TierBadge(
      tier: state.tier,
      compact: compact,
      showProgress: showProgress,
      harmonyScore: state.harmonyScore,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = tier.color;

    if (compact) {
      return Tooltip(
        message: '${tier.emoji} ${tier.displayName}',
        child: Text(tier.emoji, style: const TextStyle(fontSize: 14)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SojornRadii.full),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tier.emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              Text(
                tier.displayName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        if (showProgress && harmonyScore != null && tier.next != null) ...[
          const SizedBox(height: 4),
          _ProgressBar(tier: tier, score: harmonyScore!),
        ],
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final TrustTier tier;
  final int score;

  const _ProgressBar({required this.tier, required this.score});

  @override
  Widget build(BuildContext context) {
    final next = tier.next!;
    final range = tier.maxScore - tier.minScore;
    final progress = ((score - tier.minScore) / range).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: tier.color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(tier.color),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score / ${next.minScore} → ${next.emoji} ${next.displayName}',
          style: TextStyle(
            fontSize: 9,
            color: tier.color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Full Harmony Score card — used in profile settings / trust score screens.
class HarmonyScoreCard extends StatelessWidget {
  final TrustState state;

  const HarmonyScoreCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final tier = state.tier;
    final score = state.harmonyScore;
    final next = tier.next;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tier.color.withValues(alpha: 0.1),
            tier.color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: tier.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tier.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tier.color,
                      ),
                    ),
                    Text(
                      'Harmony Score: $score / 100',
                      style: TextStyle(
                        fontSize: 12,
                        color: tier.color.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ((score - tier.minScore) / (tier.maxScore - tier.minScore)).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: tier.color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(tier.color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${next.minScore - score} points to ${next.emoji} ${next.displayName}',
              style: TextStyle(fontSize: 11, color: tier.color.withValues(alpha: 0.65)),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Maximum tier reached',
              style: TextStyle(fontSize: 11, color: tier.color.withValues(alpha: 0.65)),
            ),
          ],
          const SizedBox(height: 14),
          _buildGates(tier),
        ],
      ),
    );
  }

  Widget _buildGates(TrustTier tier) {
    final gates = [
      (label: 'Post up to ${tier.postLimit}×/day', unlocked: true),
      (label: 'Confirm beacons', unlocked: tier.canVouchBeacons),
      (label: 'Create events', unlocked: tier.canCreateEvents),
      (label: 'Create groups', unlocked: tier.canCreateGroups),
      (label: 'Pin posts', unlocked: tier.canPinPosts),
      (label: 'Weighted beacon votes (×2)', unlocked: tier.beaconVouchWeight > 1),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: gates.map((g) => _GateChip(label: g.label, unlocked: g.unlocked, tier: tier)).toList(),
    );
  }
}

class _GateChip extends StatelessWidget {
  final String label;
  final bool unlocked;
  final TrustTier tier;

  const _GateChip({required this.label, required this.unlocked, required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? tier.color : const Color(0xFF9E9E9E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: unlocked ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: unlocked ? 0.3 : 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unlocked ? Icons.check_circle_outline : Icons.lock_outline,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: unlocked ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
