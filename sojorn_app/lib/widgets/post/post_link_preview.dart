// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import 'post_view_mode.dart';

class PostLinkPreview extends StatelessWidget {
  final Post post;
  final PostViewMode mode;

  const PostLinkPreview({
    super.key,
    required this.post,
    this.mode = PostViewMode.feed,
  });

  double get _imageHeight {
    switch (mode) {
      case PostViewMode.feed:
      case PostViewMode.sponsored:
        return 240.0;
      case PostViewMode.detail:
        return 300.0;
      case PostViewMode.compact:
        return 160.0;
      case PostViewMode.thread:
        return 120.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!post.hasLinkPreview) return const SizedBox.shrink();

    final hasImage = post.linkPreviewImageUrl != null &&
        post.linkPreviewImageUrl!.isNotEmpty;
    final title = post.linkPreviewTitle ?? '';
    final description = post.linkPreviewDescription ?? '';
    final siteName = post.linkPreviewSiteName ?? '';

    return GestureDetector(
        onTap: () => _launchUrl(post.linkPreviewUrl!),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full-width thumbnail image
              if (hasImage)
                SizedBox(
                  width: double.infinity,
                  height: _imageHeight,
                  child: Image.network(
                    post.linkPreviewImageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: AppTheme.queenPink.withValues(alpha: 0.15),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppTheme.navyBlue.withValues(alpha: 0.08),
                        child: Center(
                          child: Icon(
                            Icons.link_rounded,
                            size: 32,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Title + description + site name
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppTheme.navyBlue.withValues(alpha: 0.04),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Site name
                    if (siteName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          siteName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppTheme.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Title
                    if (title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Description
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
