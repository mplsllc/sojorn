import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sojorn/services/video_stitching_service.dart';
import 'package:video_player/video_player.dart';
import '../../../theme/tokens.dart';

import '../../../theme/app_theme.dart';
import 'quip_preview_screen.dart'; // Stage 2

class QuipRecorderScreen extends StatefulWidget {
  const QuipRecorderScreen({super.key});

  @override
  State<QuipRecorderScreen> createState() => _QuipRecorderScreenState();
}

class _QuipRecorderScreenState extends State<QuipRecorderScreen>
    with WidgetsBindingObserver {
  // Config
  static const Duration _maxDuration = Duration(seconds: 10);

  // Camera State
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRearCamera = true;
  bool _isInitializing = true;
  bool _flashOn = false;

  // Recording State
  bool _isRecording = false;
  final List<File> _recordedSegments = [];
  final List<Duration> _segmentDurations = [];
  
  // Timer State
  DateTime? _segmentStartTime;
  Timer? _progressTicker;
  Duration _currentSegmentDuration = Duration.zero;

  // Processing State
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
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() => _isInitializing = true);
    
    final status = await [Permission.camera, Permission.microphone].request();
    if (status[Permission.camera] != PermissionStatus.granted ||
        status[Permission.microphone] != PermissionStatus.granted) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions denied')));
        Navigator.pop(context);
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('No cameras found');
      
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == (_isRearCamera ? CameraLensDirection.back : CameraLensDirection.front),
        orElse: () => _cameras.first
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      await _cameraController!.prepareForVideoRecording();
      
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
    }
  }

  Future<void> _toggleCamera() async {
    if (_isRecording) return;
    setState(() {
      _isRearCamera = !_isRearCamera;
      _isInitializing = true;
    });
    await _cameraController?.dispose();
    _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    try {
      _flashOn = !_flashOn;
      await _cameraController!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Duration get _totalRecordedDuration {
    final committed = _segmentDurations.fold(Duration.zero, (prev, e) => prev + e);
    return committed + _currentSegmentDuration;
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_totalRecordedDuration >= _maxDuration) return;

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _segmentStartTime = DateTime.now();
      });

      _progressTicker = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (!mounted) return;
        final now = DateTime.now();
        setState(() {
          _currentSegmentDuration = now.difference(_segmentStartTime!);
        });

        if (_totalRecordedDuration >= _maxDuration) {
          _stopRecording();
        }
      });
    } catch (e) {
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _progressTicker?.cancel();

    try {
      final file = await _cameraController!.stopVideoRecording();
      
      setState(() {
        _isRecording = false;
        _recordedSegments.add(File(file.path));
        _segmentDurations.add(_currentSegmentDuration);
        _currentSegmentDuration = Duration.zero;
        _segmentStartTime = null;
      });

      // NO Auto-Navigation. Just stop.
    } catch (e) {
    }
  }

  void _deleteLastSegment() {
    if (_recordedSegments.isEmpty) return;
    setState(() {
      _recordedSegments.removeLast();
      _segmentDurations.removeLast();
    });
  }

  Future<void> _finishAndNavigate() async {
    if (_recordedSegments.isEmpty) return;
    
    setState(() => _isProcessing = true);

    try {
      // Stitch segments if multiple
      File? finalFile;
      if (_recordedSegments.length == 1) {
        finalFile = _recordedSegments.first;
      } else {
        finalFile = await VideoStitchingService.stitchVideosLegacy(_recordedSegments);
      }

      if (finalFile != null && mounted) {
        await _cameraController?.pausePreview();
        
        // Navigate to Stage 2: Preview
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuipPreviewScreen(videoFile: finalFile!),
          ),
        ).then((_) {
          _cameraController?.resumePreview();
        });
      } else {
        throw Exception("Stitching failed or returned null");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error processing video: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 10));
    if (video != null) {
      if (mounted) {
         Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuipPreviewScreen(videoFile: File(video.path))),
        );
      }
    }
  }

  Widget _buildProgressBar() {
    return Container(
      height: 6,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SojornColors.basicWhite.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Row(
          children: [
            ..._segmentDurations.map((d) => _buildSegment(d, false)),
            if (_isRecording) _buildSegment(_currentSegmentDuration, true),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(Duration duration, bool isActive) {
    final double percent = duration.inMilliseconds / _maxDuration.inMilliseconds;
    if (percent <= 0) return const SizedBox.shrink();
    
    return Flexible(
      flex: (percent * 1000).toInt(),
      fit: FlexFit.loose,
      child: Container(
        color: isActive ? SojornColors.destructive : AppTheme.brightNavy,
        margin: const EdgeInsets.only(right: 2), 
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _cameraController == null) {
      return const Scaffold(backgroundColor: SojornColors.basicBlack, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: CameraPreview(_cameraController!)),
            if (_isProcessing)
              Container(color: const Color(0x8A000000), child: const Center(child: CircularProgressIndicator())),

            Positioned(
              top: 0, left: 0, right: 0,
              child: Column(
                children: [
                  _buildProgressBar(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: SojornColors.basicWhite),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: SojornColors.basicWhite),
                              onPressed: _toggleFlash,
                            ),
                            IconButton(
                              icon: const Icon(Icons.flip_camera_ios, color: SojornColors.basicWhite),
                              onPressed: _toggleCamera,
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 40, left: 24, right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined, color: SojornColors.basicWhite, size: 28),
                    onPressed: _pickFromGallery,
                  ),
                  
                  GestureDetector(
                    onTap: () {
                      if (_isRecording) _stopRecording(); else _startRecording();
                    },
                    onLongPress: _startRecording,
                    onLongPressUp: _stopRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: _isRecording ? 90 : 80,
                      width: _isRecording ? 90 : 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: SojornColors.basicWhite, width: 4),
                        shape: BoxShape.circle,
                        color: SojornColors.transparent,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isRecording ? SojornColors.destructive : SojornColors.destructive,
                          shape: BoxShape.circle,
                        ),
                        child: _isRecording 
                          ? const Center(child: Icon(Icons.stop, color: SojornColors.basicWhite)) 
                          : null,
                      ),
                    ),
                  ),

                  if (_recordedSegments.isNotEmpty)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.backspace, color: SojornColors.basicWhite),
                          onPressed: _deleteLastSegment,
                        ),
                        const SizedBox(width: 12),
                        FloatingActionButton.small(
                          backgroundColor: AppTheme.brightNavy,
                          onPressed: _finishAndNavigate,
                          child: const Icon(Icons.check, color: SojornColors.basicWhite),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 80), 
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
