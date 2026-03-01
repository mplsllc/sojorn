// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'quip_decorate_screen.dart';
import 'quip_studio_screen.dart';
import '../../../models/sojorn_media_result.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';

/// Stage 2 of the Quip creation flow — preview playback and optional trim.
///
/// The user sees their recorded/picked video looping. From here they can:
///   - Open the trim editor ("Studio" button → QuipStudioScreen)
///   - Proceed to decoration ("Next" → QuipDecorateScreen)
class QuipPreviewScreen extends StatefulWidget {
  final File videoFile;
  const QuipPreviewScreen({super.key, required this.videoFile});

  @override
  State<QuipPreviewScreen> createState() => _QuipPreviewScreenState();
}

class _QuipPreviewScreenState extends State<QuipPreviewScreen> {
  late VideoPlayerController _controller;
  File _currentFile;
  bool _isInitialized = false;

  _QuipPreviewScreenState() : _currentFile = File('');

  @override
  void initState() {
    super.initState();
    _currentFile = widget.videoFile;
    _initVideo();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initVideo() async {
    _controller = VideoPlayerController.file(_currentFile);
    await _controller.initialize();
    _controller.setLooping(true);
    _controller.play();
    if (mounted) setState(() => _isInitialized = true);
  }

  /// Opens the trim editor. If the user saves, reload the player with the new file.
  void _openTrimEditor() async {
    _controller.pause();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuipStudioScreen(videoFile: _currentFile)),
    );

    File? newFile;
    if (result is File) {
      newFile = result;
    } else if (result is SojornMediaResult && result.filePath != null) {
      newFile = File(result.filePath!);
    }

    if (newFile != null && mounted) {
      await _controller.dispose();
      setState(() {
        _currentFile = newFile!;
        _isInitialized = false;
      });
      _initVideo();
    } else if (mounted) {
      _controller.play();
    }
  }

  /// Proceeds to the decoration stage.
  void _next() {
    _controller.pause();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuipDecorateScreen(videoXFile: XFile(_currentFile.path)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),

          // 2. UI chrome
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: SojornColors.basicWhite),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          // 3. Right sidebar — Trim only (overlays are handled on the Decorate screen)
          Positioned(
            right: 16,
            top: 100,
            child: _buildSideButton(Icons.cut, 'Trim', _openTrimEditor),
          ),

          // 4. Next FAB
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: AppTheme.brightNavy,
              onPressed: _next,
              child: const Icon(Icons.arrow_forward, color: SojornColors.basicWhite),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            backgroundColor: const Color(0x8A000000),
            radius: 24,
            child: Icon(icon, color: SojornColors.basicWhite, size: 28),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: SojornColors.basicWhite,
            fontSize: 12,
            shadows: [Shadow(blurRadius: 2, color: SojornColors.basicBlack)],
          ),
        ),
      ],
    );
  }
}
