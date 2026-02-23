// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

class ContextMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

class DesktopContextMenu {
  static void show(
    BuildContext context, {
    required Offset position,
    required List<ContextMenuItem> items,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final relativeRect = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    showMenu<int>(
      context: context,
      position: relativeRect,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SojornRadii.lg),
      ),
      color: AppTheme.cardSurface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      items: List.generate(items.length, (index) {
        final item = items[index];
        final color =
            item.isDestructive ? SojornColors.destructive : AppTheme.navyText;

        return PopupMenuItem<int>(
          value: index,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    ).then((selected) {
      if (selected != null && selected >= 0 && selected < items.length) {
        items[selected].onTap();
      }
    });
  }
}
