// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Defines how a post should be displayed based on its context.
///
/// This enum controls visual variations without duplicating widgets.
enum PostViewMode {
  /// Standard view for feed - truncated text, constrained images
  feed,

  /// Full detail view - complete text, full images, expanded interactions
  detail,

  /// Compact view for profile lists - minimal header, reduced spacing
  compact,

  /// Thread view - reduced padding, no card elevation, smaller avatars,
  /// connecting lines align correctly, media collapsed
  thread,

  /// Sponsored/ad view - same layout as feed with "Sponsored" badge in header
  sponsored,
}
