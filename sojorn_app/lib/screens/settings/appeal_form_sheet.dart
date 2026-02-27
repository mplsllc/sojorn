// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/violation.dart';
import '../../providers/violations_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/sojorn_sheet.dart';

class AppealFormSheet extends StatefulWidget {
  final UserViolation violation;
  final WidgetRef ref;

  const AppealFormSheet({super.key, required this.violation, required this.ref});

  static void show(BuildContext context, WidgetRef ref, UserViolation violation) {
    SojornSheet.show(
      context,
      title: 'Appeal Violation',
      isScrollControlled: true,
      child: AppealFormSheet(violation: violation, ref: ref),
    );
  }

  @override
  State<AppealFormSheet> createState() => _AppealFormSheetState();
}

class _AppealFormSheetState extends State<AppealFormSheet> {
  final _reasonController = TextEditingController();
  final _contextController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  int get _reasonLength => _reasonController.text.trim().length;
  bool get _isValid => _reasonLength >= 10 && _reasonLength <= 1000;

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);

    final success = await widget.ref.read(violationsProvider.notifier).submitAppeal(
          violationId: widget.violation.id,
          reason: _reasonController.text.trim(),
          context: _contextController.text.trim().isNotEmpty ? _contextController.text.trim() : null,
        );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      context.showSuccess('Appeal submitted successfully');
    } else {
      setState(() => _submitting = false);
      context.showError('Failed to submit appeal. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: SojornSpacing.lg,
        right: SojornSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + SojornSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(SojornSpacing.sm),
            decoration: BoxDecoration(
              color: (widget.violation.violationType == 'hard_violation'
                      ? SojornColors.destructive
                      : SojornColors.warning)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(SojornRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: widget.violation.violationType == 'hard_violation'
                      ? SojornColors.destructive
                      : SojornColors.warning,
                ),
                const SizedBox(width: SojornSpacing.xs),
                Expanded(
                  child: Text(
                    widget.violation.violationReason,
                    style: AppTheme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SojornSpacing.lg),
          Text(
            'Why should this be reconsidered?',
            style: AppTheme.textTheme.labelLarge,
          ),
          const SizedBox(height: SojornSpacing.sm),
          TextField(
            controller: _reasonController,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Explain why you believe this violation should be overturned...',
              hintStyle: AppTheme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.3),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue),
              ),
              contentPadding: const EdgeInsets.all(SojornSpacing.md),
            ),
          ),
          if (_reasonLength > 0 && _reasonLength < 10)
            Padding(
              padding: const EdgeInsets.only(top: SojornSpacing.xs),
              child: Text(
                '${10 - _reasonLength} more characters needed',
                style: AppTheme.textTheme.labelSmall?.copyWith(color: SojornColors.warning),
              ),
            ),
          const SizedBox(height: SojornSpacing.md),
          Text(
            'Additional context (optional)',
            style: AppTheme.textTheme.labelLarge,
          ),
          const SizedBox(height: SojornSpacing.sm),
          TextField(
            controller: _contextController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Any relevant context or circumstances...',
              hintStyle: AppTheme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.3),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.egyptianBlue),
              ),
              contentPadding: const EdgeInsets.all(SojornSpacing.md),
            ),
          ),
          const SizedBox(height: SojornSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isValid && !_submitting ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.egyptianBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SojornRadii.md),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Appeal'),
            ),
          ),
        ],
      ),
    );
  }
}
