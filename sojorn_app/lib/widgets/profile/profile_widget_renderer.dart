import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sojorn/models/profile_widgets.dart';
import 'package:sojorn/theme/app_theme.dart';

class ProfileWidgetRenderer extends StatelessWidget {
  final ProfileWidget widget;
  final ProfileTheme theme;
  final VoidCallback? onTap;

  const ProfileWidgetRenderer({
    super.key,
    required this.widget,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = ProfileWidgetConstraints.getWidgetSize(widget.type);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.accentColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildWidgetContent(),
      ),
    );
  }

  Widget _buildWidgetContent() {
    switch (widget.type) {
      case ProfileWidgetType.pinnedPosts:
        return _buildPinnedPosts();
      case ProfileWidgetType.musicWidget:
        return _buildMusicWidget();
      case ProfileWidgetType.photoGrid:
        return _buildPhotoGrid();
      case ProfileWidgetType.socialLinks:
        return _buildSocialLinks();
      case ProfileWidgetType.bio:
        return _buildBio();
      case ProfileWidgetType.stats:
        return _buildStats();
      case ProfileWidgetType.quote:
        return _buildQuote();
      case ProfileWidgetType.beaconActivity:
        return _buildBeaconActivity();
      case ProfileWidgetType.customText:
        return _buildCustomText();
      case ProfileWidgetType.featuredFriends:
        return _buildFeaturedFriends();
    }
  }

  Widget _buildPinnedPosts() {
    final postIds = widget.config['postIds'] as List<dynamic>? ?? [];
    final maxPosts = widget.config['maxPosts'] as int? ?? 3;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.push_pin,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Pinned Posts',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (postIds.isEmpty)
            Text(
              'No pinned posts yet',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.6),
                fontSize: 12,
              ),
            )
          else
            Column(
              children: postIds.take(maxPosts).map((postId) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Post #${postId}',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildMusicWidget() {
    final currentTrack = widget.config['currentTrack'] as Map<String, dynamic>?;
    final isPlaying = widget.config['isPlaying'] as bool? ?? false;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.music_note,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Now Playing',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (currentTrack != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTrack['title'] ?? 'Unknown Track',
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  currentTrack['artist'] ?? 'Unknown Artist',
                  style: TextStyle(
                    color: theme.textColor.withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            )
          else
            Text(
              'No music playing',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.skip_previous,
                color: theme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 16),
              Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: theme.primaryColor,
                size: 24,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.skip_next,
                color: theme.primaryColor,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    final imageUrls = widget.config['imageUrls'] as List<dynamic>? ?? [];
    final maxPhotos = widget.config['maxPhotos'] as int? ?? 6;
    final columns = widget.config['columns'] as int? ?? 3;
    
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_library,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Photo Gallery',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (imageUrls.isEmpty)
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(
                  Icons.add_photo_alternate,
                  color: Colors.grey,
                  size: 32,
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              itemCount: imageUrls.take(maxPhotos).length,
              itemBuilder: (context, index) {
                final imageUrl = imageUrls[index] as String;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSocialLinks() {
    final links = widget.config['links'] as List<dynamic>? ?? [];
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Social Links',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (links.isEmpty)
            Text(
              'No social links added',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.6),
                fontSize: 12,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: links.map((link) {
                final linkData = link as Map<String, dynamic>;
                final platform = linkData['platform'] as String? ?? 'web';
                final url = linkData['url'] as String? ?? '';
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPlatformColor(platform),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getPlatformIcon(platform),
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        platform,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBio() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Bio',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your bio information will appear here...',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final showFollowers = widget.config['showFollowers'] as bool? ?? true;
    final showPosts = widget.config['showPosts'] as bool? ?? true;
    final showMemberSince = widget.config['showMemberSince'] as bool? ?? true;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Stats',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (showFollowers)
            _buildStatItem('Followers', '1.2K'),
          if (showPosts)
            _buildStatItem('Posts', '342'),
          if (showMemberSince)
            _buildStatItem('Member Since', 'Jan 2024'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuote() {
    final text = widget.config['text'] as String? ?? '';
    final author = widget.config['author'] as String? ?? 'Anonymous';
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Quote',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: theme.primaryColor,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              text.isNotEmpty ? text : 'Your favorite quote here...',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (author.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '— $author',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.7),
                fontSize: 10,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBeaconActivity() {
    final maxActivities = widget.config['maxActivities'] as int? ?? 5;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_on,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Beacon Activity',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Recent beacon contributions will appear here...',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomText() {
    final title = widget.config['title'] as String? ?? 'Custom Text';
    final content = widget.config['content'] as String? ?? 'Add your custom text here...';
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.text_fields,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedFriends() {
    final friendIds = widget.config['friendIds'] as List<dynamic>? ?? [];
    final maxFriends = widget.config['maxFriends'] as int? ?? 6;
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.people,
                color: theme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Featured Friends',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (friendIds.isEmpty)
            Text(
              'No featured friends yet',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.6),
                fontSize: 12,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: friendIds.take(maxFriends).map((friendId) {
                return CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.primaryColor.withOpacity(0.1),
                  child: Icon(
                    Icons.person,
                    color: theme.primaryColor,
                    size: 16,
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return Colors.blue;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue.shade(700);
      case 'github':
        return Colors.black;
      case 'linkedin':
        return Colors.blue.shade(800);
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return Icons.alternate_email;
      case 'instagram':
        return Icons.camera_alt;
      case 'facebook':
        return Icons.facebook;
      case 'github':
        return Icons.code;
      case 'linkedin':
        return Icons.work;
      case 'youtube':
        return Icons.play_circle;
      case 'tiktok':
        return Icons.music_video;
      default:
        return Icons.link;
    }
  }
}
