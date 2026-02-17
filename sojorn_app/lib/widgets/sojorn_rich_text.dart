import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/link_handler.dart';
import '../screens/discover/discover_screen.dart';

/// Rich text widget that automatically detects and styles URLs and mentions.
///
/// Parses text to find:
/// - URLs (http/https/www)
/// - Mentions (@handle)
///
/// Links are styled with AppTheme.royalPurple for an energetic, interactive feel.
class sojornRichText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final bool hideUrls;

  const sojornRichText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.hideUrls = false,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
      text: TextSpan(
        children: _parseText(context),
        style: style ?? AppTheme.postBody,
      ),
    );
  }

  List<InlineSpan> _parseText(BuildContext context) {
    final List<InlineSpan> spans = [];

    // Regex matches URLs (starting with http/https/www/sojorn), Mentions (@handle), and Hashtags (#tag)
    final RegExp regex = RegExp(
      r'((?:https?:\/\/|www\.|sojorn:\/\/)[^\s/$.?#].[^\s]*)' // URLs including sojorn://
      r'|(@\w+)' // Mentions
      r'|(#\w+)', // Hashtags
      caseSensitive: false,
    );

    final Iterable<Match> matches = regex.allMatches(text);

    int start = 0;

    for (final Match match in matches) {
      // Add text before the match
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }

      final String matchText = match.group(0)!;

      // Determine if it is a Mention, Hashtag, or a URL
      final bool isMention = matchText.startsWith('@');
      final bool isHashtag = matchText.startsWith('#');
      final bool issojornLink = matchText.startsWith('sojorn://');
      final bool isUrl = !isMention && !isHashtag;
      
      // Skip URLs entirely if hideUrls is true
      if (hideUrls && isUrl && !issojornLink) {
        start = match.end;
        continue;
      }
      
      final Color linkColor =
          isHashtag ? AppTheme.brightNavy : AppTheme.royalPurple;

      // For sojorn:// links, extract and display in a user-friendly format
      String displayText = matchText;
      if (issojornLink) {
        final RegExp coordRegex = RegExp(r'lat=([-\d.]+)&long=([-\d.]+)');
        final match = coordRegex.firstMatch(matchText);
        if (match != null) {
          displayText = 'View on Map (${match.group(1)}, ${match.group(2)})';
        } else {
          displayText = 'View Location';
        }
      } else if (!isMention && !isHashtag) {
        // Truncate long URLs for display: "https://apnews.com/article..."
        displayText = _truncateUrl(matchText);
      }

      spans.add(
        TextSpan(
          text: displayText,
          style: style?.copyWith(
                color: linkColor, // ACCENT color for interactions
                fontWeight: FontWeight.w600, // Bolder for "Awake" feel
                decoration:
                    isMention || isHashtag ? null : TextDecoration.underline,
                decorationColor: linkColor.withValues(alpha: 0.7),
              ) ??
              TextStyle(
                color: linkColor,
                fontWeight: FontWeight.w600,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (isMention) {
                _navigateToProfile(matchText);
              } else if (isHashtag) {
                _navigateToHashtag(matchText);
              } else {
                _navigateToUrl(matchText);
              }
            },
        ),
      );

      start = match.end;
    }

    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return spans;
  }

  /// Truncate long URLs for display: show domain + start of path + "..."
  static String _truncateUrl(String url) {
    if (url.length <= 45) return url;
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;
      final path = uri.path;
      if (path.length > 15) {
        return '${uri.scheme}://$domain${path.substring(0, 12)}...';
      }
      return '${uri.scheme}://$domain$path';
    } catch (_) {
      return '${url.substring(0, 42)}...';
    }
  }

  void _navigateToProfile(String username) {
    // Remove @ prefix if present
    final cleanUsername = username.startsWith('@') ? username.substring(1) : username;
    // Navigate to profile screen
    // This would typically use GoRouter or Navigator
    print('Navigate to profile: $cleanUsername');
  }

  void _navigateToHashtag(String hashtag) {
    // Remove # prefix if present
    final cleanHashtag = hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;
    // Navigate to search/discover with hashtag
    print('Navigate to hashtag: $cleanHashtag');
  }

  void _navigateToUrl(String url) {
    // Launch URL in browser or handle in-app
    print('Navigate to URL: $url');
  }
}
