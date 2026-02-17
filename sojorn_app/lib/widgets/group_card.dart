import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group.dart';
import '../providers/api_provider.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/error_handler.dart';
import 'follow_button.dart';

/// Card widget for displaying a group in discovery and lists
class GroupCard extends ConsumerStatefulWidget {
  final Group group;
  final VoidCallback? onTap;
  final bool showReason;
  final String? reason;

  const GroupCard({
    super.key,
    required this.group,
    this.onTap,
    this.showReason = false,
    this.reason,
  });

  @override
  ConsumerState<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<GroupCard> {
  bool _isLoading = false;

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
            backgroundColor: result['status'] == 'joined' ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(e, context: context);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLeave() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      await api.leaveGroup(widget.group.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left group successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(e, context: context);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildJoinButton() {
    if (widget.group.isMember) {
      return Container(
        width: 80,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Joined',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      );
    }

    if (widget.group.hasPendingRequest) {
      return Container(
        width: 80,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Pending',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.orange[800],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Container(
        width: 80,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.navyBlue),
            ),
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: _handleJoin,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.navyBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size(80, 32),
      ),
      child: Text(
        widget.group.isPrivate ? 'Request' : 'Join',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with avatar and privacy indicator
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.1),
                  backgroundImage: widget.group.avatarUrl != null
                      ? NetworkImage(widget.group.avatarUrl!)
                      : null,
                  child: widget.group.avatarUrl == null
                      ? Icon(Icons.group, size: 24, color: AppTheme.navyBlue.withValues(alpha: 0.3))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.group.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.group.isPrivate)
                            const Icon(Icons.lock, size: 16, color: Colors.grey),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(widget.group.category).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.group.category.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getCategoryColor(widget.group.category),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Description
            if (widget.group.description.isNotEmpty)
              Text(
                widget.group.description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            
            if (widget.group.description.isNotEmpty)
              const SizedBox(height: 8),
            
            // Stats
            Row(
              children: [
                Text(
                  widget.group.memberCountText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Text(' • ', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                Text(
                  widget.group.postCountText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            
            if (widget.showReason && widget.reason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.reason!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            
            const Spacer(),
            
            // Join button
            _buildJoinButton(),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(GroupCategory category) {
    switch (category) {
      case GroupCategory.general:
        return AppTheme.navyBlue;
      case GroupCategory.hobby:
        return Colors.purple;
      case GroupCategory.sports:
        return Colors.green;
      case GroupCategory.professional:
        return Colors.blue;
      case GroupCategory.localBusiness:
        return Colors.orange;
      case GroupCategory.support:
        return Colors.pink;
      case GroupCategory.education:
        return Colors.teal;
    }
  }
}

/// Compact version of GroupCard for horizontal scrolling lists
class CompactGroupCard extends StatelessWidget {
  final Group group;
  final VoidCallback? onTap;
  final bool showReason;
  final String? reason;

  const CompactGroupCard({
    super.key,
    required this.group,
    this.onTap,
    this.showReason = false,
    this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.1),
              backgroundImage: group.avatarUrl != null
                  ? NetworkImage(group.avatarUrl!)
                  : null,
              child: group.avatarUrl == null
                  ? Icon(Icons.group, size: 28, color: AppTheme.navyBlue.withValues(alpha: 0.3))
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              group.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (group.isPrivate)
                  Icon(Icons.lock, size: 12, color: Colors.grey[600]),
                Text(
                  group.memberCountText,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            if (widget.showReason && widget.reason != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.reason!,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.blue[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
