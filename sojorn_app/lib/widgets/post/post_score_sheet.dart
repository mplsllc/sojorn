// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../sojorn_sheet.dart';

/// Shows the algorithmic score breakdown for a post.
/// Only works for the post author — backend enforces this.
class PostScoreSheet extends StatefulWidget {
  final String postId;

  const PostScoreSheet({super.key, required this.postId});

  static Future<void> show(BuildContext context, String postId) {
    return SojornSheet.show(
      context,
      isScrollControlled: true,
      child: PostScoreSheet(postId: postId),
    );
  }

  @override
  State<PostScoreSheet> createState() => _PostScoreSheetState();
}

class _PostScoreSheetState extends State<PostScoreSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.instance.getPostScore(widget.postId);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final score = (_data!['score'] as num).toDouble();
    final summary = _data!['summary'] as String;
    final factors = (_data!['factors'] as List).cast<Map<String, dynamic>>();
    final scoredAt = _data!['scored_at'] as String?;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.insights_outlined, color: AppTheme.brightNavy, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Post Score',
                  style: AppTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(score).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SojornRadii.full),
                  ),
                  child: Text(
                    score.toStringAsFixed(3),
                    style: AppTheme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _scoreColor(score),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Summary
            Text(
              summary,
              style: AppTheme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Factor breakdown
            ...factors.map((f) => _buildFactorRow(f)),

            if (scoredAt != null) ...[
              const SizedBox(height: 16),
              Text(
                'Last scored: ${_formatTime(scoredAt)}',
                style: AppTheme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              'Posts are scored purely on content merit — not your account. Scores update every 15 minutes.',
              style: AppTheme.textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFactorRow(Map<String, dynamic> factor) {
    final name = factor['name'] as String;
    final score = (factor['score'] as num).toDouble();
    final weight = (factor['weight'] as num).toDouble();
    final weighted = (factor['weighted'] as num).toDouble();
    final explanation = factor['explanation'] as String;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_factorIcon(name), size: 16, color: _factorColor(weighted)),
              const SizedBox(width: 6),
              Text(
                _factorLabel(name),
                style: AppTheme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${weighted >= 0 ? '+' : ''}${weighted.toStringAsFixed(3)}',
                style: AppTheme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _factorColor(weighted),
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Visual bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score.abs().clamp(0.0, 1.0),
              backgroundColor: AppTheme.borderSubtle.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(_factorColor(weighted).withValues(alpha: 0.6)),
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            style: AppTheme.textTheme.labelSmall?.copyWith(
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
          Text(
            'Raw: ${score.toStringAsFixed(2)} × ${(weight * 100).toStringAsFixed(0)}% weight',
            style: AppTheme.textTheme.labelSmall?.copyWith(
              color: AppTheme.textSecondary.withValues(alpha: 0.35),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score <= -1.0) return AppTheme.error;
    if (score < 0) return AppTheme.warning;
    if (score < 0.15) return AppTheme.textSecondary;
    return AppTheme.success;
  }

  Color _factorColor(double weighted) {
    if (weighted < -0.01) return AppTheme.error;
    if (weighted < 0.005) return AppTheme.textSecondary;
    return AppTheme.success;
  }

  IconData _factorIcon(String name) {
    return switch (name) {
      'engagement' => Icons.favorite_outline,
      'quality' => Icons.auto_awesome_outlined,
      'recency' => Icons.schedule_outlined,
      'network' => Icons.people_outline,
      'personalization' => Icons.tune_outlined,
      'tone' => Icons.sentiment_satisfied_outlined,
      'video_boost' => Icons.videocam_outlined,
      'harmony' => Icons.handshake_outlined,
      'moderation' => Icons.shield_outlined,
      _ => Icons.circle_outlined,
    };
  }

  String _factorLabel(String name) {
    return switch (name) {
      'engagement' => 'Engagement',
      'quality' => 'Quality',
      'recency' => 'Recency',
      'network' => 'Network',
      'personalization' => 'Personalization',
      'tone' => 'Tone',
      'video_boost' => 'Video Boost',
      'harmony' => 'Harmony',
      'moderation' => 'Moderation',
      _ => name,
    };
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return iso;
    }
  }
}
