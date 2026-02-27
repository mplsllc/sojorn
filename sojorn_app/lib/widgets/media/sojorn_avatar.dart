// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'signed_media_image.dart';

/// A rounded-square avatar widget used consistently across the app.
///
/// Shows the user's photo if available, otherwise their initial letter
/// on a hash-based background color.
class SojornAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double size;
  /// Corner radius — defaults to size * 0.28 (rounded square feel)
  final double? borderRadius;

  const SojornAvatar({
    super.key,
    required this.displayName,
    this.avatarUrl,
    this.size = 40,
    this.borderRadius,
  });

  double get _radius => borderRadius ?? (size * 0.28).clamp(6, 20);

  Color _backgroundColor() {
    const colors = [
      Color(0xFF1B4FD8),
      Color(0xFF7C3AED),
      Color(0xFF0D9488),
      Color(0xFFD97706),
      Color(0xFFDC2626),
      Color(0xFF059669),
      Color(0xFF7C2D12),
      Color(0xFF1D4ED8),
    ];
    final code = displayName.isNotEmpty ? displayName.codeUnitAt(0) : 65;
    return colors[code % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final letter =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final url = avatarUrl;

    return Semantics(
      image: true,
      label: '$displayName avatar',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: SizedBox(
          width: size,
          height: size,
          child: url != null && url.isNotEmpty
              ? SignedMediaImage(
                  url: url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: _backgroundColor(),
                  alignment: Alignment.center,
                  child: ExcludeSemantics(
                    child: Text(
                      letter,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: size * 0.38,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
