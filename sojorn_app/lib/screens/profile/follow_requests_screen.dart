import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/follow_request.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media/signed_media_image.dart';

class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<FollowRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final requests = await apiService.getFollowRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptRequest(FollowRequest request) async {
    final apiService = ref.read(apiServiceProvider);
    try {
      await apiService.acceptFollowRequest(request.followerId);
      if (!mounted) return;
      setState(() {
        _requests.removeWhere((r) => r.followerId == request.followerId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept @${request.handle}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _rejectRequest(FollowRequest request) async {
    final apiService = ref.read(apiServiceProvider);
    try {
      await apiService.rejectFollowRequest(request.followerId);
      if (!mounted) return;
      setState(() {
        _requests.removeWhere((r) => r.followerId == request.followerId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to decline @${request.handle}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Follow Requests',
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadRequests,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState()
                : _requests.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppTheme.spacingMd),
                        itemBuilder: (context, index) =>
                            _buildRequestTile(_requests[index]),
                      ),
      ),
    );
  }

  Widget _buildRequestTile(FollowRequest request) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.queenPink.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.queenPink,
            child: request.avatarUrl != null
                ? ClipOval(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: SignedMediaImage(
                        url: request.avatarUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : Text(
                    request.displayName.isNotEmpty
                        ? request.displayName[0].toUpperCase()
                        : '?',
                    style: AppTheme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.royalPurple,
                    ),
                  ),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.displayName,
                  style: AppTheme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '@${request.handle}',
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          TextButton(
            onPressed: () => _rejectRequest(request),
            child: const Text('Decline'),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          ElevatedButton(
            onPressed: () => _acceptRequest(request),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalPurple,
              foregroundColor: AppTheme.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'No follow requests right now.',
        style: AppTheme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _errorMessage ?? 'Something went wrong.',
            style: AppTheme.textTheme.labelMedium?.copyWith(color: AppTheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          ElevatedButton(
            onPressed: _loadRequests,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
