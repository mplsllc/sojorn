// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'quip_studio_screen.dart'; // Stage 3
import 'quip_metadata_screen.dart'; // Stage 4
import '../../../models/sojorn_media_result.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';

class QuipPreviewScreen extends StatefulWidget {
  final File videoFile;
  const QuipPreviewScreen({super.key, required this.videoFile});

  @override
  State<QuipPreviewScreen> createState() => _QuipPreviewScreenState();
}

class _QuipPreviewScreenState extends State<QuipPreviewScreen> {
  late VideoPlayerController _controller;
  File _currentFile;
  
  // Simple overlay state
  final List<OverlayItem> _overlays = [];
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

  void _openProEditor() async {
    _controller.pause();
    // Navigate to Stage 3: Pro Studio
    // Expecting QuipStudioScreen to return a File or SojornMediaResult if edits were made.
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

    if (newFile != null) {
      // User saved edits, reload the player with new file
      await _controller.dispose();
      setState(() {
        _currentFile = newFile!;
        _isInitialized = false;
        // Optionally clear simple overlays if deep edits happened, or keep them.
        _overlays.clear(); 
      });
      _initVideo();
    } else {
      _controller.play(); // Just resume if they canceled
    }
  }

  void _addText() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xDD000000),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: SojornColors.basicWhite, fontSize: 24),
          decoration: InputDecoration(
            border: InputBorder.none, 
            hintText: 'Type here...',
            hintStyle: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.54)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                setState(() {
                  _overlays.add(OverlayItem(text: textController.text));
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Done', style: TextStyle(color: SojornColors.basicWhite)),
          )
        ],
      ),
    );
  }

  void _next() {
    _controller.pause();
    // Navigate to Stage 4: Metadata
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuipMetadataScreen(videoFile: _currentFile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(backgroundColor: SojornColors.basicBlack, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Layer
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),

          // 2. Overlay Layer
          ..._overlays.map((item) => Positioned(
            left: item.position.dx,
            top: item.position.dy,
            child: Draggable(
              feedback: Material(
                color: SojornColors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SojornColors.overlayDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SojornColors.basicWhite.withValues(alpha: 0.24), width: 1),
                  ),
                  child: Text(
                    item.text,
                    style: const TextStyle(
                      color: SojornColors.basicWhite, 
                      fontSize: 28, 
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 4, color: SojornColors.basicBlack)],
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SojornColors.overlayDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.text,
                    style: const TextStyle(
                      color: SojornColors.basicWhite, 
                      fontSize: 28, 
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              onDragEnd: (details) {
                setState(() {
                  // Adjust position accounting for app bar height if needed, 
                  // but simplest is just taking offset.
                  // Ideally convert global to local, but details.offset is global.
                  // We need RenderBox of Stack.
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localOffset = box.globalToLocal(details.offset);
                  
                  // Clamp to screen bounds
                  final x = localOffset.dx.clamp(0.0, box.size.width - 100);
                  final y = localOffset.dy.clamp(0.0, box.size.height - 100);
                  
                  item.position = Offset(x, y);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SojornColors.overlayDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.text,
                  style: const TextStyle(
                    color: SojornColors.basicWhite, 
                    fontSize: 28, 
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4, color: SojornColors.basicBlack)],
                  ),
                ),
              ),
            ),
          )),

          // 3. UI Layer
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.all(8.0),
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

          // Right Controls
          Positioned(
            right: 16,
            top: 100,
            child: Column(
              children: [
                _buildSideButton(Icons.text_fields, "Text", _addText),
                const SizedBox(height: 20),
                _buildSideButton(Icons.edit_note, "Studio", _openProEditor),
              ],
            ),
          ),

          // Bottom Controls
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
        Text(label, style: const TextStyle(color: SojornColors.basicWhite, fontSize: 12, shadows: [Shadow(blurRadius: 2, color: SojornColors.basicBlack)])),
      ],
    );
  }
}

class OverlayItem {
  String text;
  Offset position;
  OverlayItem({required this.text, this.position = const Offset(100, 100)});
}