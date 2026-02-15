import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Multiline text input for long-form content (posts, comments, etc.)
class sojornTextArea extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool showCharacterCount;
  final bool enabled;
  final FocusNode? focusNode;

  const sojornTextArea({
    super.key,
    this.label,
    this.hint,
    this.errorText,
    this.controller,
    this.onChanged,
    this.minLines = 3,
    this.maxLines = 10,
    this.maxLength,
    this.showCharacterCount = true,
    this.enabled = true,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTheme.textTheme.labelMedium?.copyWith(
              color: AppTheme.navyBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
        ],
        TextField(
          controller: controller,
          onChanged: onChanged,
          enabled: enabled,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          focusNode: focusNode,
          style: AppTheme.bodyLarge,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            hintStyle: AppTheme.textTheme.bodyLarge
                ?.copyWith(color: AppTheme.egyptianBlue),
            errorStyle:
                AppTheme.textTheme.labelSmall?.copyWith(color: AppTheme.error),
            counterStyle: AppTheme.textTheme.labelSmall
                ?.copyWith(color: AppTheme.egyptianBlue),
          ),
        ),
      ],
    );
  }
}
