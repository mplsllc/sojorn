// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Filter options for the home feed
enum FeedFilter {
  all('All Posts', null),
  posts('Posts Only', 'post'),
  quips('Quips Only', 'quip'),
  chains('Chains Only', 'chain'),
  beacons('Beacons Only', 'beacon');

  final String label;
  final String? typeValue;

  const FeedFilter(this.label, this.typeValue);
}
