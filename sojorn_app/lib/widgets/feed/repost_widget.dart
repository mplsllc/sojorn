import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sojorn/models/repost.dart';
import 'package:sojorn/models/post.dart';
import 'package:sojorn/services/repost_service.dart';
import 'package:sojorn/providers/api_provider.dart';
import '../../theme/app_theme.dart';

class RepostWidget extends ConsumerWidget {
  final Post originalPost;
  final Repost? repost;
  final VoidCallback? onRepost;
  final VoidCallback? onBoost;
  final bool showAnalytics;

  const RepostWidget({
    super.key,
    required this.originalPost,
    this.repost,
    this.onRepost,
    this.onBoost,
    this.showAnalytics = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repostController = ref.watch(repostControllerProvider);
    final analyticsAsync = ref.watch(amplificationAnalyticsProvider(originalPost.id));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: repost != null ? Colors.blue.withOpacity(0.3) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Repost header
          if (repost != null)
            _buildRepostHeader(repost),
          
          // Original post content
          _buildOriginalPost(),
          
          // Engagement actions
          _buildEngagementActions(repostController),
          
          // Analytics section
          if (showAnalytics)
            _buildAnalyticsSection(analyticsAsync),
        ],
      ),
    );
  }

  Widget _buildRepostHeader(Repost repost) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Repost type icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: repost.type == RepostType.boost 
                ? Colors.orange 
                : repost.type == RepostType.amplify 
                  ? Colors.purple 
                  : Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              repost.type.icon,
              color: Colors.white,
              size: 16,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Reposter info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      repost.authorHandle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      repost.type.displayName,
                      style: TextStyle(
                        color: repost.type == RepostType.boost 
                          ? Colors.orange 
                          : repost.type == RepostType.amplify 
                            ? Colors.purple 
                            : Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  repost.timeAgo,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Amplification indicator
          if (repost.isAmplified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Amplified',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOriginalPost() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Original post author
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: originalPost.authorAvatar != null
                    ? NetworkImage(originalPost.authorAvatar!)
                    : null,
                child: originalPost.authorAvatar == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      originalPost.authorHandle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      originalPost.timeAgo,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Original post content
          if (originalPost.body.isNotEmpty)
            Text(
              originalPost.body,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
            ),
          
          // Original post media
          if (originalPost.imageUrl != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                originalPost.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ],
          
          if (originalPost.videoUrl != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.play_circle_filled, color: Colors.white, size: 48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEngagementActions(RepostController repostController) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey[700]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Engagement stats
          Row(
            children: [
              _buildEngagementStat(
                icon: Icons.repeat,
                count: originalPost.repostCount ?? 0,
                label: 'Reposts',
                onTap: onRepost,
              ),
              const SizedBox(width: 16),
              _buildEngagementStat(
                icon: Icons.rocket_launch,
                count: originalPost.boostCount ?? 0,
                label: 'Boosts',
                onTap: onBoost,
              ),
              const SizedBox(width: 16),
              _buildEngagementStat(
                icon: Icons.favorite,
                count: originalPost.likeCount ?? 0,
                label: 'Likes',
              ),
              const SizedBox(width: 16),
              _buildEngagementStat(
                icon: Icons.comment,
                count: originalPost.commentCount ?? 0,
                label: 'Comments',
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.repeat,
                  label: 'Repost',
                  color: Colors.blue,
                  onPressed: onRepost,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.rocket_launch,
                  label: 'Boost',
                  color: Colors.orange,
                  onPressed: onBoost,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.trending_up,
                  label: 'Amplify',
                  color: Colors.purple,
                  onPressed: () => _showAmplifyDialog(context),
                ),
              ),
            ],
          ),
          
          if (repostController.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(color: Colors.blue),
            ),
          
          if (repostController.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                repostController.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEngagementStat({
    required IconData icon,
    required int count,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.grey[400],
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsSection(AsyncValue<AmplificationAnalytics?> analyticsAsync) {
    return analyticsAsync.when(
      data: (analytics) {
        if (analytics == null) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.analytics,
                    color: Colors.purple,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Amplification Analytics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Stats grid
              Row(
                children: [
                  Expanded(
                    child: _buildAnalyticsItem(
                      'Total Reach',
                      analytics.totalAmplification.toString(),
                      Icons.visibility,
                    ),
                  ),
                  Expanded(
                    child: _buildAnalyticsItem(
                      'Engagement Rate',
                      '${(analytics.amplificationRate * 100).toStringAsFixed(1)}%',
                      Icons.trending_up,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Repost breakdown
              Text(
                'Repost Breakdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              ...analytics.repostCounts.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        entry.key.icon,
                        color: _getRepostTypeColor(entry.key),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.key.displayName}: ${entry.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: Colors.purple),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Failed to load analytics',
          style: TextStyle(color: Colors.red[400]),
        ),
      ),
    );
  }

  Widget _buildAnalyticsItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.purple,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Color _getRepostTypeColor(RepostType type) {
    switch (type) {
      case RepostType.standard:
        return Colors.blue;
      case RepostType.quote:
        return Colors.green;
      case RepostType.boost:
        return Colors.orange;
      case RepostType.amplify:
        return Colors.purple;
    }
  }

  void _showAmplifyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Amplify Post'),
        content: const Text('Choose amplification level:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle amplify action
            },
            child: const Text('Amplify'),
          ),
        ],
      ),
    );
  }
}
