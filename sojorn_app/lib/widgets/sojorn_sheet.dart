// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Unified bottom sheet helper.
///
/// Use [SojornSheet.show] instead of calling [showModalBottomSheet] directly
/// to guarantee consistent border radius, drag handle, and background color.
///
/// Example:
/// ```dart
/// SojornSheet.show(
///   context,
///   child: MySheetContent(),
/// );
/// ```
class SojornSheet {
  const SojornSheet._();

  /// Shows a standard bottom sheet with the Sojorn design system appearance.
  ///
  /// - Transparent outer container so the rounded corners show correctly.
  /// - `SojornRadii.modal` (24px) top corner radius.
  /// - Drag handle drawn automatically.
  /// - [isScrollControlled] should be `true` when the sheet contains a
  ///   text field or is taller than ~50% of the screen.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    bool isScrollControlled = false,
    String? title,
    EdgeInsetsGeometry? padding,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      builder: (ctx) => _SojornSheetWrapper(
        title: title,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _SojornSheetWrapper extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry? padding;

  const _SojornSheetWrapper({
    required this.child,
    this.title,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SojornRadii.modal),
        ),
      ),
      padding: padding ??
          EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navyBlue,
                    ),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}
