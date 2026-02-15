import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/api_service.dart';

import '../../../models/sojorn_media_result.dart';
import '../../../providers/api_provider.dart';
import '../../../theme/tokens.dart';
import '../../../services/image_upload_service.dart';
import '../../../theme/app_theme.dart';
import '../../compose/video_editor_screen.dart';

/// Quip editor for videos with 10-second maximum duration.
/// Uses the standardized sojornVideoEditor and uploads via ImageUploadService.
class QuipEditorScreen extends ConsumerStatefulWidget {
  final File videoFile;
  final Duration originalDuration;
  final bool requireTrim;

  const QuipEditorScreen({
    super.key,
    required this.videoFile,
    this.originalDuration = Duration.zero,
    this.requireTrim = false,
  });

  @override
  ConsumerState<QuipEditorScreen> createState() => _QuipEditorScreenState();
}

class _QuipEditorScreenState extends ConsumerState<QuipEditorScreen> {
  static const Duration _maxDuration = Duration(seconds: 10);
  final TextEditingController _captionController = TextEditingController();
  final ImageUploadService _uploadService = ImageUploadService();

  bool _isProcessing = false;
  bool _isUploading = false;
  String? _statusMessage;
  String? _editedVideoPath;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _openVideoEditor() async {
    // Open the standardized video editor
    final result = await Navigator.push<SojornMediaResult>(
      context,
      MaterialPageRoute(
        builder: (context) => sojornVideoEditor(
          videoPath: widget.videoFile.path,
          videoName: 'quip_${DateTime.now().millisecondsSinceEpoch}.mp4',
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _editedVideoPath = result.filePath ?? widget.videoFile.path;
      });
    }
  }

  Future<void> _uploadQuip() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading your Quip...';
    });

    try {
      // Verify authentication
      final auth = AuthService.instance;
      final userId = auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be signed in to upload a quip.');
      }

      // Use the edited video path or original if not edited
      final videoToUpload = _editedVideoPath != null
          ? File(_editedVideoPath!)
          : widget.videoFile;

      // Ensure video is in temp directory
      File tempVideo;
      if (!videoToUpload.path.contains('cache')) {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        tempVideo = File('${tempDir.path}/quip_video_$timestamp.mp4');
        await videoToUpload.copy(tempVideo.path);
      } else {
        tempVideo = videoToUpload;
      }

      // Upload video via ImageUploadService
      final videoUrl = await _uploadService.uploadVideo(
        tempVideo,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Uploading... ${(progress * 100).toInt()}%';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Finalizing...';
      });

      // Calculate duration
      final durationMs = widget.originalDuration.inMilliseconds;

      // Publish post via Go API
      await ApiService.instance.publishPost(
        body: _captionController.text.trim(),
        imageUrl: videoUrl,
        categoryId: null, // Quips usually don't have a category in this UI
      );

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Upload complete!';
      });

      // Pop twice to return to quips feed
      Navigator.of(context).pop(true);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage = null;
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool videoDurationOk = widget.originalDuration <= _maxDuration;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: SojornColors.basicWhite,
        title: const Text('Create Quip'),
        actions: [
          if (!videoDurationOk)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Trim required (max 10s)',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Video preview placeholder
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: SojornColors.basicBlack,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.brightNavy.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: 80,
                          color: AppTheme.brightNavy,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Video Duration: ${widget.originalDuration.inSeconds}s',
                          style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
                        ),
                        if (!videoDurationOk) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Video exceeds 10s - trim required',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Edit Video button
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _openVideoEditor,
                icon: const Icon(Icons.edit),
                label: const Text('Edit Video'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.brightNavy,
                  side: BorderSide(color: AppTheme.brightNavy),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // Caption input
              TextField(
                controller: _captionController,
                maxLines: 2,
                maxLength: 150,
                style: const TextStyle(color: SojornColors.basicWhite),
                decoration: InputDecoration(
                  hintText: 'Add a caption (optional)',
                  hintStyle: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.54)),
                  filled: true,
                  fillColor: SojornColors.basicWhite.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.54)),
                ),
              ),
              const SizedBox(height: 16),

              // Status message
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      if (_isUploading) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.brightNavy,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
                        ),
                      ),
                    ],
                  ),
                ),

              // Upload button
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadQuip,
                icon: Icon(_isUploading ? Icons.hourglass_empty : Icons.upload),
                label: Text(_isUploading ? 'Uploading...' : 'Post Quip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  disabledBackgroundColor: AppTheme.brightNavy.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
