// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../sojorn_rich_text.dart';
import 'markdown_post_body.dart';
import 'post_view_mode.dart';

/// Post body text with reading-optimized typography.
///
/// Design Intent:
/// - Post body is the hero - clear visual hierarchy
/// - Line height adjusts based on content length
/// - Typography communicates emotional tone, not just content
/// - Supports both plain text and Markdown formatting
/// - ViewMode controls truncation behavior
class PostBody extends StatelessWidget {
  final String text;
  final String? bodyFormat; // 'plain' or 'markdown'
  final String? backgroundId; // theme id
  final bool isReflective;
  final PostViewMode mode;
  final bool hideUrls;

  const PostBody({
    super.key,
    required this.text,
    this.bodyFormat,
    this.backgroundId,
    this.isReflective = false,
    this.mode = PostViewMode.feed,
    this.hideUrls = false,
  });

  /// Check if text contains Markdown syntax
  bool _hasMarkdownSyntax(String text) {
    // Check for common Markdown patterns
    return text.contains('**') || // Bold
        text.contains('_') || // Italic
        text.startsWith('#') || // Headers
        text.contains('[') && text.contains('](') || // Links
        text.contains('```') || // Code blocks
        text.contains('- ') || // Lists
        text.contains('> '); // Blockquotes
  }

  /// Determine max lines based on view mode
  int? get _maxLines {
    switch (mode) {
      case PostViewMode.feed:
      case PostViewMode.sponsored:
        return 12; // Truncate in feed
      case PostViewMode.detail:
        return null; // Show all in detail
      case PostViewMode.compact:
        return 6; // More compact in profile lists
      case PostViewMode.thread:
        return 4; // Very compact in thread replies
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Trim trailing whitespace
    // 2. Collapse 3+ newlines into 2 (max one empty line)
    final cleanedText = text
        .replaceAll(RegExp(r'\s+$'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
        
    final isMarkdown = bodyFormat == 'markdown' || _hasMarkdownSyntax(cleanedText);

    final TextStyle style;
    if (isReflective) {
      style = AppTheme.postBodyReflective;
    } else {
      final estimatedLines = (cleanedText.length / 45).ceil();
      if (estimatedLines <= 3) {
        style = AppTheme.postBodyShort;
      } else if (estimatedLines >= 10) {
        style = AppTheme.postBodyLong;
      } else {
        style = AppTheme.postBody;
      }
    }

    final int? maxLines = _maxLines;
    
    // If we have a maxLines limit, we want to show "Expand post..." if it's exceeded
    if (maxLines != null) {
      // Approximate line height (fontSize * 1.5 height + a bit of buffer)
      final double lineHeight = (style.fontSize ?? 17.0) * 1.6;
      final double maxHeight = maxLines * lineHeight;

      return LayoutBuilder(
        builder: (context, constraints) {
          final content = isMarkdown
              ? MarkdownPostBody(
                  markdown: text,
                  baseStyle: style,
                  // We don't pass maxLines to MarkdownPostBody here because we handle clipping ourselves 
                  // to show the "Expand" button at the bottom correctly
                )
              : sojornRichText(
                  text: cleanedText,
                  style: style,
                  hideUrls: hideUrls,
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LimitedBox(
                maxHeight: maxHeight,
                child: content,
              ),
              _ExpandIndicator(maxLines: maxLines, text: text),
            ],
          );
        },
      );
    }

    if (isMarkdown) {
      return MarkdownPostBody(
        markdown: text,
        baseStyle: style,
        maxLines: maxLines,
      );
    }

    return sojornRichText(
      text: cleanedText,
      style: style,
      maxLines: maxLines,
      hideUrls: hideUrls,
    );
  }
}

class _ExpandIndicator extends StatelessWidget {
  final int maxLines;
  final String text;

  const _ExpandIndicator({required this.maxLines, required this.text});

  @override
  Widget build(BuildContext context) {
    // Basic heuristic: check if line count is high or text is long
    final lineCount = '\n'.allMatches(text).length + 1;
    final isLong = text.length > 400 || lineCount > maxLines;

    if (!isLong) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(
            'Expand post...',
            style: TextStyle(
              color: AppTheme.brightNavy,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.brightNavy),
        ],
      ),
    );
  }
}
