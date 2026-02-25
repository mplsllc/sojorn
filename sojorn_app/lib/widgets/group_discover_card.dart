// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group.dart';
import '../providers/api_provider.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/error_handler.dart';
import 'media/sojorn_avatar.dart';
import 'media/signed_media_image.dart';

/// Discovery card for groups — cover image, overlapping avatar, description, join button.
class GroupDiscoverCard extends ConsumerStatefulWidget {
  final Group group;
  final String? reason;
  final VoidCallback? onTap;
  final VoidCallback? onJoined;

  const GroupDiscoverCard({
    super.key,
    required this.group,
    this.reason,
    this.onTap,
    this.onJoined,
  });

  @override
  ConsumerState<GroupDiscoverCard> createState() => _GroupDiscoverCardState();
}

class _GroupDiscoverCardState extends ConsumerState<GroupDiscoverCard> {
  bool _isLoading = false;
  bool _isHovered = false;

  Future<void> _handleJoin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.joinGroup(widget.group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Request sent'),
            backgroundColor:
                result['status'] == 'joined' ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        widget.onJoined?.call();
      }
    } catch (e) {
      if (mounted) ErrorHandler.handleError(e, context: context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final cat = group.category;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(SojornRadii.card),
            border: Border.all(
                color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Cover image ──
              SizedBox(
                height: 120,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (group.bannerUrl != null &&
                        group.bannerUrl!.isNotEmpty)
                      SignedMediaImage(
                        url: group.bannerUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildGradientFallback(cat),
                      )
                    else
                      _buildGradientFallback(cat),
                    // Dark gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                            ],
                            stops: const [0.4, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Category badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.icon, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              cat.displayName,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Avatar overlap ──
              Transform.translate(
                offset: const Offset(0, -20),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(SojornRadii.card),
                      border: Border.all(
                          color: AppTheme.cardSurface, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SojornAvatar(
                      displayName: group.name,
                      avatarUrl: group.avatarUrl,
                      size: 48,
                    ),
                  ),
                ),
              ),

              // ── Content ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              AppTheme.navyText.withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Stats row
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 14,
                            color: SojornColors.textDisabled),
                        const SizedBox(width: 4),
                        Text(
                          group.memberCountText,
                          style: TextStyle(
                            fontSize: 12,
                            color: SojornColors.textDisabled,
                          ),
                        ),
                        if (group.postCount > 0) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 12,
                              color: SojornColors.textDisabled,
                            ),
                          ),
                          Icon(Icons.article_outlined,
                              size: 13,
                              color: SojornColors.textDisabled),
                          const SizedBox(width: 3),
                          Text(
                            group.postCountText,
                            style: TextStyle(
                              fontSize: 12,
                              color: SojornColors.textDisabled,
                            ),
                          ),
                        ],
                        if (widget.reason != null &&
                            widget.reason!.isNotEmpty) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 12,
                              color: SojornColors.textDisabled,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              widget.reason!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.brightNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Join button
                    _buildJoinButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientFallback(GroupCategory cat) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cat.color.withValues(alpha: 0.6),
            cat.color.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: Icon(cat.icon,
            size: 36,
            color: Colors.white.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _buildJoinButton() {
    final group = widget.group;

    if (group.isMember) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(Icons.check, size: 16, color: AppTheme.royalPurple),
          label: Text(
            'Joined',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalPurple,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppTheme.royalPurple, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md)),
            padding: const EdgeInsets.symmetric(vertical: 9),
          ),
        ),
      );
    }

    if (group.hasPendingRequest) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md)),
            padding: const EdgeInsets.symmetric(vertical: 9),
          ),
          child: Text(
            'Pending',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SojornColors.textDisabled,
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return SizedBox(
        width: double.infinity,
        height: 38,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.royalPurple,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _handleJoin,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.royalPurple,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SojornRadii.md)),
          padding: const EdgeInsets.symmetric(vertical: 9),
        ),
        child: Text(
          group.isPrivate ? 'Request to Join' : 'Join Group',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
