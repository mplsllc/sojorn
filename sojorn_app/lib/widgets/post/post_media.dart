import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/post.dart';
import '../../routes/app_routes.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../media/signed_media_image.dart';
import 'post_view_mode.dart';

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
    final String? displayUrl = (isVideo && post?.thumbnailUrl?.isNotEmpty == true)
        ? post!.thumbnailUrl
        : (post?.imageUrl?.isNotEmpty == true)
            ? post!.imageUrl
            : (post?.thumbnailUrl?.isNotEmpty == true)
                ? post!.thumbnailUrl
                : null;

    if (displayUrl != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTheme.spacingSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Container(
                width: double.infinity,
                // For videos in feed mode, use a more vertical 4:5 aspect ratio
                // For other modes or non-videos, use the constrained height logic
                child: InkWell(
                  onTap: isVideo
                      ? (onVideoTap ?? () {
                          final url = '${AppRoutes.quips}?postId=${post!.id}';
                          context.go(url);
                        })
                      : onTap,


                  child: (isVideo && mode == PostViewMode.feed)
                      ? AspectRatio(
                          aspectRatio: 4 / 5,
                          child: _buildMediaContent(displayUrl, true),
                        )
                      : ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: _imageHeight),
                          child: _buildMediaContent(displayUrl, isVideo),
                        ),
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

