// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/post.dart';
import '../providers/settings_provider.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'desktop/desktop_context_menu.dart';
import 'post/post_actions.dart';
import 'post/post_body.dart';
import 'post/post_header.dart';
import 'post/post_link_preview.dart';
import 'post/post_media.dart';
import 'post/post_menu.dart';
import 'post/post_view_mode.dart';
import 'chain_quote_widget.dart';
import '../routes/app_routes.dart';
import 'modals/sanctuary_sheet.dart';


/// Unified Post Card - Single Source of Truth for post display.
///
/// This master widget assembles all post sub-components and serves as the
/// single entry point for displaying posts regardless of context.
///
/// ## Usage
/// ```dart
/// // Feed view (truncated)
/// sojornPostCard(post: post, mode: PostViewMode.feed)
///
/// // Detail view (full content)
/// sojornPostCard(post: post, mode: PostViewMode.detail)
///
/// // Profile list (compact)
/// sojornPostCard(post: post, mode: PostViewMode.compact)
/// ```
///
/// ## Architecture
/// - Single source of truth for layout margins, padding, and elevation
/// - Pure stateless composition of sub-components
/// - ViewMode-driven visual variations without code duplication
class sojornPostCard extends ConsumerStatefulWidget {
  final Post post;
  final PostViewMode mode;
  final VoidCallback? onTap;
  final VoidCallback? onChain;
  final VoidCallback? onPostChanged;
  final VoidCallback? onChainParentTap;
  final bool isThreadView;
  final bool showChainContext;

  const sojornPostCard({
    super.key,
    required this.post,
    this.mode = PostViewMode.feed,
    this.onTap,
    this.onChain,
    this.onPostChanged,
    this.onChainParentTap,
    this.isThreadView = false,
    this.showChainContext = true,
  });

  @override
  ConsumerState<sojornPostCard> createState() => _sojornPostCardState();
}

class _sojornPostCardState extends ConsumerState<sojornPostCard> {
  bool _nsfwRevealed = false;
  bool _hovering = false;

  Post get post => widget.post;
  PostViewMode get mode => widget.mode;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onChain => widget.onChain;
  VoidCallback? get onPostChanged => widget.onPostChanged;
  VoidCallback? get onChainParentTap => widget.onChainParentTap;
  bool get isThreadView => widget.isThreadView;
  bool get showChainContext => widget.showChainContext;

  /// Get spacing values based on view mode
  EdgeInsets get _padding {
    switch (mode) {
      case PostViewMode.feed:
      case PostViewMode.sponsored:
        return const EdgeInsets.all(AppTheme.spacingMd);
      case PostViewMode.detail:
        return const EdgeInsets.all(AppTheme.spacingLg);
      case PostViewMode.compact:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        );
      case PostViewMode.thread:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSm,
          vertical: AppTheme.spacingXs,
        );
    }
  }

  /// Whether NSFW post should be completely hidden (not shown at all)
  bool get _shouldHideNsfw {
    if (!post.isNsfw) return false;
    final settings = ref.read(settingsProvider);
    return !(settings.user?.nsfwEnabled ?? false);
  }

  /// Whether to show NSFW blur overlay — only applies when user HAS opted in
  bool get _shouldBlurNsfw {
    if (!post.isNsfw || _nsfwRevealed) return false;
    if (_shouldHideNsfw) return false; // Will be hidden entirely, no blur needed
    final settings = ref.read(settingsProvider);
    // If opted in, respect the blur toggle
    return settings.user?.nsfwBlurEnabled ?? true;
  }

  double get _avatarSize {
    switch (mode) {
      case PostViewMode.feed:
      case PostViewMode.sponsored:
        return 48.0;
      case PostViewMode.detail:
        return 50.0;
      case PostViewMode.compact:
        return 28.0;
      case PostViewMode.thread:
        return 24.0;
    }
  }

  bool get _isSponsored => mode == PostViewMode.sponsored;

  bool get _isThread => mode == PostViewMode.thread;
  bool get _effectiveThreadView => isThreadView || _isThread;

  @override
  Widget build(BuildContext context) {
    // Completely hide NSFW posts when user hasn't enabled NSFW
    if (_shouldHideNsfw) return const SizedBox.shrink();

    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      child: MouseRegion(
      onEnter: isDesktop ? (_) => setState(() => _hovering = true) : null,
      onExit: isDesktop ? (_) => setState(() => _hovering = false) : null,
      child: Material(
      color: SojornColors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: EdgeInsets.only(bottom: _isThread ? 4 : 16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(_isThread ? 12 : 20),
          border: _isThread
              ? Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06), width: 1)
              : Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1), width: 1),
          boxShadow: _isThread
              ? []
              : [
                  BoxShadow(
                    color: AppTheme.brightNavy.withValues(alpha: _hovering && isDesktop ? 0.18 : 0.12),
                    blurRadius: _hovering && isDesktop ? 28 : 20,
                    offset: Offset(0, _hovering && isDesktop ? 10 : 6),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_isThread ? 12 : 20),
          child: Container(
            padding: _padding.copyWith(
              left: 0,
              right: 0,
              bottom: post.hasLinkPreview ? 0 : _padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Internal horizontal padding for text/actions
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _padding.left),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chain Context (The Quote Box) - only show in thread view
                      if (_effectiveThreadView && showChainContext && post.chainParent != null) ...[
                        ChainQuoteWidget(
                          parent: post.chainParent!,
                          onTap: onChainParentTap,
                        ),
                        const SizedBox(height: AppTheme.spacingSm),
                      ],

                      // Feed chain hint — subtle "replying to" for non-thread views
                      if (!_effectiveThreadView && post.chainParent != null) ...[
                        GestureDetector(
                          onTap: onTap,
                          child: _ChainReplyHint(parent: post.chainParent!),
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Main Post Content
                      const SizedBox(height: 4),
                      // Header row with menu - only header is clickable for profile
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                final handle = post.author?.handle ?? 'unknown';
                                if (handle != 'unknown' && handle.trim().isNotEmpty) {
                                  AppRoutes.navigateToProfile(context, handle);
                                }
                              },
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                child: PostHeader(
                                  post: post,
                                  avatarSize: _avatarSize,
                                  mode: mode,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTapDown: (details) => SanctuarySheet.showQuick(
                              context,
                              post,
                              details.globalPosition,
                            ),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.ksuPurple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text("!", style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.royalPurple.withValues(alpha: 0.7),
                              )),
                            ),
                          ),
                          PostMenu(
                            post: post,
                            onPostDeleted: onPostChanged,
                          ),
                        ],
                      ),
                      if (!post.hasLinkPreview || post.body.trim().isNotEmpty)
                        const SizedBox(height: 6),

                      // Sponsored badge
                      if (_isSponsored) ...[                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.sponsoredBadgeBg,
                            borderRadius: BorderRadius.circular(SojornRadii.md),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.campaign, size: 12, color: AppTheme.sponsoredBadgeText),
                              const SizedBox(width: 4),
                              Text(
                                'SPONSORED${post.advertiserName != null ? ' BY ${post.advertiserName!.toUpperCase()}' : ''}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: AppTheme.sponsoredBadgeText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Group context chip
                      if (post.groupName != null && post.groupName!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.brightNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 11, color: AppTheme.brightNavy.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(
                                'Posted in ${post.groupName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.brightNavy.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Beacon alert badge (for geo-alert posts)
                      if (post.isBeaconPost && post.beaconType != null && post.beaconType!.isGeoAlert) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: post.beaconType!.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: post.beaconType!.color.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(post.beaconType!.icon, size: 14, color: post.beaconType!.color),
                              const SizedBox(width: 5),
                              Text(
                                post.beaconType!.displayName.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: post.beaconType!.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Body text - clickable for post detail with full background coverage
                      // Skip body entirely for link-preview-only posts (no real text)
                      if (post.hasLinkPreview && post.body.trim().isEmpty) ...[
                        // No body to show — link preview handles display
                      ] else if (_shouldBlurNsfw) ...[
                        // NSFW blurred body
                        ClipRect(
                          child: Stack(
                            children: [
                              ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: PostBody(
                                    text: post.body,
                                    bodyFormat: post.bodyFormat,
                                    backgroundId: post.backgroundId,
                                    mode: mode,
                                    hideUrls: post.hasLinkPreview,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: PostBody(
                              text: post.body,
                              bodyFormat: post.bodyFormat,
                              backgroundId: post.backgroundId,
                              mode: mode,
                              hideUrls: post.hasLinkPreview,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Link preview card — outside horizontal padding for edge-to-edge display
                if (post.hasLinkPreview) ...[
                  PostLinkPreview(
                    post: post,
                    mode: mode,
                  ),
                ],

                // Media (if available) - clickable for post detail (or quip player if video)
                if ((post.imageUrl != null && post.imageUrl!.isNotEmpty) || 
                    (post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty) ||
                    (post.videoUrl != null && post.videoUrl!.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  if (_shouldBlurNsfw) ...[
                    ClipRect(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: PostMedia(
                          post: post,
                          mode: mode,
                          onTap: null,
                        ),
                      ),
                    ),
                  ] else ...[
                    PostMedia(
                      post: post,
                      mode: mode,
                      onTap: onTap,
                    ),
                  ],
                ],


                // NSFW warning banner with tap-to-reveal
                if (_shouldBlurNsfw) ...[
                  GestureDetector(
                    onTap: () => setState(() => _nsfwRevealed = true),
                    child: Container(
                      width: double.infinity,
                      margin: EdgeInsets.symmetric(horizontal: _padding.left, vertical: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.nsfwWarningBg,
                        borderRadius: BorderRadius.circular(SojornRadii.lg),
                        border: Border.all(color: AppTheme.nsfwWarningBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.visibility_off, size: 16, color: AppTheme.nsfwWarningIcon),
                              const SizedBox(width: 6),
                              Text(
                                'Sensitive Content',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.nsfwWarningText,
                                ),
                              ),
                            ],
                          ),
                          if (post.nsfwReason != null && post.nsfwReason!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              post.nsfwReason!,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.nsfwWarningSubText,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'Tap to reveal',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.nsfwRevealText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],




                // Actions section - with padding
                const SizedBox(height: 10),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _padding.left),
                  child: PostActions(
                    post: post,
                    onChain: onChain,
                    onPostChanged: onPostChanged,
                    isThreadView: _effectiveThreadView,
                    showReactions: _effectiveThreadView,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    ),
    ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    DesktopContextMenu.show(
      context,
      position: position,
      items: [
        ContextMenuItem(
          icon: Icons.link,
          label: 'Copy link',
          onTap: () {
            // Copy post link to clipboard
          },
        ),
        ContextMenuItem(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () {
            // Trigger share
          },
        ),
        ContextMenuItem(
          icon: Icons.bookmark_border,
          label: 'Save',
          onTap: () {
            // Trigger save
          },
        ),
        ContextMenuItem(
          icon: Icons.flag_outlined,
          label: 'Report',
          onTap: () {
            // Open report flow
          },
          isDestructive: true,
        ),
      ],
    );
  }
}

/// Subtle single-line "replying to" hint shown on feed cards that are chains.
/// Uses a thin left accent bar and muted text to stay unobtrusive.
class _ChainReplyHint extends StatelessWidget {
  final PostPreview parent;

  const _ChainReplyHint({required this.parent});

  @override
  Widget build(BuildContext context) {
    final handle = parent.author?.handle ?? 'someone';
    final snippet = parent.body
        .replaceAll('\n', ' ')
        .trim();
    final truncated = snippet.length > 60
        ? '${snippet.substring(0, 60)}…'
        : snippet;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.35),
            width: 2.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply_rounded,
            size: 13,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            '@$handle',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
            ),
          ),
          if (truncated.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                truncated,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
