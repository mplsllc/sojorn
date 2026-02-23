// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../models/quip_text_overlay.dart';
import '../../../providers/quip_upload_provider.dart';
import '../../../screens/audio/audio_library_screen.dart';
import '../../../theme/tokens.dart';
import '../../../theme/app_theme.dart';

// Curated sticker/emoji set for the picker
const _kTextStickers = ['LOL', 'OMG', 'WOW', 'WAIT', 'FR?', 'NO WAY'];
const _kEmojis = [
  '🎉', '🔥', '❤️', '😂', '💯', '✨',
  '🤣', '😍', '🙌', '😮', '💕', '🤩',
  '🎶', '🌟', '💀', '😎', '🥰', '🤔',
  '👀', '🫶',
];

// Colors available for text overlays
const _kTextColors = [
  Colors.white,
  Colors.yellow,
  Colors.cyan,
  Colors.pinkAccent,
  Colors.greenAccent,
  Colors.redAccent,
];

/// Stage 2 of the new Quip creation flow.
///
/// The raw video loops immediately. The user decorates with:
/// - Draggable + pinch-to-scale/rotate text and sticker overlays
/// - Pre-recorded or newly-selected background audio
/// - A "Post Quip" FAB that fires a background upload and returns to the feed
class QuipDecorateScreen extends ConsumerStatefulWidget {
  final XFile videoXFile;
  final AudioTrack? preloadedAudio;

  const QuipDecorateScreen({
    super.key,
    required this.videoXFile,
    this.preloadedAudio,
  });

  @override
  ConsumerState<QuipDecorateScreen> createState() => _QuipDecorateScreenState();
}

class _QuipDecorateScreenState extends ConsumerState<QuipDecorateScreen> {
  late VideoPlayerController _controller;
  bool _videoReady = false;

  // Overlays
  final List<_EditableOverlay> _overlays = [];
  String? _draggingId; // id of the item being dragged/scaled

  // Trash zone
  bool _showTrash = false;
  bool _overTrash = false;

  // Audio
  AudioTrack? _selectedAudio;

  // Text color for next text item
  Color _nextTextColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _selectedAudio = widget.preloadedAudio;
    _initVideo();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    _controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoXFile.path))
        : VideoPlayerController.file(File(widget.videoXFile.path));
    await _controller.initialize();
    _controller.setLooping(true);
    _controller.play();
    if (mounted) setState(() => _videoReady = true);
  }

  // ─── Overlay management ────────────────────────────────────────────────────

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _addTextOverlay(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _overlays.add(_EditableOverlay(
        id: _newId(),
        type: QuipOverlayType.text,
        content: text.trim(),
        color: _nextTextColor,
        normalizedX: 0.5,
        normalizedY: 0.4,
        scale: 1.0,
        rotation: 0.0,
      ));
    });
  }

  void _addStickerOverlay(String sticker) {
    setState(() {
      _overlays.add(_EditableOverlay(
        id: _newId(),
        type: QuipOverlayType.sticker,
        content: sticker,
        color: Colors.white,
        normalizedX: 0.5,
        normalizedY: 0.5,
        scale: 1.0,
        rotation: 0.0,
      ));
    });
  }

  void _removeOverlay(String id) {
    setState(() => _overlays.removeWhere((o) => o.id == id));
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _openTextSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xDD000000),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Color row
            Row(
              children: _kTextColors.map((c) {
                final selected = c == _nextTextColor;
                return GestureDetector(
                  onTap: () => setState(() => _nextTextColor = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: SojornColors.basicWhite, width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: SojornColors.basicWhite, fontSize: 22),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type something...',
                hintStyle: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.4)),
              ),
              onSubmitted: (val) {
                Navigator.pop(ctx);
                _addTextOverlay(val);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _addTextOverlay(ctrl.text);
                },
                child: const Text('Done', style: TextStyle(color: SojornColors.basicWhite, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openStickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text stickers row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kTextStickers.map((s) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addStickerOverlay(s);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: SojornColors.basicWhite, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s,
                          style: const TextStyle(
                              color: SojornColors.basicWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Emoji grid
            SizedBox(
              height: 180,
              child: GridView.count(
                crossAxisCount: 7,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: _kEmojis.map((e) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addStickerOverlay(e);
                    },
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSound() async {
    final track = await Navigator.push<AudioTrack>(
      context,
      MaterialPageRoute(builder: (_) => const AudioLibraryScreen()),
    );
    if (track != null && mounted) {
      setState(() => _selectedAudio = track);
    }
  }

  Future<void> _postQuip() async {
    _controller.pause();

    // Build overlay + sound JSON payload
    final payload = {
      'overlays': _overlays.map((o) => o.toJson()).toList(),
      if (_selectedAudio != null) 'sound_id': _selectedAudio!.path,
    };
    final overlayJson = jsonEncode(payload);

    ref.read(quipUploadProvider.notifier).startUpload(
      widget.videoXFile,
      '',
      overlayJson: overlayJson,
    );

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading your Quip...')),
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_videoReady) {
      return const Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(child: CircularProgressIndicator(color: SojornColors.basicWhite)),
      );
    }

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Looping video
              Center(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),

              // 2. Overlay items (draggable, pinch-to-scale/rotate)
              ..._overlays.map((o) => _buildOverlayWidget(o, w, h)),

              // 3. Trash zone (shown while dragging)
              if (_showTrash)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _overTrash
                            ? SojornColors.destructive
                            : const Color(0xAA000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: SojornColors.basicWhite,
                        size: _overTrash ? 40 : 32,
                      ),
                    ),
                  ),
                ),

              // 4. Top-left back button
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: SojornColors.basicWhite),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),

              // 5. Right sidebar (Text, Sticker, Sound)
              Positioned(
                right: 16,
                top: 100,
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildSideButton(Icons.text_fields, 'Text', _openTextSheet),
                      const SizedBox(height: 20),
                      _buildSideButton(Icons.emoji_emotions_outlined, 'Sticker', _openStickerSheet),
                      const SizedBox(height: 20),
                      _buildSideButton(
                        _selectedAudio != null ? Icons.music_note : Icons.music_note_outlined,
                        _selectedAudio != null ? 'Sound ✓' : 'Sound',
                        _pickSound,
                      ),
                    ],
                  ),
                ),
              ),

              // 6. "Post Quip" FAB (bottom-right)
              Positioned(
                bottom: 40,
                right: 20,
                child: FloatingActionButton.extended(
                  backgroundColor: AppTheme.brightNavy,
                  onPressed: _postQuip,
                  icon: const Icon(Icons.send_rounded, color: SojornColors.basicWhite),
                  label: const Text(
                    'Post Quip',
                    style: TextStyle(color: SojornColors.basicWhite, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlayWidget(_EditableOverlay overlay, double w, double h) {
    final absX = overlay.normalizedX * w;
    final absY = overlay.normalizedY * h;
    final isText = overlay.type == QuipOverlayType.text;

    return Positioned(
      left: absX - 60, // rough half-width offset so item centers on position
      top: absY - 30,
      child: GestureDetector(
        onScaleStart: (_) {
          setState(() {
            _draggingId = overlay.id;
            _showTrash = true;
          });
        },
        onScaleUpdate: (details) {
          final idx = _overlays.indexWhere((o) => o.id == overlay.id);
          if (idx == -1) return;

          // Convert global focal point to normalized position
          final newNX = (details.focalPoint.dx / w).clamp(0.0, 1.0);
          final newNY = (details.focalPoint.dy / h).clamp(0.0, 1.0);

          // Detect if over trash zone (bottom 80px)
          final overTrash = details.focalPoint.dy > h - 80;

          setState(() {
            _overTrash = overTrash;
            _overlays[idx] = _overlays[idx].copyWith(
              normalizedX: newNX,
              normalizedY: newNY,
              scale: (_overlays[idx].scale * details.scale).clamp(0.3, 5.0),
              rotation: _overlays[idx].rotation + details.rotation,
            );
          });
        },
        onScaleEnd: (_) {
          if (_overTrash && _draggingId != null) {
            _removeOverlay(_draggingId!);
          }
          setState(() {
            _draggingId = null;
            _showTrash = false;
            _overTrash = false;
          });
        },
        child: Transform(
          transform: Matrix4.identity()
            ..scale(overlay.scale)
            ..rotateZ(overlay.rotation),
          alignment: Alignment.center,
          child: isText
              ? _buildTextChip(overlay)
              : _buildStickerChip(overlay),
        ),
      ),
    );
  }

  Widget _buildTextChip(_EditableOverlay overlay) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        overlay.content,
        style: TextStyle(
          color: overlay.color,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
    );
  }

  Widget _buildStickerChip(_EditableOverlay overlay) {
    final isEmoji = overlay.content.runes.length == 1 ||
        overlay.content.length <= 2;
    if (isEmoji) {
      return Text(overlay.content, style: const TextStyle(fontSize: 48));
    }
    // Text sticker ('LOL', 'OMG', etc.)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: SojornColors.basicWhite, width: 2),
        borderRadius: BorderRadius.circular(8),
        color: Colors.black.withValues(alpha: 0.3),
      ),
      child: Text(
        overlay.content,
        style: const TextStyle(
          color: SojornColors.basicWhite,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
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
            child: Icon(icon, color: SojornColors.basicWhite, size: 26),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: SojornColors.basicWhite,
            fontSize: 11,
            shadows: [Shadow(blurRadius: 2, color: Colors.black)],
          ),
        ),
      ],
    );
  }
}

// ─── Internal mutable overlay state ──────────────────────────────────────────

class _EditableOverlay {
  final String id;
  final QuipOverlayType type;
  final String content;
  final Color color;
  double normalizedX;
  double normalizedY;
  double scale;
  double rotation;

  _EditableOverlay({
    required this.id,
    required this.type,
    required this.content,
    required this.color,
    required this.normalizedX,
    required this.normalizedY,
    required this.scale,
    required this.rotation,
  });

  _EditableOverlay copyWith({
    double? normalizedX,
    double? normalizedY,
    double? scale,
    double? rotation,
  }) {
    return _EditableOverlay(
      id: id,
      type: type,
      content: content,
      color: color,
      normalizedX: normalizedX ?? this.normalizedX,
      normalizedY: normalizedY ?? this.normalizedY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'color': color.value,
    'position': {'x': normalizedX, 'y': normalizedY},
    'scale': scale,
    'rotation': rotation,
  };
}
