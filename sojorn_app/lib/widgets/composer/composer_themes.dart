// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Simple text styling options (Twitter/Bluesky style)
enum TextStyleOption {
  normal,
  bold,
  italic,
}

/// Text style controller for the composer
class TextStyleController extends ChangeNotifier {
  final Set<TextStyleOption> _activeStyles = {};

  Set<TextStyleOption> get activeStyles => _activeStyles;

  void toggleStyle(TextStyleOption style) {
    if (_activeStyles.contains(style)) {
      _activeStyles.remove(style);
    } else {
      _activeStyles.add(style);
    }
    notifyListeners();
  }

  void clearStyles() {
    _activeStyles.clear();
    notifyListeners();
  }

  TextStyle applyStyles(TextStyle base) {
    TextStyle result = base;
    if (_activeStyles.contains(TextStyleOption.bold)) {
      result = result.copyWith(fontWeight: FontWeight.bold);
    }
    if (_activeStyles.contains(TextStyleOption.italic)) {
      result = result.copyWith(fontStyle: FontStyle.italic);
    }
    return result;
  }
}

/// Simple formatting toolbar (Twitter style - minimal)
class FormattingToolbar extends StatelessWidget {
  final TextStyleController styleController;
  final VoidCallback? onAddImage;

  const FormattingToolbar({
    super.key,
    required this.styleController,
    this.onAddImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSm, vertical: AppTheme.spacingXs),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          _buildStyleButton(
            icon: Icons.format_bold,
            label: 'Bold',
            isActive: styleController.activeStyles.contains(TextStyleOption.bold),
            onTap: () => styleController.toggleStyle(TextStyleOption.bold),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          _buildStyleButton(
            icon: Icons.format_italic,
            label: 'Italic',
            isActive: styleController.activeStyles.contains(TextStyleOption.italic),
            onTap: () => styleController.toggleStyle(TextStyleOption.italic),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          if (onAddImage != null)
            IconButton(
              onPressed: onAddImage,
              icon: const Icon(Icons.image_outlined),
              color: AppTheme.egyptianBlue,
              tooltip: 'Add image',
            ),
        ],
      ),
    );
  }

  Widget _buildStyleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.queenPink.withValues(alpha: 0.3) : SojornColors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isActive ? AppTheme.royalPurple : AppTheme.egyptianBlue,
        ),
      ),
    );
  }
}
