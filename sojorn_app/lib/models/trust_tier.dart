// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Trust tier enum matching backend schema
enum TrustTier {
  // ignore: constant_identifier_names
  new_user('new'),
  trusted('trusted'),
  established('established');

  final String value;
  const TrustTier(this.value);

  static TrustTier fromString(String value) {
    return TrustTier.values.firstWhere(
      (tier) => tier.value == value,
      orElse: () => TrustTier.new_user,
    );
  }

  String get displayName {
    switch (this) {
      case TrustTier.new_user:
        return 'New';
      case TrustTier.trusted:
        return 'Trusted';
      case TrustTier.established:
        return 'Established';
    }
  }

  int get postLimit {
    switch (this) {
      case TrustTier.new_user:
        return 3;
      case TrustTier.trusted:
        return 10;
      case TrustTier.established:
        return 25;
    }
  }
}
