// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/api_provider.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_ext.dart';

/// Follow/Unfollow button with loading state and animations
class FollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final bool initialIsFollowing;
  final Function(bool)? onFollowChanged;
  final bool compact;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.initialIsFollowing = false,
    this.onFollowChanged,
    this.compact = false,
  });

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  late bool _isFollowing;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.initialIsFollowing;
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIsFollowing != widget.initialIsFollowing) {
      setState(() => _isFollowing = widget.initialIsFollowing);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      if (_isFollowing) {
        await api.unfollowUser(widget.targetUserId);
      } else {
        await api.followUser(widget.targetUserId);
      }

      setState(() => _isFollowing = !_isFollowing);
      widget.onFollowChanged?.call(_isFollowing);
    } catch (e) {
      if (mounted) {
        context.showError('Failed to ${_isFollowing ? 'unfollow' : 'follow'}. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: widget.compact ? _buildCompactButton() : _buildFullButton(),
    );
  }

  Widget _buildFullButton() {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _toggleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isFollowing ? AppTheme.cardSurface : AppTheme.navyBlue,
          foregroundColor: _isFollowing ? AppTheme.navyBlue : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          elevation: 0,
          side: _isFollowing
              ? BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.2))
              : null,
        ),
        child: _isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    _isFollowing ? AppTheme.navyBlue : Colors.white,
                  ),
                ),
              )
            : Text(
                _isFollowing ? 'Following' : 'Follow',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildCompactButton() {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _toggleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isFollowing ? AppTheme.cardSurface : AppTheme.navyBlue,
          foregroundColor: _isFollowing ? AppTheme.navyBlue : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          side: _isFollowing
              ? BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.2))
              : null,
          minimumSize: const Size(80, 32),
        ),
        child: _isLoading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    _isFollowing ? AppTheme.navyBlue : Colors.white,
                  ),
                ),
              )
            : Text(
                _isFollowing ? 'Following' : 'Follow',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
