import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/beacon.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'camera_player.dart';

const _teal = Color(0xFF0097A7);

/// Full-featured camera viewer bottom sheet.
///
/// • Web  → inline HLS player via HtmlElementView + HLS.js
/// • iOS/Android → Chewie (play / pause / seek / fullscreen / volume)
/// • Fallback → "Watch in Browser" button
class CameraViewerSheet extends StatefulWidget {
  final Beacon camera;
  const CameraViewerSheet({super.key, required this.camera});

  @override
  State<CameraViewerSheet> createState() => _CameraViewerSheetState();
}

class _CameraViewerSheetState extends State<CameraViewerSheet> {
  VideoPlayerController? _vpc;
  ChewieController? _chewie;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initNativePlayer();
    else setState(() => _loading = false);
  }

  Future<void> _initNativePlayer() async {
    final stream = widget.camera.streamUrl;
    if (stream == null || stream.isEmpty) {
      setState(() { _loading = false; _error = true; });
      return;
    }
    try {
      _vpc = VideoPlayerController.networkUrl(Uri.parse(stream));
      await _vpc!.initialize();
      _chewie = ChewieController(
        videoPlayerController: _vpc!,
        autoPlay: true,
        looping: true,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: _vpc!.value.aspectRatio > 0 ? _vpc!.value.aspectRatio : 16 / 9,
        placeholder: _videoPlaceholder,
        materialProgressColors: ChewieProgressColors(
          playedColor: _teal,
          handleColor: _teal,
          bufferedColor: _teal.withValues(alpha: 0.4),
          backgroundColor: Colors.white24,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: _teal,
          handleColor: _teal,
        ),
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[Camera] native player init error: $e');
      _vpc?.dispose();
      _vpc = null;
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Widget get _videoPlaceholder => const ColoredBox(
    color: Color(0xFF0A1628),
    child: Center(child: CircularProgressIndicator(color: _teal)),
  );

  @override
  void dispose() {
    _chewie?.dispose();
    _vpc?.dispose();
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    final url = widget.camera.imageUrl?.isNotEmpty == true
        ? widget.camera.imageUrl!
        : widget.camera.streamUrl ?? '';
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      expand: false,
      builder: (ctx, _) => Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── drag handle ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // ── header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam, color: _teal, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cam.body,
                          style: TextStyle(
                            color: AppTheme.navyBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(children: [
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _teal.withValues(alpha: 0.3)),
                            ),
                            child: const Text('LIVE', style: TextStyle(
                              color: _teal, fontSize: 10, fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            )),
                          ),
                          Text('MN DOT Traffic Camera',
                            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                        ]),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _openInBrowser,
                        icon: Icon(Icons.open_in_new,
                            color: AppTheme.navyBlue.withValues(alpha: 0.45), size: 18),
                        tooltip: 'Open in browser',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close,
                            color: AppTheme.navyBlue.withValues(alpha: 0.35), size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── divider ─────────────────────────────────────────
            Divider(height: 1, color: AppTheme.navyBlue.withValues(alpha: 0.08)),

            // ── video canvas (always dark) ────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: Container(
                  color: const Color(0xFF0A1628),
                  padding: EdgeInsets.only(bottom: bottomPad),
                  child: _buildVideoArea(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_loading) return _videoPlaceholder;

    // Web: use inline HLS.js player
    if (kIsWeb) {
      final stream = widget.camera.streamUrl;
      if (stream != null && stream.isNotEmpty && webCameraPlayerSupported) {
        return buildInlineCameraPlayer(stream);
      }
      return _buildFallback();
    }

    // Native: use Chewie player
    if (!_error && _chewie != null) {
      return Chewie(controller: _chewie!);
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam, color: _teal, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            kIsWeb ? 'Open in browser for full controls' : 'Stream unavailable',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(widget.camera.body,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Watch Live'),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
