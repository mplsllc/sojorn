import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../services/media/ffmpeg.dart';
import 'package:path_provider/path_provider.dart';
import '../../../providers/quip_upload_provider.dart';
import '../../../services/image_upload_service.dart';
import '../../../providers/api_provider.dart';
import '../../../theme/tokens.dart';
import '../../../providers/feed_refresh_provider.dart';
import '../../../theme/app_theme.dart';

class QuipMetadataScreen extends ConsumerStatefulWidget {
  final File videoFile;
  const QuipMetadataScreen({super.key, required this.videoFile});

  @override
  ConsumerState<QuipMetadataScreen> createState() => _QuipMetadataScreenState();
}

class _QuipMetadataScreenState extends ConsumerState<QuipMetadataScreen> {
  late VideoPlayerController _controller;
  final TextEditingController _captionController = TextEditingController();
  double _coverTimestamp = 0.0;
  // bool _isUploading = false;
  // final ImageUploadService _uploadService = ImageUploadService();

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _postQuip() async {
    final uploadNotifier = ref.read(quipUploadProvider.notifier);
    
    // We already have the logic to generate a specific thumbnail in the provider,
    // but the screen allows choosing a timestamp.
    // To support the chosen cover, we'll generate it here and then pass it 
    // or just pass the timestamp to the provider.
    // Let's pass the chosen timestamp to startUpload.
    
    uploadNotifier.startUpload(
      widget.videoFile, 
      _captionController.text.trim(),
      thumbnailTimestampMs: _coverTimestamp,
    );

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload started in background")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('New Post'),
        backgroundColor: AppTheme.cardSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SojornColors.basicBlack),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              onPressed: _postQuip,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brightNavy,
                shape: const StadiumBorder(),
              ),
              child: const Text("Post"),
            ),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Caption Input
          TextField(
            controller: _captionController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "Write a caption... #hashtags",
              border: InputBorder.none,
            ),
          ),
          const Divider(height: 40),

          // 2. Cover Selection
          const Text("Select Cover", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          
          AspectRatio(
            aspectRatio: 16/9, // Widescreen preview for cover selection
            child: Container(
              color: SojornColors.basicBlack,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          ),
          
          Slider(
            value: _coverTimestamp,
            min: 0.0,
            max: _controller.value.duration.inMilliseconds.toDouble(),
            activeColor: AppTheme.brightNavy,
            onChanged: (value) {
              setState(() {
                _coverTimestamp = value;
              });
              _controller.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
          Center(child: Text("Scrub to choose a thumbnail frame", style: TextStyle(color: AppTheme.textDisabled, fontSize: 12))),
        ],
      ),
    );
  }
}