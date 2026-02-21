// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../media/signed_media_image.dart';

enum BlockState {
  idle, // Preview mode - minimal display
  active, // Inspector mode - expanded with full details
}

/// InteractiveReplyBlock - A 2-stage interactive widget for reply posts
/// Stage 1 (Idle/Preview): Minimalist block with avatar + truncated preview
/// Stage 2 (Active/Inspector): Expanded block with full content and actions
class InteractiveReplyBlock extends StatefulWidget {
  final Post post;
  final VoidCallback? onTap;
  final BlockState initialState;
  final bool isSelected;
  final bool compactPreview;
  final Widget? reactionStrip;
  final bool? isLikedOverride;
  final VoidCallback? onToggleLike;

  const InteractiveReplyBlock({
    super.key,
    required this.post,
    this.onTap,
    this.initialState = BlockState.idle,
    this.isSelected = false,
    this.compactPreview = false,
    this.reactionStrip,
    this.isLikedOverride,
    this.onToggleLike,
  });

  @override
  State<InteractiveReplyBlock> createState() => _InteractiveReplyBlockState();
}

class _InteractiveReplyBlockState extends State<InteractiveReplyBlock>
    with TickerProviderStateMixin {
  late BlockState _currentState;
  late AnimationController _expandController;
  late AnimationController _bounceController;
  late Animation<double> _expandAnimation;
  late Animation<double> _bounceAnimation;

  static const Duration _expandDuration = Duration(milliseconds: 400);
  static const Duration _bounceDuration = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _currentState = widget.initialState;
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _expandController = AnimationController(
      duration: _expandDuration,
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: _bounceDuration,
      vsync: this,
    );

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    _bounceAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    ));

    if (_currentState == BlockState.active) {
      _expandController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.compactPreview) {
      widget.onTap?.call();
      return;
    }
    if (_currentState == BlockState.idle) {
      _transitionToActive();
    } else {
      widget.onTap?.call();
    }
  }

  void _transitionToActive() {
    setState(() => _currentState = BlockState.active);
    _expandController.forward();
    _bounceController.forward(from: 0.0);
    
    // Haptic feedback for tactile response
    // HapticFeedback.mediumImpact(); // Uncomment if haptic feedback is desired
  }

  void _transitionToIdle() {
    setState(() => _currentState = BlockState.idle);
    _expandController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _currentState == BlockState.active;
    if (widget.compactPreview && !isActive) {
      return SizedBox(
        width: 160,
        child: Material(
          color: SojornColors.transparent,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: _expandDuration,
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.brightNavy,
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brightNavy.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildCompactAvatar(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.post.author?.displayName ?? 'Anonymous',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _compactLabel(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.navyText.withValues(alpha: 0.75),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.reactionStrip != null) ...[
                    const SizedBox(height: 10),
                    widget.reactionStrip!,
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_expandAnimation, _bounceAnimation]),
      builder: (context, child) {
        final scale = _bounceAnimation.value;
        
        return Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: _expandDuration,
            curve: Curves.easeOutBack,
            margin: EdgeInsets.symmetric(
              vertical: isActive ? 8.0 : 4.0,
              horizontal: 16.0,
            ),
            padding: EdgeInsets.all(
              isActive ? 20.0 : 16.0,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected 
                  ? AppTheme.brightNavy.withValues(alpha: 0.08)
                  : AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(
                isActive ? 24.0 : 18.0,
              ),
              border: Border.all(
                color: widget.isSelected
                    ? AppTheme.brightNavy
                    : isActive
                        ? AppTheme.brightNavy.withValues(alpha: 0.4)
                        : AppTheme.navyBlue.withValues(alpha: 0.12),
                width: widget.isSelected ? 2.0 : (isActive ? 1.6 : 1.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.isSelected
                      ? AppTheme.brightNavy.withValues(alpha: 0.25)
                      : AppTheme.navyBlue.withValues(alpha: isActive ? 0.14 : 0.06),
                  blurRadius: isActive ? 24.0 : 14.0,
                  offset: const Offset(0, 8),
                ),
                if (isActive)
                  BoxShadow(
                    color: AppTheme.brightNavy.withValues(alpha: 0.1),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
              ],
            ),
            child: Material(
              color: SojornColors.transparent,
              child: InkWell(
                onTap: _handleTap,
                borderRadius: BorderRadius.circular(
                  isActive ? 24.0 : 18.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isActive),
                    if (isActive) ...[
                      const SizedBox(height: 12),
                    _buildFullContent(),
                    const SizedBox(height: 16),
                    _buildEngagementStats(),
                    if (widget.reactionStrip != null) ...[
                      const SizedBox(height: 12),
                      widget.reactionStrip!,
                    ],
                    const SizedBox(height: 12),
                    _buildActionButtons(),
                  ] else ...[
                    const SizedBox(height: 8),
                    _buildPreviewContent(),
                    if (widget.reactionStrip != null) ...[
                      const SizedBox(height: 10),
                      widget.reactionStrip!,
                    ],
                  ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).animate(target: _currentState == BlockState.active ? 1 : 0).fadeIn(
      duration: 300.ms,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildHeader(bool isActive) {
    return Row(
      children: [
        _buildAvatar(isActive),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.post.author?.displayName ?? 'Anonymous',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: isActive ? 16 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isActive) ...[
                const SizedBox(height: 2),
                Text(
                  '@${widget.post.author?.handle ?? 'anonymous'}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.expand_more,
              size: 16,
              color: AppTheme.egyptianBlue,
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(bool isActive) {
    final avatarUrl = widget.post.author?.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;
    final size = isActive ? 40.0 : 32.0;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.brightNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(isActive ? 14 : 10),
      ),
      child: !hasAvatar
          ? Center(
              child: Text(
                _initialForName(widget.post.author?.displayName),
                style: GoogleFonts.inter(
                  color: AppTheme.brightNavy,
                  fontSize: isActive ? 14 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(isActive ? 14 : 10),
              child: SignedMediaImage(
                url: avatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            ),
    );
  }

  Widget _buildPreviewContent() {
    final previewText = _getPreviewText(widget.post.body);
    
    return Text(
      previewText,
      style: GoogleFonts.inter(
        color: AppTheme.navyText.withValues(alpha: 0.8),
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFullContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.body,
          style: GoogleFonts.inter(
            color: AppTheme.navyText,
            fontSize: 16,
            height: 1.6,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (widget.post.imageUrl != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SignedMediaImage(
              url: widget.post.imageUrl!,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEngagementStats() {
    return Row(
      children: [
        _buildStatItem(
          icon: Icons.favorite_border,
          count: widget.post.likeCount ?? 0,
          color: SojornColors.destructive,
        ),
        const SizedBox(width: 16),
        _buildStatItem(
          icon: Icons.chat_bubble_outline,
          count: widget.post.commentCount ?? 0,
          color: AppTheme.egyptianBlue,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required int count,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: color.withValues(alpha: 0.7),
        ),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    final isLiked = widget.isLikedOverride ?? (widget.post.isLiked ?? false);
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // Handle reply action
              widget.onTap?.call();
            },
            icon: const Icon(Icons.reply, size: 16),
            label: const Text('Reply'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brightNavy,
              foregroundColor: SojornColors.basicWhite,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: widget.onToggleLike,
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? SojornColors.destructive : AppTheme.textSecondary,
          ),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  String _getPreviewText(String fullText) {
    // Simple preview - take first 80 characters
    if (fullText.length <= 80) return fullText;
    
    final preview = fullText.substring(0, 80);
    final lastSpace = preview.lastIndexOf(' ');
    
    if (lastSpace > 40) {
      return '${preview.substring(0, lastSpace)}...';
    }
    
    return '$preview...';
  }

  String _compactLabel() {
    final trimmed = widget.post.body.trim();
    if (trimmed.isEmpty) return 'reply..';
    return _getPreviewText(trimmed);
  }

  Widget _buildCompactAvatar() {
    final avatarUrl = widget.post.author?.avatarUrl;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppTheme.brightNavy.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: avatarUrl == null
          ? Center(
              child: Text(
                _initialForName(widget.post.author?.displayName),
                style: GoogleFonts.inter(
                  color: AppTheme.brightNavy,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SignedMediaImage(
                url: avatarUrl,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
    );
  }

  String _initialForName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'S';
    return trimmed.characters.first.toUpperCase();
  }
}
