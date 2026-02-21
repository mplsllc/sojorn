// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Client-side content filter for Sojorn.
/// Layer 0: Catches obvious slurs BEFORE sending to server.
/// This prevents the post from ever leaving the device.
class ContentFilter {
  ContentFilter._();
  static final instance = ContentFilter._();

  /// Check text for hard-blocked content.
  /// Returns null if clean, or a user-friendly message if blocked.
  String? check(String text) {
    if (text.isEmpty) return null;

    final normalized = _normalize(text);

    for (final pattern in _hardBlockPatterns) {
      if (pattern.hasMatch(normalized)) {
        return "We don't allow that kind of language on Sojorn. Please revise your post.";
      }
    }

    return null;
  }

  /// Normalize text to catch common evasion tactics.
  String _normalize(String text) {
    var result = text.toLowerCase();

    // Remove zero-width characters
    result = result.replaceAll('\u200b', '');
    result = result.replaceAll('\u200c', '');
    result = result.replaceAll('\u200d', '');
    result = result.replaceAll('\ufeff', '');

    // Remove common separator characters used to evade filters
    result = result.replaceAll(RegExp(r'[.\-_*|]'), '');

    return result;
  }

  // Hard-blocked patterns — these match slurs and direct threats.
  // Mirrors the server-side patterns in content_filter.go.
  static final List<RegExp> _hardBlockPatterns = [
    // N-word and variants (no \b — catches concatenated slurs like 'niggerfag')
    RegExp(r'n[i1!|l][gq9][gq9]+[e3a@]?[r0d]?s?', caseSensitive: false),
    RegExp(r'n[i1!|l][gq9]+[aA@]', caseSensitive: false),
    RegExp(r'n\s*[i1!]\s*[gq9]\s*[gq9]\s*[e3a]?\s*[r0]?', caseSensitive: false),

    // F-word (homophobic slur) and variants
    RegExp(r'f[a@4][gq9][gq9]?[o0]?[t7]?s?', caseSensitive: false),
    RegExp(r'f\s*[a@4]\s*[gq9]\s*[gq9]?\s*[o0]?\s*[t7]?', caseSensitive: false),

    // K-word (anti-Jewish slur)
    RegExp(r'k[i1][k]+[e3]?s?', caseSensitive: false),

    // C-word (racial slur against Asian people)
    RegExp(r'ch[i1]n[k]+s?', caseSensitive: false),

    // S-word (anti-Hispanic slur)
    RegExp(r'sp[i1][ck]+s?', caseSensitive: false),

    // W-word (racial slur)
    RegExp(r'w[e3][t7]b[a@]ck+s?', caseSensitive: false),

    // R-word (ableist slur)
    RegExp(r'r[e3]t[a@]rd+s?', caseSensitive: false),

    // T-word (transphobic slur)
    RegExp(r'tr[a@4]nn[yie]+s?', caseSensitive: false),

    // Direct death/violence threats (keep \b for sentence structure)
    RegExp(r"(i('?m| am) go(ing|nna)|i('?ll| will)) (to )?(kill|murder|shoot|stab|rape)", caseSensitive: false),
    RegExp(r'(kill|murder|shoot|stab|rape) (you|them|him|her|all)', caseSensitive: false),
  ];
}
