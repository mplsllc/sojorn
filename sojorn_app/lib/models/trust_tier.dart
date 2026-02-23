// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';

/// Harmony Score trust tiers — inspired (clean-room) by Discourse's TL0-TL4 system.
///
/// Thresholds (Harmony Score 0-100):
///   new_user:    0–19   🌱 Seedling  — basic read/post access
///   sprout:     20–39   🪴 Sprout    — can vouch beacons, full reactions
///   trusted:    40–64   🌿 Trusted   — can create events
///   elder:      65–84   🌾 Elder     — can create groups, pin posts
///   established: 85–100 🌳 Established — full privileges, weighted vouches
enum TrustTier {
  // ignore: constant_identifier_names
  new_user('new'),
  sprout('sprout'),
  trusted('trusted'),
  elder('elder'),
  established('established');

  final String value;
  const TrustTier(this.value);

  static TrustTier fromString(String value) {
    return TrustTier.values.firstWhere(
      (tier) => tier.value == value,
      orElse: () => TrustTier.new_user,
    );
  }

  // ── Display ──────────────────────────────────────────────────────────────

  String get displayName {
    switch (this) {
      case TrustTier.new_user:    return 'Seedling';
      case TrustTier.sprout:      return 'Sprout';
      case TrustTier.trusted:     return 'Trusted';
      case TrustTier.elder:       return 'Elder';
      case TrustTier.established: return 'Established';
    }
  }

  String get emoji {
    switch (this) {
      case TrustTier.new_user:    return '🌱';
      case TrustTier.sprout:      return '🪴';
      case TrustTier.trusted:     return '🌿';
      case TrustTier.elder:       return '🌾';
      case TrustTier.established: return '🌳';
    }
  }

  Color get color {
    switch (this) {
      case TrustTier.new_user:    return const Color(0xFF9E9E9E); // grey
      case TrustTier.sprout:      return const Color(0xFF66BB6A); // light green
      case TrustTier.trusted:     return const Color(0xFF26A69A); // teal
      case TrustTier.elder:       return const Color(0xFF5C6BC0); // indigo
      case TrustTier.established: return const Color(0xFF8D6E63); // warm brown
    }
  }

  // ── Posting limits ───────────────────────────────────────────────────────

  int get postLimit {
    switch (this) {
      case TrustTier.new_user:    return 2;
      case TrustTier.sprout:      return 5;
      case TrustTier.trusted:     return 15;
      case TrustTier.elder:       return 25;
      case TrustTier.established: return 50;
    }
  }

  // ── Feature gates ────────────────────────────────────────────────────────

  /// Can confirm/vouch that a beacon is accurate (sprout+).
  bool get canVouchBeacons => index >= TrustTier.sprout.index;

  /// Can create events within groups they belong to (trusted+).
  bool get canCreateEvents => index >= TrustTier.trusted.index;

  /// Can create new groups (elder+).
  bool get canCreateGroups => index >= TrustTier.elder.index;

  /// Can pin posts in groups/neighborhoods where they are admin (elder+).
  bool get canPinPosts => index >= TrustTier.elder.index;

  /// Beacon vouch weight — established users count as 2 confirms.
  int get beaconVouchWeight => this == TrustTier.established ? 2 : 1;

  /// Minimum score to reach this tier (for progress display).
  int get minScore {
    switch (this) {
      case TrustTier.new_user:    return 0;
      case TrustTier.sprout:      return 20;
      case TrustTier.trusted:     return 40;
      case TrustTier.elder:       return 65;
      case TrustTier.established: return 85;
    }
  }

  /// Maximum score for this tier (for progress bar).
  int get maxScore {
    switch (this) {
      case TrustTier.new_user:    return 19;
      case TrustTier.sprout:      return 39;
      case TrustTier.trusted:     return 64;
      case TrustTier.elder:       return 84;
      case TrustTier.established: return 100;
    }
  }

  /// Next tier, or null if already at the top.
  TrustTier? get next {
    final idx = TrustTier.values.indexOf(this);
    if (idx >= TrustTier.values.length - 1) return null;
    return TrustTier.values[idx + 1];
  }
}
