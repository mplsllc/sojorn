import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import '../../utils/external_link_controller.dart';
import '../../theme/app_theme.dart';
import '../../screens/discover/discover_screen.dart';

/// Simple widget to limit max lines for any child
class LimitedMaxLinesBox extends StatelessWidget {
  final int maxLines;
  final Widget child;

  const LimitedMaxLinesBox({
    super.key,
    required this.maxLines,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _calculateHeightForLines(maxLines),
          ),
          child: child,
        ),
      ),
    );
  }

  double _calculateHeightForLines(int lines) {
    // Approximate line height based on baseStyle font size (17px * 1.5 = ~25.5px per line)
    return lines * 28.0;
  }
}

/// Widget for rendering Markdown-formatted post body
///
/// Displays rich text with:
/// - Bold, italic, strikethrough
/// - Headings (H1, H2, H3)
/// - Lists (ordered and unordered)
/// - Links (clickable)
/// - Code blocks and inline code
/// - Blockquotes
class MarkdownPostBody extends StatelessWidget {
  final String markdown;
  final TextStyle? baseStyle;
  final int? maxLines;

  const MarkdownPostBody({
    super.key,
    required this.markdown,
    this.baseStyle,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap with LimitedMaxLinesBox if maxLines is specified
    if (maxLines != null) {
      return LimitedMaxLinesBox(
        maxLines: maxLines!,
        child: _MarkdownBodyContent(
          markdown: markdown,
          baseStyle: baseStyle,
        ),
      );
    }

    return _MarkdownBodyContent(
      markdown: markdown,
      baseStyle: baseStyle,
    );
  }
}

class _MarkdownBodyContent extends StatelessWidget {
  final String markdown;
  final TextStyle? baseStyle;

  const _MarkdownBodyContent({
    required this.markdown,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: markdown,
      inlineSyntaxes: [HashtagSyntax()],
      builders: {
        'hashtag': HashtagBuilder(),
      },
      styleSheet: MarkdownStyleSheet(
        // Paragraph style (default text)
        p: baseStyle ?? AppTheme.postBody,

        // Bold text
        strong: (baseStyle ?? AppTheme.postBody).copyWith(
          fontWeight: FontWeight.bold,
        ),

        // Italic text
        em: (baseStyle ?? AppTheme.postBody).copyWith(
          fontStyle: FontStyle.italic,
        ),

        // Strikethrough
        del: (baseStyle ?? AppTheme.postBody).copyWith(
          decoration: TextDecoration.lineThrough,
        ),

        // Headings
        h1: AppTheme.headlineMedium.copyWith(fontSize: 28),
        h2: AppTheme.headlineMedium,
        h3: AppTheme.headlineSmall,

        // Code blocks
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          backgroundColor: AppTheme.queenPink.withValues(alpha: 0.1),
          color: AppTheme.egyptianBlue,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppTheme.queenPink.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),

        // Blockquotes
        blockquote: (baseStyle ?? AppTheme.postBody).copyWith(
          color: AppTheme.navyText.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppTheme.royalPurple,
              width: 4,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),

        // Links
        a: TextStyle(
          color: AppTheme.brightNavy,
          decoration: TextDecoration.underline,
        ),

        // Lists
        listBullet: (baseStyle ?? AppTheme.postBody).copyWith(
          color: AppTheme.egyptianBlue,
        ),
      ),
      onTapLink: (text, href, title) async {
        if (href != null && href.startsWith('hashtag://')) {
          final tag = href.replaceFirst('hashtag://', '');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DiscoverScreen(initialQuery: '#$tag'),
            ),
          );
          return;
        }
        if (href != null) {
          // Use ExternalLinkController for safety checks
          await ExternalLinkController.handleUrl(context, href);
        }
      },
    );
  }
}

/// Custom inline syntax to detect hashtags (#word) inside markdown text.
class HashtagSyntax extends md.InlineSyntax {
  HashtagSyntax() : super(r'(^|[\s])(#\w+)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final leading = match[1] ?? '';
    final tag = match[2] ?? '';

    if (leading.isNotEmpty) {
      parser.addNode(md.Text(leading));
    }

    parser.addNode(md.Element.text('hashtag', tag));
    return true;
  }
}

/// Renders hashtags as clickable text that routes to DiscoverScreen.
class HashtagBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tagText = element.textContent.trim();
    if (tagText.isEmpty) return null;

    final displayText = tagText.startsWith('#') ? tagText : '#$tagText';
    final textStyle =
        (preferredStyle ?? parentStyle ?? AppTheme.postBody).copyWith(
      color: AppTheme.brightNavy,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.none,
    );

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DiscoverScreen(initialQuery: displayText),
          ),
        );
      },
      child: Text(displayText, style: textStyle),
    );
  }
}
