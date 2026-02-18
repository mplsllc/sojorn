import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'follow_button.dart';
import '../screens/profile/viewable_profile_screen.dart';
import 'media/sojorn_avatar.dart';

/// Horizontal scrolling section showing suggested users to follow
class SuggestedUsersSection extends StatefulWidget {
  const SuggestedUsersSection({super.key});

  @override
  State<SuggestedUsersSection> createState() => _SuggestedUsersSectionState();
}

class _SuggestedUsersSectionState extends State<SuggestedUsersSection> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final suggestions = await api.getSuggestedUsers(limit: 10);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingSkeleton();
    }

    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'People You May Know',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navyBlue,
                ),
              ),
              TextButton(
                onPressed: () {
                  // Navigate to full suggestions page
                },
                child: Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _suggestions.length,
            itemBuilder: (context, index) {
              return _SuggestedUserCard(
                user: _suggestions[index],
                onFollowChanged: (isFollowing) {
                  // Optionally remove from suggestions after following
                  if (isFollowing) {
                    setState(() {
                      _suggestions.removeAt(index);
                    });
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Container(
            width: 180,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Container(
                width: 160,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SuggestedUserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final Function(bool)? onFollowChanged;

  const _SuggestedUserCard({
    required this.user,
    this.onFollowChanged,
  });

  @override
  State<_SuggestedUserCard> createState() => __SuggestedUserCardState();
}

class __SuggestedUserCardState extends State<_SuggestedUserCard> {
  bool _isFollowing = false;

  @override
  Widget build(BuildContext context) {
    final userId = widget.user['id'] as String? ?? widget.user['user_id'] as String? ?? '';
    final username = widget.user['username'] as String? ?? '';
    final displayName = widget.user['display_name'] as String? ?? username;
    final avatarUrl = widget.user['avatar_url'] as String?;
    final reason = widget.user['reason'] as String?;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ViewableProfileScreen(userId: userId),
          ),
        );
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SojornAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              size: 72,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              '@$username',
              style: TextStyle(
                fontSize: 12,
                color: SojornColors.textDisabled,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                style: TextStyle(
                  fontSize: 10,
                  color: SojornColors.textDisabled,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FollowButton(
                targetUserId: userId,
                initialIsFollowing: _isFollowing,
                compact: true,
                onFollowChanged: (isFollowing) {
                  setState(() => _isFollowing = isFollowing);
                  widget.onFollowChanged?.call(isFollowing);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
