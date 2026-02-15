import 'package:flutter/material.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'media/signed_media_image.dart';
import 'reactions/reactions_display.dart';

class ChainQuoteWidget extends StatelessWidget {
  final PostPreview parent;
  final VoidCallback? onTap;

  const ChainQuoteWidget({
    super.key,
    required this.parent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final handle = parent.author?.handle ?? 'unknown';
    final displayName = parent.author?.displayName ?? 'Unknown';
    final avatarUrl = parent.author?.avatarUrl;
    final createdAt = _formatTime(parent.createdAt);
    final avatarColor = _getAvatarColor(handle);

    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppTheme.spacingSm,
        left: AppTheme.spacingMd,
        right: AppTheme.spacingMd,
      ),
      child: Material(
        color: SojornColors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            // Flat design - NO box, NO background, NO border
            // Looks exactly like a regular post
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header Row (Avatar + Names)
                Row(
                  children: [
                    // Micro-Avatar
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: avatarColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(5.5),
                              child: SignedMediaImage(
                                url: avatarUrl,
                                width: 20,
                                height: 20,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Center(
                              child: Text(
                                handle.isNotEmpty
                                    ? handle[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: SojornColors.basicWhite,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    
                    // Display Name (Bold, Official)
                    Flexible(
                      child: Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.labelMedium.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700, // Punchier
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    
                    // Handle (Muted)
                    Text(
                      '@$handle',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textTertiary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    
                    // Separator dot
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '·',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
                    
                    // Time
                    Text(
                      createdAt,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 2. Body Text - Neutral color for content
                Text(
                  parent.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyMedium.copyWith(
                    fontSize: 15,
                    height: 1.5,
                    color: AppTheme.postContentLight,
                  ),
                ),
                if (parent.reactions != null && parent.reactions!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ReactionsDisplay(
                    reactionCounts: parent.reactions!,
                    myReactions: parent.myReactions?.toSet() ?? {},
                    mode: ReactionsDisplayMode.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Consistent Avatar Coloring
  Color _getAvatarColor(String handle) {
    if (handle.isEmpty) return AppTheme.textDisabled;
    final hash = handle.hashCode;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.55).toColor();
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
