// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_report.dart';
import '../../providers/report_history_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../home/full_screen_shell.dart';

class ReportHistoryScreen extends ConsumerWidget {
  const ReportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportHistoryProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final body = state.isLoading
        ? const Center(child: CircularProgressIndicator())
        : state.error != null && state.reports.isEmpty
            ? _buildError(ref)
            : state.reports.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: () => ref.read(reportHistoryProvider.notifier).refresh(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(SojornSpacing.lg),
                      itemCount: state.reports.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == state.reports.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: SojornSpacing.md),
                            child: state.isLoadingMore
                                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(
                                    onPressed: () => ref.read(reportHistoryProvider.notifier).loadMore(),
                                    child: const Text('Load more'),
                                  ),
                          );
                        }
                        return _ReportCard(report: state.reports[index]);
                      },
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
            'Report History',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: body,
      );
    }

    return FullScreenShell(titleText: 'Report History', body: body);
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 56, color: AppTheme.navyText.withValues(alpha: 0.3)),
            const SizedBox(height: SojornSpacing.md),
            Text('No reports submitted', style: AppTheme.textTheme.bodyLarge),
            const SizedBox(height: SojornSpacing.xs),
            Text(
              'Reports you submit will appear here',
              style: AppTheme.textTheme.bodySmall?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: SojornColors.destructive.withValues(alpha: 0.5)),
            const SizedBox(height: SojornSpacing.md),
            Text('Failed to load reports', style: AppTheme.textTheme.bodyLarge),
            const SizedBox(height: SojornSpacing.sm),
            TextButton(
              onPressed: () => ref.read(reportHistoryProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final UserReport report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (report.status) {
      'pending' => SojornColors.warning,
      'reviewed' => AppTheme.egyptianBlue,
      'actioned' => AppTheme.success,
      'dismissed' => AppTheme.navyText.withValues(alpha: 0.4),
      _ => AppTheme.navyText.withValues(alpha: 0.5),
    };

    final target = report.targetHandle ?? report.groupName ?? report.neighborhoodName ?? 'Unknown';

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
              Icon(Icons.flag, size: 16, color: AppTheme.navyText.withValues(alpha: 0.4)),
              const SizedBox(width: SojornSpacing.xs),
              Expanded(
                child: Text(
                  report.targetHandle != null ? '@$target' : target,
                  style: AppTheme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SojornRadii.full),
                ),
                child: Text(
                  report.status,
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SojornSpacing.xs),
          Text(
            report.violationType.replaceAll('_', ' '),
            style: AppTheme.textTheme.bodySmall?.copyWith(
              color: AppTheme.navyText.withValues(alpha: 0.6),
            ),
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: SojornSpacing.xs),
            Text(
              report.description,
              style: AppTheme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: SojornSpacing.xs),
          Text(
            '${report.createdAt.month}/${report.createdAt.day}/${report.createdAt.year}',
            style: AppTheme.textTheme.bodySmall?.copyWith(
              color: AppTheme.navyText.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
