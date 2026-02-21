// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Converts an ISO 3166-1 alpha-2 country code to a flag emoji.
///
/// Uses Unicode Regional Indicator Symbols to create flag emojis.
/// Each letter A-Z maps to a regional indicator symbol (U+1F1E6 to U+1F1FF).
/// Combining two regional indicators creates a flag emoji.
///
/// Example: 'US' -> 🇺🇸, 'GB' -> 🇬🇧, 'CA' -> 🇨🇦
///
/// Returns null if the country code is invalid or null.
String? getCountryFlag(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) {
    return null;
  }

  final code = countryCode.toUpperCase();

  // Validate that both characters are A-Z
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
    return null;
  }

  // Convert each letter to its regional indicator symbol
  // 'A' = 65 in ASCII, Regional Indicator A = 0x1F1E6
  // Offset = 0x1F1E6 - 65 = 127397
  const int regionalIndicatorOffset = 0x1F1E6 - 65;

  final firstChar = code.codeUnitAt(0) + regionalIndicatorOffset;
  final secondChar = code.codeUnitAt(1) + regionalIndicatorOffset;

  return String.fromCharCodes([firstChar, secondChar]);
}
