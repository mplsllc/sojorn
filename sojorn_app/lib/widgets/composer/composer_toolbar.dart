// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Keyboard-attached toolbar for the composer with attachments, formatting, topic, and counter.
class ComposerToolbar extends StatelessWidget {
  final VoidCallback onAddMedia;
  final VoidCallback? onAddGif;
  final VoidCallback? onAddMusic;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final VoidCallback onToggleChain;
  final VoidCallback? onToggleNsfw;
  final VoidCallback? onSelectTtl;
  final bool isBold;
  final bool isItalic;
  final bool allowChain;
  final bool isNsfw;
  final bool ttlOverrideActive;
  final String? ttlLabel;
  final int characterCount;
  final int maxCharacters;
  final bool isUploadingImage;
  final int remainingChars;

  const ComposerToolbar({
    super.key,
    required this.onAddMedia,
    this.onAddGif,
    this.onAddMusic,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onToggleChain,
    this.onToggleNsfw,
    this.onSelectTtl,
    this.isBold = false,
    this.isItalic = false,
    this.allowChain = true,
    this.isNsfw = false,
    this.ttlOverrideActive = false,
    this.ttlLabel,
    this.characterCount = 0,
    this.maxCharacters = 500,
    this.isUploadingImage = false,
    this.remainingChars = 500,
  });

  @override
  Widget build(BuildContext context) {
    final isOverLimit = remainingChars < 0;
    final showNumber = remainingChars <= 20;

    Color ringColor;
    if (isOverLimit) {
      ringColor = AppTheme.error;
    } else if (remainingChars <= 20) {
      ringColor = AppTheme.warning;
    } else {
      ringColor = AppTheme.brightNavy;
    }

    return Row(
      children: [
        IconButton(
          onPressed: isUploadingImage ? null : onAddMedia,
          icon: isUploadingImage
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AppTheme.navyText.withValues(alpha: 0.75),
                ),
          tooltip: 'Add media',
        ),
        if (onAddGif != null)
          IconButton(
            onPressed: onAddGif,
            icon: Icon(Icons.gif_outlined,
                color: AppTheme.navyText.withValues(alpha: 0.75)),
            tooltip: 'Add GIF',
          ),
        if (onAddMusic != null)
          IconButton(
            onPressed: onAddMusic,
            icon: Icon(Icons.music_note_outlined,
                color: AppTheme.navyText.withValues(alpha: 0.75)),
            tooltip: 'Add music',
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onToggleBold,
              icon: Icon(
                Icons.format_bold,
                color: isBold ? AppTheme.brightNavy : AppTheme.navyText.withValues(alpha: 0.5),
              ),
              tooltip: 'Bold',
            ),
            IconButton(
              onPressed: onToggleItalic,
              icon: Icon(
                Icons.format_italic,
                color: isItalic ? AppTheme.brightNavy : AppTheme.navyText.withValues(alpha: 0.5),
              ),
              tooltip: 'Italic',
            ),
            IconButton(
              onPressed: onToggleChain,
              icon: Icon(
                Icons.link,
                color: allowChain ? AppTheme.brightNavy : AppTheme.navyText.withValues(alpha: 0.4),
              ),
              tooltip: allowChain ? 'Allow chain' : 'Chain disabled',
            ),
            if (onToggleNsfw != null)
              IconButton(
                onPressed: onToggleNsfw,
                icon: Icon(
                  Icons.visibility_off_outlined,
                  color: isNsfw ? AppTheme.nsfwWarningIcon : AppTheme.navyText.withValues(alpha: 0.4),
                ),
                tooltip: isNsfw ? 'Marked as NSFW' : 'Mark as NSFW',
              ),
            if (onSelectTtl != null)
              IconButton(
                onPressed: onSelectTtl,
                icon: Icon(
                  Icons.timer_outlined,
                  color: ttlOverrideActive
                      ? AppTheme.brightNavy
                      : AppTheme.navyText.withValues(alpha: 0.5),
                ),
                tooltip: ttlLabel != null ? 'Post duration: $ttlLabel' : 'Post duration',
              ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: (characterCount / maxCharacters).clamp(0, 1),
                  strokeWidth: 2.5,
                  backgroundColor: AppTheme.queenPink.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                ),
              ),
              if (showNumber)
                Text(
                  remainingChars.clamp(-99, 99).toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: ringColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
