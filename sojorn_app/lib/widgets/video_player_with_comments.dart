// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'video_comments_sheet.dart';
import 'media/signed_media_image.dart';

/// Enhanced video player with integrated comments (TikTok-style)
class VideoPlayerWithComments extends StatefulWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onShare;
  final VoidCallback? onCommentTap;

  const VideoPlayerWithComments({
    super.key,
    required this.post,
    this.onLike,
    this.onShare,
    this.onCommentTap,
  });

  @override
  State<VideoPlayerWithComments> createState() => _VideoPlayerWithCommentsState();
}

class _VideoPlayerWithCommentsState extends State<VideoPlayerWithComments> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isControlsVisible = true;
  int _commentCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _commentCount = widget.post.commentCount ?? 0;
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (widget.post.videoUrl == null) return;

    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.post.videoUrl!),
      );
      
      await _videoController!.initialize();
      
      _videoController!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _videoController!.value.isPlaying;
          });
        }
      });
      
      setState(() {});
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SojornColors.basicBlack,
      child: Stack(
        children: [
          // Video player
          _buildVideoPlayer(),
          
          // Video controls overlay
          if (_isControlsVisible)
            _buildControlsOverlay(),
          
          // Side action buttons
          _buildSideActions(),
          
          // Bottom info
          _buildBottomInfo(),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Thumbnail fallback
            if (widget.post.thumbnailUrl != null)
              Positioned.fill(
                child: SignedMediaImage(
                  url: widget.post.thumbnailUrl!,
                  fit: BoxFit.cover,
                ),
              ),
            
            // Loading indicator
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(SojornColors.basicWhite),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _isControlsVisible = !_isControlsVisible;
        });
        
        // Hide controls after 3 seconds
        if (_isControlsVisible) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _isControlsVisible) {
              setState(() => _isControlsVisible = false);
            }
          });
        }
      },
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0x4D000000),
              SojornColors.transparent,
              SojornColors.transparent,
              const Color(0x80000000),
            ],
          ),
        ),
        child: Column(
          children: [
            // Top controls
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: SojornColors.basicWhite),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      _showMoreOptions(context);
                    },
                    icon: const Icon(Icons.more_vert, color: SojornColors.basicWhite),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            // Bottom controls
            SafeArea(
              child: Row(
                children: [
                  // Play/Pause button
                  IconButton(
                    onPressed: () {
                      if (_isPlaying) {
                        _videoController?.pause();
                      } else {
                        _videoController?.play();
                      }
                    },
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: SojornColors.basicWhite,
                      size: 48,
                    ),
                  ),
                  
                  // Progress bar
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: VideoProgressIndicator(
                        _videoController!,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: SojornColors.basicWhite,
                          backgroundColor: SojornColors.basicWhite.withValues(alpha: 0.24),
                          bufferedColor: SojornColors.basicWhite.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                  ),
                  
                  // Duration
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      _formatDuration(_videoController?.value.position) ?? '0:00',
                      style: GoogleFonts.inter(
                        color: SojornColors.basicWhite,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideActions() {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        children: [
          // Like button
          _buildActionButton(
            icon: Icons.favorite,
            count: widget.post.likeCount ?? 0,
            onTap: widget.onLike,
          ),
          
          const SizedBox(height: 16),
          
          // Comment button
          _buildActionButton(
            icon: Icons.chat_bubble_outline,
            count: _commentCount,
            onTap: _showComments,
          ),
          
          const SizedBox(height: 16),
          
          // Share button
          _buildActionButton(
            icon: Icons.share,
            count: null,
            onTap: widget.onShare,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required int? count,
    required VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0x4D000000),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: SojornColors.basicWhite, size: 24),
          ),
        ),
        if (count != null) ...[
          const SizedBox(height: 4),
          Text(
            count > 999 ? '${(count / 1000).toStringAsFixed(1)}k' : count.toString(),
            style: GoogleFonts.inter(
              color: SojornColors.basicWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomInfo() {
    return Positioned(
      left: 16,
      right: 80, // Leave space for action buttons
      bottom: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author info
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.brightNavy.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: widget.post.author?.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SignedMediaImage(
                          url: widget.post.author!.avatarUrl!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(
                          widget.post.author?.displayName?.isNotEmpty == true
                              ? widget.post.author!.displayName![0].toUpperCase()
                              : '?',
                          style: GoogleFonts.inter(
                            color: SojornColors.basicWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.post.author?.displayName ?? 
                  widget.post.author?.handle ?? 
                  'Anonymous',
                  style: GoogleFonts.inter(
                    color: SojornColors.basicWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Post content
          Text(
            widget.post.body,
            style: GoogleFonts.inter(
              color: SojornColors.basicWhite,
              fontSize: 14,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showComments() {
    widget.onCommentTap?.call();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (context) => VideoCommentsSheet(
        postId: widget.post.id,
        initialCommentCount: _commentCount,
        onCommentPosted: () {
          setState(() {
            _commentCount++;
          });
        },
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Video Options',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.speed, color: Colors.white),
              title: const Text(
                'Playback Speed',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPlaybackSpeedDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.report, color: Colors.white),
              title: const Text(
                'Report Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text(
                'Share Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onShare?.call();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showPlaybackSpeedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback Speed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return RadioListTile<double>(
              title: Text('${speed}x'),
              value: speed,
              groupValue: _videoController?.value.playbackSpeed ?? 1.0,
              onChanged: (value) {
                if (value != null && _videoController != null) {
                  _videoController!.setPlaybackSpeed(value);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Video'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Why are you reporting this video?'),
            const SizedBox(height: 16),
            ...['Inappropriate content', 'Spam', 'Copyright violation', 'Other'].map((reason) {
              return ListTile(
                title: Text(reason),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video reported successfully')),
                  );
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
