// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

class QuillEditorWrapper extends StatelessWidget {
  final QuillController controller;
  final FocusNode? focusNode;
  final String placeholder;

  const QuillEditorWrapper({
    super.key,
    required this.controller,
    this.focusNode,
    this.placeholder = 'Unleash your thoughts with vibrant energy...',
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toolbar
          Container(
            color: AppTheme.queenPink.withValues(alpha: 0.15),
            child: QuillSimpleToolbar(
              controller: controller,
              config: const QuillSimpleToolbarConfig(
                decoration: BoxDecoration(),
                toolbarIconAlignment: WrapAlignment.start,
              ),
            ),
          ),
          
          // Editor
          Container(
            constraints: const BoxConstraints(minHeight: 200),
            decoration: const BoxDecoration(
              color: SojornColors.basicWhite,
            ),
            child: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode ?? FocusNode(),
              config: QuillEditorConfig(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                placeholder: placeholder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
