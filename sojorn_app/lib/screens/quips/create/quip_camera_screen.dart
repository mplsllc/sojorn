// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../screens/audio/audio_library_screen.dart';
import '../../../theme/tokens.dart';
import '../../../theme/app_theme.dart';
import 'quip_decorate_screen.dart';

/// Stage 1 of the new Quip creation flow.
///
/// Full-screen camera preview with:
/// - Pre-record sound selection (top-center)
/// - Flash + flip camera controls (top-right)
/// - 10 s progress-ring record button (bottom-center)
///   Tap = start/stop toggle; Hold = hold-to-record
///
/// On stop (or auto-stop at 10 s), navigates to [QuipDecorateScreen].
class QuipCameraScreen extends StatefulWidget {
  const QuipCameraScreen({super.key});

  @override
  State<QuipCameraScreen> createState() => _QuipCameraScreenState();
}

class _QuipCameraScreenState extends State<QuipCameraScreen>
    with WidgetsBindingObserver {
  static const Duration _maxDuration = Duration(seconds: 10);
  static const Duration _tickInterval = Duration(milliseconds: 30);

  // Camera
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isRearCamera = true;
  bool _isInitializing = true;
  bool _flashOn = false;

  // Recording
  bool _isRecording = false;
  double _progress = 0.0; // 0.0–1.0
  Timer? _progressTicker;
  Timer? _autoStopTimer;
  DateTime? _recordStart;

  // Pre-record audio
  AudioTrack? _selectedAudio;

  // Processing (brief moment between stop and navigate)
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTicker?.cancel();
    _autoStopTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ─── Camera init ───────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() => _isInitializing = true);

    if (!kIsWeb) {
      final status =
          await [Permission.camera, Permission.microphone].request();
      if (status[Permission.camera] != PermissionStatus.granted ||
          status[Permission.microphone] != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera & microphone access required')),
          );
          Navigator.pop(context);
        }
        return;
      }
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('No cameras found');

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection ==
            (_isRearCamera
                ? CameraLensDirection.back
                : CameraLensDirection.front),
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: kIsWeb ? ImageFormatGroup.unknown : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!kIsWeb) await _cameraController!.prepareForVideoRecording();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _toggleCamera() async {
    if (_isRecording) return;
    setState(() {
      _isRearCamera = !_isRearCamera;
      _isInitializing = true;
    });
    await _cameraController?.dispose();
    _cameraController = null;
    _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    try {
      _flashOn = !_flashOn;
      await _cameraController!
          .setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  // ─── Audio ─────────────────────────────────────────────────────────────────

  Future<void> _pickSound() async {
    final track = await Navigator.push<AudioTrack>(
      context,
      MaterialPageRoute(builder: (_) => const AudioLibraryScreen()),
    );
    if (track != null && mounted) {
      setState(() => _selectedAudio = track);
    }
  }

  // ─── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      _recordStart = DateTime.now();
      _autoStopTimer = Timer(_maxDuration, _stopRecording);
      _progressTicker =
          Timer.periodic(_tickInterval, (_) => _updateProgress());
      if (mounted) setState(() => _isRecording = true);
    } catch (_) {}
  }

  void _updateProgress() {
    if (!mounted || _recordStart == null) return;
    final elapsed = DateTime.now().difference(_recordStart!);
    setState(() {
      _progress =
          (elapsed.inMilliseconds / _maxDuration.inMilliseconds).clamp(0.0, 1.0);
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _progressTicker?.cancel();
    _autoStopTimer?.cancel();

    try {
      final xfile = await _cameraController!.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _progress = 0.0;
        _isProcessing = true;
      });
      await _cameraController?.pausePreview();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuipDecorateScreen(
              videoXFile: xfile,
              preloadedAudio: _selectedAudio,
            ),
          ),
        );
        // Guard against disposed controller (lifecycle change while on next screen)
        if (mounted && _cameraController != null && _cameraController!.value.isInitialized) {
          await _cameraController!.resumePreview();
        }
        if (mounted) setState(() => _isProcessing = false);
      }
    } catch (_) {
      if (mounted) setState(() {_isRecording = false; _progress = 0.0; _isProcessing = false;});
    }
  }

  void _onRecordTap() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _cameraController == null) {
      return const Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(child: CircularProgressIndicator(color: SojornColors.basicWhite)),
      );
    }

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen camera preview
          CameraPreview(_cameraController!),

          // Processing overlay
          if (_isProcessing)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(child: CircularProgressIndicator(color: SojornColors.basicWhite)),
            ),

          // ── Top bar ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Close
                      IconButton(
                        icon: const Icon(Icons.close, color: SojornColors.basicWhite),
                        onPressed: () => Navigator.pop(context),
                      ),
                      // Add Sound (center)
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            onTap: _pickSound,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                border: Border.all(color: SojornColors.basicWhite.withValues(alpha: 0.7)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.music_note, color: SojornColors.basicWhite, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedAudio != null
                                        ? _selectedAudio!.title
                                        : 'Add Sound',
                                    style: const TextStyle(
                                      color: SojornColors.basicWhite,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Flash + Flip
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _flashOn ? Icons.flash_on : Icons.flash_off,
                              color: SojornColors.basicWhite,
                            ),
                            onPressed: _toggleFlash,
                          ),
                          IconButton(
                            icon: const Icon(Icons.flip_camera_ios, color: SojornColors.basicWhite),
                            onPressed: _toggleCamera,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Record button (bottom-center) ─────────────────────────────────
          Positioned(
            bottom: 56,
            left: 0,
            right: 0,
            child: Center(child: _buildRecordButton()),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _onRecordTap,
      onLongPress: _startRecording,
      onLongPressUp: _stopRecording,
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                value: _isRecording ? _progress : 0.0,
                strokeWidth: 4,
                backgroundColor: SojornColors.basicWhite.withValues(alpha: 0.3),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(SojornColors.destructive),
              ),
            ),
            // Inner solid circle (slightly smaller)
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: _isRecording
                    ? SojornColors.destructive
                    : SojornColors.destructive,
                shape: BoxShape.circle,
                border: Border.all(
                  color: SojornColors.basicWhite,
                  width: _isRecording ? 0 : 3,
                ),
              ),
              child: _isRecording
                  ? const Icon(Icons.stop_rounded,
                      color: SojornColors.basicWhite, size: 32)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
