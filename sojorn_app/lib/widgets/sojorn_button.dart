import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Custom button widget enforcing sojorn's visual system
/// Variants: primary, secondary, tertiary, destructive
class sojornButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final sojornButtonVariant variant;
  final sojornButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  const sojornButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = sojornButtonVariant.primary,
    this.size = sojornButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: _getHeight(),
      child: _buildButton(isDisabled),
    );
  }

  double _getHeight() {
    switch (size) {
      case sojornButtonSize.small:
        return 40;
      case sojornButtonSize.medium:
        return 48;
      case sojornButtonSize.large:
        return 56;
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case sojornButtonSize.small:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        );
      case sojornButtonSize.medium:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingMd,
        );
      case sojornButtonSize.large:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg * 1.5, // Replaced AppTheme.spacingXl
          vertical: AppTheme.spacingMd,
        );
    }
  }

  TextStyle _getTextStyle() {
    final baseStyle = size == sojornButtonSize.small
        ? AppTheme.textTheme.labelMedium // Using textTheme
        : AppTheme.textTheme.labelMedium
            ?.copyWith(fontSize: 16); // A bit larger for labelLarge equivalent

    return baseStyle!.copyWith(
      fontWeight: FontWeight.w600,
      color: _getTextColor(),
    );
  }

  Color _getTextColor() {
    switch (variant) {
      case sojornButtonVariant.primary:
      case sojornButtonVariant.destructive:
        return AppTheme.white; // Replaced AppTheme.textOnAccent
      case sojornButtonVariant.secondary:
      case sojornButtonVariant.tertiary:
        return AppTheme.brightNavy; // Replaced AppTheme.accent
    }
  }

  Widget _buildButton(bool isDisabled) {
    switch (variant) {
      case sojornButtonVariant.primary:
        return ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brightNavy, // Replaced AppTheme.accent
            foregroundColor: AppTheme.white, // Replaced AppTheme.textOnAccent
            disabledBackgroundColor:
                AppTheme.queenPinkLight, // Replaced AppTheme.surfaceVariant
            disabledForegroundColor: AppTheme.navyText
                .withValues(alpha: 0.5), // Replaced AppTheme.textDisabled
            elevation: 0,
            shadowColor: SojornColors.transparent,
            padding: _getPadding(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  AppTheme.radiusMd), // Replaced AppTheme.radiusMd
            ),
          ),
          child: _buildContent(),
        );

      case sojornButtonVariant.destructive:
        return ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            foregroundColor: AppTheme.white, // Replaced AppTheme.textOnAccent
            disabledBackgroundColor:
                AppTheme.queenPinkLight, // Replaced AppTheme.surfaceVariant
            disabledForegroundColor: AppTheme.navyText
                .withValues(alpha: 0.5), // Replaced AppTheme.textDisabled
            elevation: 0,
            shadowColor: SojornColors.transparent,
            padding: _getPadding(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  AppTheme.radiusMd), // Replaced AppTheme.radiusMd
            ),
          ),
          child: _buildContent(),
        );

      case sojornButtonVariant.secondary:
        return OutlinedButton(
          onPressed: isDisabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.brightNavy, // Replaced AppTheme.accent
            disabledForegroundColor: AppTheme.navyText
                .withValues(alpha: 0.5), // Replaced AppTheme.textDisabled
            side: BorderSide(
              color: isDisabled
                  ? AppTheme.egyptianBlue.withValues(alpha: 0.5)
                  : AppTheme.egyptianBlue, // Replaced borderSubtle and border
              width: 1,
            ),
            padding: _getPadding(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  AppTheme.radiusMd), // Replaced AppTheme.radiusMd
            ),
          ),
          child: _buildContent(),
        );

      case sojornButtonVariant.tertiary:
        return TextButton(
          onPressed: isDisabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.brightNavy, // Replaced AppTheme.accent
            disabledForegroundColor: AppTheme.navyText
                .withValues(alpha: 0.5), // Replaced AppTheme.textDisabled
            padding: _getPadding(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  AppTheme.radiusSm), // Replaced AppTheme.radiusSm
            ),
          ),
          child: _buildContent(),
        );
    }
  }

  Widget _buildContent() {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.white), // Replaced _getTextColor
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon!, size: 18, color: _getTextColor()),
          const SizedBox(width: AppTheme.spacingSm),
          Text(label, style: _getTextStyle()),
        ],
      );
    }

    return Text(label, style: _getTextStyle());
  }
}

enum sojornButtonVariant {
  primary, // Filled with accent color
  secondary, // Outlined
  tertiary, // Text only
  destructive, // Filled with error color
}

enum sojornButtonSize {
  small,
  medium,
  large,
}
