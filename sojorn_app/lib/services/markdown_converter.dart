// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Service for converting between Quill Delta format and Markdown
///
/// Handles bidirectional conversion:
/// - Quill Delta → Markdown (for storage)
/// - Markdown → Quill Delta (for editing existing posts)
class MarkdownConverter {
  /// Convert Quill document to Markdown string
  String toMarkdown(quill.Document document) {
    final buffer = StringBuffer();
    final delta = document.toDelta();

    for (final op in delta.toList()) {
      if (op.data is! String) continue;

      String text = op.data as String;
      final attrs = op.attributes;

      if (attrs == null) {
        buffer.write(text);
        continue;
      }

      // Handle block-level formatting
      if (attrs.containsKey('header')) {
        final level = attrs['header'] as int;
        final hashes = '#' * level;
        buffer.write('$hashes $text');
        continue;
      }

      if (attrs.containsKey('blockquote')) {
        buffer.write('> $text');
        continue;
      }

      if (attrs.containsKey('code-block')) {
        buffer.write('```\n$text```\n');
        continue;
      }

      if (attrs.containsKey('list')) {
        final listType = attrs['list'];
        if (listType == 'bullet') {
          buffer.write('- $text');
        } else if (listType == 'ordered') {
          buffer.write('1. $text');
        }
        continue;
      }

      // Handle inline formatting
      String formattedText = text;

      if (attrs.containsKey('bold')) {
        formattedText = '**$formattedText**';
      }

      if (attrs.containsKey('italic')) {
        formattedText = '_${formattedText}_';
      }

      if (attrs.containsKey('underline')) {
        // Markdown doesn't have native underline, use HTML
        formattedText = '<u>$formattedText</u>';
      }

      if (attrs.containsKey('strike')) {
        formattedText = '~~$formattedText~~';
      }

      if (attrs.containsKey('code')) {
        formattedText = '`$formattedText`';
      }

      if (attrs.containsKey('link')) {
        final url = attrs['link'];
        formattedText = '[$formattedText]($url)';
      }

      buffer.write(formattedText);
    }

    return buffer.toString();
  }

  /// Convert Markdown string to Quill document
  ///
  /// Note: This is a simplified implementation. For production use,
  /// consider using a proper Markdown parser or the quill_markdown package.
  quill.Document fromMarkdown(String markdown) {
    // For now, return a simple document with the markdown as plain text
    // This will be enhanced in future iterations
    return quill.Document()..insert(0, markdown);
  }

  /// Get character count of rendered text (without Markdown syntax)
  int getRenderedCharCount(quill.Document document) {
    final markdown = toMarkdown(document);
    final rendered = _stripMarkdownSyntax(markdown);
    return rendered.length;
  }

  /// Strip Markdown syntax to get plain text character count
  String _stripMarkdownSyntax(String markdown) {
    String text = markdown;

    // Remove headers
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // Remove bold
    text = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');

    // Remove italic
    text = text.replaceAll(RegExp(r'_(.+?)_'), r'$1');

    // Remove strikethrough
    text = text.replaceAll(RegExp(r'~~(.+?)~~'), r'$1');

    // Remove inline code
    text = text.replaceAll(RegExp(r'`(.+?)`'), r'$1');

    // Remove links but keep text
    text = text.replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1');

    // Remove blockquotes
    text = text.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

    // Remove list markers
    text = text.replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');

    // Remove HTML tags (for underline)
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // Remove code block markers
    text = text.replaceAll('```', '');

    return text;
  }
}
