// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../services/media/ffmpeg.dart';

import '../../models/sojorn_media_result.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Sojorn Video Editor with basic trimming and FFmpeg export
/// Implements video editing with H.264 codec support via FFmpeg
class sojornVideoEditor extends StatefulWidget {
  final String? videoPath;
  final Uint8List? videoBytes;
  final String? videoName;

  const sojornVideoEditor({
    super.key,
    this.videoPath,
    this.videoBytes,
    this.videoName,
  }) : assert(videoPath != null || videoBytes != null);

  @override
  State<sojornVideoEditor> createState() => _sojornVideoEditorState();
}

class _sojornVideoEditorState extends State<sojornVideoEditor> {
  static const Color _matteBlack = Color(0xFF0B0B0B);
  static const Color _brightNavy = Color(0xFF1974D1);

  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';

  // Trimming variables
  Duration _startTrim = Duration.zero;
  Duration _endTrim = Duration.zero;
  bool _isTrimming = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (widget.videoPath == null || kIsWeb) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      _videoController = VideoPlayerController.file(File(widget.videoPath!));
      await _videoController!.initialize();
      await _videoController!.setLooping(true);

      // Initialize trimming to full video
      _endTrim = _videoController!.value.duration;

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize video: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _exportVideo() async {
    if (_isExporting || _videoController == null) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportStatus = 'Preparing export...';
    });

    try {
      // Generate output file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'sojorn_video_$timestamp.mp4';
      final outputFile = File('${tempDir.path}/$fileName');

      // FFmpeg command for trimming and encoding with H.264
      final startSeconds = _startTrim.inSeconds;
      final durationSeconds = _endTrim.inSeconds - _startTrim.inSeconds;

      final command =
          '-y -i "${widget.videoPath}" -ss $startSeconds -t $durationSeconds ' +
              '-c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k ' +
              '-shortest "${outputFile.path}"';

      // Execute FFmpeg command
      final session = await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Export successful
          if (!mounted) return;

          Navigator.pop(
            context,
            SojornMediaResult.video(
              filePath: outputFile.path,
              name: fileName,
            ),
          );
        } else {
          throw Exception('FFmpeg export failed with code: $returnCode');
        }
      }, (log) {
        // Update progress (this is a simple approach)
        if (mounted) {
          setState(() {
            _exportStatus = 'Exporting video...';
            // Note: FFmpeg progress parsing would require more complex logic
            // For now, we'll just show a simple progress indicator
          });
        }
      }, (statistics) {
        // Update progress based on FFmpeg statistics
        if (mounted) {
          setState(() {
            final time = statistics?.getTime();
            if (time != null && time > 0) {
              final totalDuration =
                  _endTrim.inMilliseconds - _startTrim.inMilliseconds;
              _exportProgress = time / totalDuration;
              _exportStatus =
                  'Exporting... ${(_exportProgress * 100).toInt()}%';
            }
          });
        }
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
          _exportStatus = '';
        });
      }
    }
  }

  Future<void> _saveWithoutEditing() async {
    setState(() => _isExporting = true);

    try {
      if (widget.videoPath != null && !kIsWeb) {
        // Move to temp directory for standardized storage
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'sojorn_video_$timestamp.mp4';
        final tempFile = File('${tempDir.path}/$fileName');

        await File(widget.videoPath!).copy(tempFile.path);

        if (!mounted) return;
        Navigator.pop(
          context,
          SojornMediaResult.video(
            filePath: tempFile.path,
            name: fileName,
          ),
        );
      } else if (widget.videoBytes != null) {
        // Return bytes for web
        if (!mounted) return;
        Navigator.pop(
          context,
          SojornMediaResult.video(
            bytes: widget.videoBytes!,
            name: widget.videoName ?? 'sojorn_edit.mp4',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving video: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildExportOverlay() {
    if (!_isExporting) return const SizedBox.shrink();

    return Container(
      color: const Color(0x8A000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _exportProgress > 0 ? _exportProgress : null,
              color: _brightNavy,
            ),
            const SizedBox(height: 16),
            Text(
              _exportStatus.isNotEmpty ? _exportStatus : 'Exporting...',
              style: const TextStyle(color: SojornColors.basicWhite),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_isInitialized) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
            _videoController!.play();
          }
        });
      },
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            if (!_videoController!.value.isPlaying)
              Icon(
                Icons.play_circle_outline,
                size: 80,
                color: _brightNavy,
              ),
            // Trim handles (basic implementation)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (!_isTrimming) return;
                  // Update start trim position
                },
                child: Container(
                  width: 20,
                  color: _brightNavy.withValues(alpha: 0.3),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 40,
                      color: _brightNavy,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (!_isTrimming) return;
                  // Update end trim position
                },
                child: Container(
                  width: 20,
                  color: _brightNavy.withValues(alpha: 0.3),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 40,
                      color: _brightNavy,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrimControls() {
    if (!_isInitialized) return const SizedBox.shrink();

    final duration = _videoController!.value.duration;
    final trimDuration = _endTrim - _startTrim;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Start: ${_startTrim.inSeconds}s',
              style: GoogleFonts.inter(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
            ),
            Text(
              'End: ${_endTrim.inSeconds}s',
              style: GoogleFonts.inter(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
            ),
            Text(
              'Duration: ${trimDuration.inSeconds}s',
              style: GoogleFonts.inter(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _brightNavy,
            inactiveTrackColor: SojornColors.basicWhite.withValues(alpha: 0.24),
            thumbColor: _brightNavy,
            overlayColor: _brightNavy.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: RangeSlider(
            values: RangeValues(
              _startTrim.inMilliseconds.toDouble(),
              _endTrim.inMilliseconds.toDouble(),
            ),
            min: 0,
            max: duration.inMilliseconds.toDouble(),
            onChanged: (values) {
              setState(() {
                _startTrim = Duration(milliseconds: values.start.toInt());
                _endTrim = Duration(milliseconds: values.end.toInt());
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _isTrimming = !_isTrimming;
                });
              },
              icon: Icon(
                _isTrimming ? Icons.check : Icons.edit,
                color: _isTrimming ? _brightNavy : SojornColors.basicWhite.withValues(alpha: 0.7),
              ),
              tooltip: _isTrimming ? 'Finish Trimming' : 'Enable Trimming',
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () {
                setState(() {
                  _startTrim = Duration.zero;
                  _endTrim = duration;
                });
              },
              icon: Icon(Icons.restore, color: SojornColors.basicWhite.withValues(alpha: 0.7)),
              tooltip: 'Reset Trim',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // For web or bytes, show placeholder
    if (kIsWeb || widget.videoBytes != null) {
      return Scaffold(
        backgroundColor: _matteBlack,
        appBar: AppBar(
          backgroundColor: _matteBlack,
          foregroundColor: SojornColors.basicWhite,
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton(
              onPressed: _isExporting ? null : _saveWithoutEditing,
              style: TextButton.styleFrom(
                foregroundColor: _brightNavy,
              ),
              child: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(SojornColors.basicWhite),
                      ),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library,
                size: 64,
                color: _brightNavy,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Video Editor',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: SojornColors.basicWhite,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Video editing is not supported on web yet.\nYour video will be saved without editing.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: SojornColors.basicWhite.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isExporting ? null : _saveWithoutEditing,
                icon: Icon(_isExporting ? Icons.hourglass_empty : Icons.check),
                label: Text(
                    _isExporting ? 'Processing...' : 'Continue with Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading state
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _matteBlack,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: _brightNavy,
              ),
              const SizedBox(height: 16),
              const Text(
                'Initializing editor...',
                style: TextStyle(color: SojornColors.basicWhite),
              ),
            ],
          ),
        ),
      );
    }

    // Show error state if initialization failed
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: _matteBlack,
        appBar: AppBar(
          backgroundColor: _matteBlack,
          foregroundColor: SojornColors.basicWhite,
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.error,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Failed to initialize video editor',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: SojornColors.basicWhite,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Please try again or use a different video',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: SojornColors.basicWhite.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _saveWithoutEditing,
                icon: const Icon(Icons.save),
                label: const Text('Save Original Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show actual video editor
    return Scaffold(
      backgroundColor: _matteBlack,
      appBar: AppBar(
        backgroundColor: _matteBlack,
        foregroundColor: SojornColors.basicWhite,
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: _isExporting ? null : () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isExporting ? null : _exportVideo,
            style: TextButton.styleFrom(
              foregroundColor: _brightNavy,
            ),
            child: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(SojornColors.basicWhite),
                    ),
                  )
                : const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Video player with trim controls
                Expanded(
                  child: _buildVideoPlayer(),
                ),
                const SizedBox(height: 16),
                // Trim controls
                _buildTrimControls(),
                const SizedBox(height: 16),
                // Video info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SojornColors.basicWhite.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Original: ${_videoController!.value.duration.inSeconds}s',
                        style: GoogleFonts.inter(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
                      ),
                      Text(
                        'Trimmed: ${(_endTrim - _startTrim).inSeconds}s',
                        style: GoogleFonts.inter(
                          color: (_endTrim - _startTrim) <
                                  _videoController!.value.duration
                              ? _brightNavy
                              : SojornColors.basicWhite.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildExportOverlay(),
        ],
      ),
    );
  }
}
