import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Custom text input widget enforcing sojorn's visual system
class sojornInput extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final bool showCharacterCount;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconPressed;
  final FocusNode? focusNode;
  final List<String>? autofillHints;

  const sojornInput({
    super.key,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.controller,
    this.onChanged,
    this.onEditingComplete,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.showCharacterCount = false,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.focusNode,
    this.autofillHints,
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
          onEditingComplete: onEditingComplete,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          enabled: enabled,
          maxLines: maxLines,
          maxLength: showCharacterCount ? maxLength : null,
          inputFormatters: inputFormatters,
          focusNode: focusNode,
          autofillHints: autofillHints,
          style: AppTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AppTheme.egyptianBlue, size: 20)
                : null,
            prefix: prefix,
            suffixIcon: suffixIcon != null
                ? IconButton(
                    icon: Icon(suffixIcon,
                        color: AppTheme.egyptianBlue, size: 20),
                    onPressed: onSuffixIconPressed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : null,
            suffix: suffix,
            hintStyle: AppTheme.textTheme.bodyMedium
                ?.copyWith(color: AppTheme.egyptianBlue),
            errorStyle:
                AppTheme.textTheme.labelSmall?.copyWith(color: AppTheme.error),
            helperStyle: AppTheme.textTheme.labelSmall
                ?.copyWith(color: AppTheme.egyptianBlue),
            counterStyle: AppTheme.textTheme.labelSmall
                ?.copyWith(color: AppTheme.egyptianBlue),
          ),
        ),
      ],
    );
  }
}
