// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/post.dart';
import '../../routes/app_routes.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../desktop/image_lightbox.dart';
import '../media/signed_media_image.dart';
import 'post_view_mode.dart';

void _showLightbox(BuildContext context, Post? post, String imageUrl) {
  final imageUrls = <String>[];
  if (post?.imageUrl?.isNotEmpty == true) imageUrls.add(post!.imageUrl!);
  if (post?.thumbnailUrl?.isNotEmpty == true &&
      !imageUrls.contains(post!.thumbnailUrl)) {
    imageUrls.add(post!.thumbnailUrl!);
  }
  if (imageUrls.isEmpty) imageUrls.add(imageUrl);

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close lightbox',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, __, ___) => ImageLightbox(
      imageUrls: imageUrls,
      initialIndex: 0,
      authorName: post?.author?.displayName,
      caption: post?.body,
      date: post?.createdAt,
      onClose: () => Navigator.of(ctx).pop(),
    ),
    transitionBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}

/// Post media widget with view-mode-aware sizing.
///
/// Logic:
/// - feed: BoxFit.cover with fixed height (300)
/// - detail: Full height (unconstrained)
/// - compact: Smaller height (200)
class PostMedia extends StatelessWidget {
  final Post? post;
  final Widget? child;
  final PostViewMode mode;
  final VoidCallback? onTap;
  /// If provided, called instead of the default `context.go()` navigation
  /// when a video thumbnail is tapped. Use this to keep the user in-context
  /// (e.g. inside a comments sheet) rather than navigating to the quips feed.
  final VoidCallback? onVideoTap;

  const PostMedia({
    super.key,
    this.post,
    this.child,
    this.mode = PostViewMode.feed,
    this.onTap,
    this.onVideoTap,
  });


  /// Get image height based on view mode
  double get _imageHeight {
    switch (mode) {
      case PostViewMode.feed:
      case PostViewMode.sponsored:
        return 450.0; // Taller for better resolution/ratio
      case PostViewMode.detail:
        return 600.0; 
      case PostViewMode.compact:
        return 200.0;
      case PostViewMode.thread:
        return 150.0;
    }
  }


  @override
  Widget build(BuildContext context) {
    // Determine which URL to display as the cover.
    // For video posts, prefer thumbnailUrl (poster frame) over imageUrl (which
    // may be the .mp4 itself) so we never feed a video file to SignedMediaImage.
    final bool isVideo = post?.hasVideoContent == true;
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    final String? displayUrl = (isVideo && post?.thumbnailUrl?.isNotEmpty == true)
        ? post!.thumbnailUrl
        : (post?.imageUrl?.isNotEmpty == true)
            ? post!.imageUrl
            : (post?.thumbnailUrl?.isNotEmpty == true)
                ? post!.thumbnailUrl
                : null;

    if (displayUrl != null) {
      // Detect GIF type by URL
      final isGif = _isGifUrl(displayUrl);
      final isRetroGif = isGif && displayUrl.contains('web.archive.org');

      // Choose image layout strategy:
      // - Video in feed: 4:5 aspect ratio (TikTok-style)
      // - Retro GIF: natural size (small 90s-era GIFs), centered
      // - Regular GIF: contained within standard height, no crop
      // - Desktop non-video: natural ratio (full width, height = natural)
      // - Everything else: constrained max-height with cover
      Widget imageContent;
      if (isVideo && mode == PostViewMode.feed) {
        imageContent = AspectRatio(
          aspectRatio: 4 / 5,
          child: _buildMediaContent(displayUrl, true),
        );
      } else if (isRetroGif) {
        // Retro GIFs: show at actual size, centered, with subtle bg
        imageContent = _buildRetroGifContent(displayUrl);
      } else if (isGif) {
        // Regular GIFs: contained (no crop), standard max height
        imageContent = _buildGifContent(displayUrl);
      } else if (!isVideo && isDesktop) {
        imageContent = _buildDesktopNaturalImage(displayUrl);
      } else {
        imageContent = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _imageHeight),
          child: _buildMediaContent(displayUrl, isVideo),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(top: AppTheme.spacingSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Container(
                width: double.infinity,
                child: GestureDetector(
                  onTap: isVideo
                      ? (onVideoTap ?? () {
                          final url = '${AppRoutes.quips}?postId=${post!.id}';
                          context.go(url);
                        })
                      : (isDesktop && !isVideo
                          ? () => _showLightbox(context, post, displayUrl)
                          : onTap),
                  child: imageContent,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (child == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: child,
      ),
    );
  }

  /// Check if a URL points to a GIF image.
  bool _isGifUrl(String url) {
    final lower = url.toLowerCase();
    // Check extension (before query params)
    final path = Uri.tryParse(lower)?.path ?? lower;
    if (path.endsWith('.gif')) return true;
    // Known GIF sources
    if (lower.contains('giphy.com') || lower.contains('tenor.com') ||
        lower.contains('gifcities.archive.org') || lower.contains('web.archive.org')) {
      return true;
    }
    return false;
  }

  /// Regular GIF: contained within standard height, no cropping.
  /// Uses BoxFit.contain so the full GIF is visible.
  Widget _buildGifContent(String displayUrl) {
    final maxH = mode == PostViewMode.feed || mode == PostViewMode.sponsored
        ? 350.0
        : mode == PostViewMode.detail
            ? 450.0
            : mode == PostViewMode.compact
                ? 180.0
                : 130.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SignedMediaImage(
        url: displayUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context) => Container(
          height: 200,
          color: AppTheme.mediaLoadingBg,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorBuilder: (context, error, stackTrace) => Container(
          height: 100,
          color: AppTheme.mediaErrorBg,
          child: const Center(
            child: Icon(Icons.broken_image, size: 32, color: SojornColors.basicWhite),
          ),
        ),
      ),
    );
  }

  /// Retro GIF (Internet Archive): display at natural size, centered.
  /// These are tiny 90s-era GIFs that look best at their actual pixel size.
  Widget _buildRetroGifContent(String displayUrl) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40, maxHeight: 300),
      alignment: Alignment.center,
      child: SignedMediaImage(
        url: displayUrl,
        fit: BoxFit.none,
        alignment: Alignment.center,
        loadingBuilder: (context) => Container(
          height: 80,
          color: AppTheme.mediaLoadingBg,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorBuilder: (context, error, stackTrace) => Container(
          height: 60,
          color: AppTheme.mediaErrorBg,
          child: const Center(
            child: Icon(Icons.broken_image, size: 24, color: SojornColors.basicWhite),
          ),
        ),
      ),
    );
  }

  /// Desktop: renders image at its natural aspect ratio (full width, height = natural).
  Widget _buildDesktopNaturalImage(String displayUrl) {
    return SignedMediaImage(
      url: displayUrl,
      fit: BoxFit.fitWidth,
      loadingBuilder: (context) => Container(
        height: 300,
        color: AppTheme.mediaLoadingBg,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorBuilder: (context, error, stackTrace) => Container(
        height: 200,
        color: AppTheme.mediaErrorBg,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, size: 48, color: SojornColors.basicWhite),
              const SizedBox(height: 8),
              Text('Error: $error',
                  style: const TextStyle(color: SojornColors.basicWhite, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent(String displayUrl, bool isVideo) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SignedMediaImage(
          url: displayUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          loadingBuilder: (context) => Container(
            color: AppTheme.mediaLoadingBg,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorBuilder: (context, error, stackTrace) => Container(
            color: AppTheme.mediaErrorBg,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, size: 48, color: SojornColors.basicWhite),
                  const SizedBox(height: 8),
                  Text('Error: $error',
                      style: const TextStyle(color: SojornColors.basicWhite, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
        // Play Button Overlay for Video
        if (isVideo)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SojornColors.overlayDark,
                shape: BoxShape.circle,
                border: Border.all(color: SojornColors.basicWhite, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow,
                color: SojornColors.basicWhite,
                size: 40,
              ),
            ),
          ),
      ],
    );
  }
}

