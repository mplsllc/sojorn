// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/foundation.dart';

/// On-device content moderation that runs BEFORE encryption.
/// No network calls — pure local pattern matching + keyword detection.
/// This is Layer 1: fast, private, zero-latency content gate.
class ContentGuardService {
  static final ContentGuardService _instance = ContentGuardService._();
  static ContentGuardService get instance => _instance;
  ContentGuardService._();

  /// Check content before sending. Returns null if clean, or a reason string if blocked.
  String? check(String text, {String? imageUrl}) {
    if (text.isEmpty) return null;

    final lower = text.toLowerCase().trim();

    // 1. Slur / hate speech blocklist
    final slurMatch = _checkBlocklist(lower, _slurPatterns);
    if (slurMatch != null) return 'Content contains prohibited language: $slurMatch';

    // 2. Violent threat patterns
    final threatMatch = _checkPatterns(lower, _threatPatterns);
    if (threatMatch != null) return 'Content contains threatening language';

    // 3. CSAM / exploitation indicators
    final csamMatch = _checkBlocklist(lower, _exploitationPatterns);
    if (csamMatch != null) return 'Content violates safety policies';

    // 4. Spam patterns (excessive caps, repeated chars, link spam)
    final spamReason = _checkSpam(lower, text);
    if (spamReason != null) return spamReason;

    return null; // Clean
  }

  /// Quick check — returns true if content is allowed
  bool isAllowed(String text, {String? imageUrl}) => check(text, imageUrl: imageUrl) == null;

  // ─── Pattern Matching Engine ────────────────────────────────────────

  String? _checkBlocklist(String text, List<String> patterns) {
    for (final pattern in patterns) {
      // Word boundary matching: ensure we match whole words, not substrings
      final regex = RegExp(r'\b' + RegExp.escape(pattern) + r'\b', caseSensitive: false);
      if (regex.hasMatch(text)) return pattern;
    }
    return null;
  }

  String? _checkPatterns(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) return pattern.pattern;
    }
    return null;
  }

  String? _checkSpam(String lower, String original) {
    // Excessive ALL CAPS (>70% uppercase in messages longer than 20 chars)
    if (original.length > 20) {
      final upperCount = original.runes.where((r) => String.fromCharCode(r) == String.fromCharCode(r).toUpperCase() && String.fromCharCode(r) != String.fromCharCode(r).toLowerCase()).length;
      if (upperCount / original.length > 0.7) return 'Excessive capitalization';
    }

    // Repeated character spam (e.g., "aaaaaaaaaa")
    final repeatedChar = RegExp(r'(.)\1{9,}');
    if (repeatedChar.hasMatch(lower)) return 'Spam detected';

    return null;
  }

  // ─── Blocklists ─────────────────────────────────────────────────────
  // These are compiled at app start and checked per-message.
  // Admin can push updates via config endpoint in the future.

  /// Racial slurs and hate speech terms
  static final List<String> _slurPatterns = [
    // Racial slurs
    'nigger', 'nigga', 'kike', 'spic', 'wetback', 'chink', 'gook',
    'raghead', 'towelhead', 'beaner', 'coon', 'darkie',
    // Anti-LGBTQ slurs
    'faggot', 'fag', 'dyke', 'tranny',
    // Disability slurs
    'retard', 'retarded',
  ];

  /// Violent threat patterns (regex)
  static final List<RegExp> _threatPatterns = [
    RegExp(r'\b(i will|im going to|gonna)\s+(kill|murder|shoot|stab|hurt)\s+(you|them|him|her|everyone)\b', caseSensitive: false),
    RegExp(r'\b(bomb|shoot up|blow up)\s+(the|a|this)\s+(school|church|mosque|synagogue|building)\b', caseSensitive: false),
    RegExp(r'\b(death|kill)\s+threat\b', caseSensitive: false),
  ];

  /// CSAM and exploitation indicators
  static final List<String> _exploitationPatterns = [
    'child porn', 'cp links', 'underage', 'jailbait',
  ];
}

/// Thrown when local content moderation blocks a message before encryption.
class ContentBlockedException implements Exception {
  final String reason;
  const ContentBlockedException(this.reason);

  @override
  String toString() => 'ContentBlockedException: $reason';
}
