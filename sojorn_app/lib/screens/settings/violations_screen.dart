// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/violation.dart';
import '../../providers/violations_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../home/full_screen_shell.dart';
import 'appeal_form_sheet.dart';

class ViolationsScreen extends ConsumerWidget {
  const ViolationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(violationsProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final body = state.isLoading
        ? const Center(child: CircularProgressIndicator())
        : state.error != null && state.violations.isEmpty
            ? _buildError(context, ref, state.error!)
            : state.violations.isEmpty && state.summary == null
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: () => ref.read(violationsProvider.notifier).refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(SojornSpacing.lg),
                      children: [
                        if (state.summary != null) _buildSummaryCard(context, state.summary!),
                        if (state.summary != null) const SizedBox(height: SojornSpacing.lg),
                        if (state.violations.isNotEmpty) ...[
                          Text('Violations', style: AppTheme.textTheme.headlineSmall),
                          const SizedBox(height: SojornSpacing.sm),
                          ...state.violations.map((v) => _ViolationCard(violation: v)),
                        ],
                        if (state.violations.isEmpty && state.summary != null)
                          _buildEmpty(),
                        if (state.hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: SojornSpacing.md),
                            child: state.isLoadingMore
                                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(
                                    onPressed: () => ref.read(violationsProvider.notifier).loadMore(),
                                    child: const Text('Load more'),
                                  ),
                          ),
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
            'Violations & Appeals',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: body,
      );
    }

    return FullScreenShell(titleText: 'Violations & Appeals', body: body);
  }

  Widget _buildSummaryCard(BuildContext context, ViolationSummary summary) {
    final statusColor = switch (summary.currentStatus) {
      'good_standing' => AppTheme.success,
      'warned' => SojornColors.warning,
      'suspended' || 'banned' => SojornColors.destructive,
      _ => AppTheme.success,
    };
    final statusLabel = switch (summary.currentStatus) {
      'good_standing' => 'Good Standing',
      'warned' => 'Warned',
      'suspended' => 'Suspended',
      'banned' => 'Banned',
      _ => summary.currentStatus.replaceAll('_', ' '),
    };

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? SojornColors.darkSurfaceElevated.withValues(alpha: 0.6)
            : SojornColors.basicWhite.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(
          color: AppTheme.isDark
              ? SojornColors.darkBorder.withValues(alpha: 0.3)
              : AppTheme.egyptianBlue.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SojornRadii.full),
                ),
                child: Text(
                  statusLabel,
                  style: AppTheme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.shield_outlined, color: statusColor, size: 28),
            ],
          ),
          const SizedBox(height: SojornSpacing.md),
          Row(
            children: [
              _SummaryStat(label: 'Total', value: summary.totalViolations.toString()),
              const SizedBox(width: SojornSpacing.lg),
              _SummaryStat(
                label: 'Hard',
                value: summary.hardViolations.toString(),
                color: SojornColors.destructive,
              ),
              const SizedBox(width: SojornSpacing.lg),
              _SummaryStat(
                label: 'Soft',
                value: summary.softViolations.toString(),
                color: SojornColors.warning,
              ),
              const SizedBox(width: SojornSpacing.lg),
              _SummaryStat(
                label: 'Appeals',
                value: summary.activeAppeals.toString(),
                color: AppTheme.egyptianBlue,
              ),
            ],
          ),
          if (summary.banExpiry != null) ...[
            const SizedBox(height: SojornSpacing.sm),
            Text(
              'Ban expires: ${_formatDate(summary.banExpiry!)}',
              style: AppTheme.textTheme.bodySmall?.copyWith(color: SojornColors.destructive),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, size: 56, color: AppTheme.success.withValues(alpha: 0.5)),
            const SizedBox(height: SojornSpacing.md),
            Text('No violations on your account', style: AppTheme.textTheme.bodyLarge),
            const SizedBox(height: SojornSpacing.xs),
            Text(
              'Keep up the great work!',
              style: AppTheme.textTheme.bodySmall?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: SojornColors.destructive.withValues(alpha: 0.5)),
            const SizedBox(height: SojornSpacing.md),
            Text('Failed to load violations', style: AppTheme.textTheme.bodyLarge),
            const SizedBox(height: SojornSpacing.sm),
            TextButton(
              onPressed: () => ref.read(violationsProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.month}/${d.day}/${d.year}';
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.textTheme.titleLarge?.copyWith(
            color: color ?? AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: AppTheme.textTheme.labelSmall?.copyWith(
            color: AppTheme.navyText.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _ViolationCard extends ConsumerWidget {
  final UserViolation violation;

  const _ViolationCard({required this.violation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHard = violation.violationType == 'hard_violation';
    final chipColor = isHard ? SojornColors.destructive : SojornColors.warning;
    final chipLabel = isHard ? 'Hard' : 'Soft';

    final statusColor = switch (violation.status) {
      'active' => SojornColors.destructive,
      'appealed' => AppTheme.egyptianBlue,
      'upheld' => SojornColors.destructive,
      'overturned' => AppTheme.success,
      'expired' => AppTheme.navyText.withValues(alpha: 0.4),
      _ => AppTheme.navyText.withValues(alpha: 0.5),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: SojornSpacing.sm),
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? SojornColors.darkSurfaceElevated.withValues(alpha: 0.6)
            : SojornColors.basicWhite.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(
          color: AppTheme.isDark
              ? SojornColors.darkBorder.withValues(alpha: 0.3)
              : AppTheme.egyptianBlue.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SojornRadii.full),
                ),
                child: Text(
                  chipLabel,
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: chipColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: SojornSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SojornRadii.full),
                ),
                child: Text(
                  violation.status,
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                ViolationsScreen._formatDate(violation.createdAt),
                style: AppTheme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.navyText.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: SojornSpacing.sm),
          Text(
            violation.violationReason,
            style: AppTheme.textTheme.bodyMedium,
          ),
          if (violation.flagReason != null && violation.flagReason!.isNotEmpty) ...[
            const SizedBox(height: SojornSpacing.xs),
            Text(
              violation.flagReason!,
              style: AppTheme.textTheme.bodySmall?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (violation.appeal != null) ...[
            const SizedBox(height: SojornSpacing.sm),
            Container(
              padding: const EdgeInsets.all(SojornSpacing.sm),
              decoration: BoxDecoration(
                color: AppTheme.egyptianBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(SojornRadii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.gavel, size: 16, color: AppTheme.egyptianBlue),
                  const SizedBox(width: SojornSpacing.xs),
                  Expanded(
                    child: Text(
                      'Appeal ${violation.appeal!.status}',
                      style: AppTheme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.egyptianBlue,
                      ),
                    ),
                  ),
                  if (violation.appeal!.reviewDecision != null)
                    Text(
                      violation.appeal!.reviewDecision!,
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (violation.canAppeal && violation.appeal == null) ...[
            const SizedBox(height: SojornSpacing.sm),
            Row(
              children: [
                if (violation.appealDeadline != null)
                  Expanded(
                    child: Text(
                      'Appeal by ${ViolationsScreen._formatDate(violation.appealDeadline!)}',
                      style: AppTheme.textTheme.bodySmall?.copyWith(
                        color: SojornColors.warning,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => AppealFormSheet.show(context, ref, violation),
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text('Appeal'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.egyptianBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
