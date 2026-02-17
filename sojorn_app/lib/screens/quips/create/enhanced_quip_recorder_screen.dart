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
import '../../audio/audio_library_screen.dart';
import 'quip_preview_screen.dart';

class EnhancedQuipRecorderScreen extends StatefulWidget {
  const EnhancedQuipRecorderScreen({super.key});

  @override
  State<EnhancedQuipRecorderScreen> createState() => _EnhancedQuipRecorderScreenState();
}

class _EnhancedQuipRecorderScreenState extends State<EnhancedQuipRecorderScreen>
    with WidgetsBindingObserver {
  // Config
  static const Duration _maxDuration = Duration(seconds: 60); // Increased for multi-segment

  // Camera State
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRearCamera = true;
  bool _isInitializing = true;
  bool _flashOn = false;

  // Recording State
  bool _isRecording = false;
  bool _isPaused = false;
  final List<File> _recordedSegments = [];
  final List<Duration> _segmentDurations = [];
  
  // Timer State
  DateTime? _segmentStartTime;
  Timer? _progressTicker;
  Duration _currentSegmentDuration = Duration.zero;

  // Speed Control
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.5, 1.0, 2.0, 3.0];

  // Effects and Filters
  String _selectedFilter = 'none';
  final List<String> _filters = ['none', 'grayscale', 'sepia', 'vintage', 'cold', 'warm', 'dramatic'];
  
  // Text Overlay
  bool _showTextOverlay = false;
  String _overlayText = '';
  double _textSize = 24.0;
  Color _textColor = Colors.white;
  double _textPositionY = 0.8; // 0=top, 1=bottom

  // Audio Overlay
  AudioTrack? _selectedAudio;
  double _audioVolume = 0.5;

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
      
      setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera initialization failed')));
        Navigator.pop(context);
      }
    }
  }

  Duration get _totalRecordedDuration {
    Duration total = Duration.zero;
    for (final duration in _segmentDurations) {
      total += duration;
    }
    return total + _currentSegmentDuration;
  }

  // Enhanced recording methods
  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_totalRecordedDuration >= _maxDuration) return;
    if (_isPaused) {
      _resumeRecording();
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _segmentStartTime = DateTime.now();
        _currentSegmentDuration = Duration.zero;
      });

      _progressTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_segmentStartTime != null) {
          setState(() {
            _currentSegmentDuration = DateTime.now().difference(_segmentStartTime!);
          });
        }
      });

      // Auto-stop at max duration
      Timer(const Duration(milliseconds: 100), () {
        if (_totalRecordedDuration >= _maxDuration) {
          _stopRecording();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start recording')));
      }
    }
  }

  Future<void> _pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    
    try {
      await _cameraController!.pauseVideoRecording();
      setState(() => _isPaused = true);
      _progressTicker?.cancel();
      
      // Save current segment
      _segmentDurations.add(_currentSegmentDuration);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pause recording')));
      }
    }
  }

  Future<void> _resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    
    try {
      await _cameraController!.resumeVideoRecording();
      setState(() {
        _isPaused = false;
        _segmentStartTime = DateTime.now();
        _currentSegmentDuration = Duration.zero;
      });

      _progressTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_segmentStartTime != null) {
          setState(() {
            _currentSegmentDuration = DateTime.now().difference(_segmentStartTime!);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to resume recording')));
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    _progressTicker?.cancel();
    
    try {
      final videoFile = await _cameraController!.stopVideoRecording();
      
      if (videoFile != null) {
        setState(() => _isRecording = false);
        _isPaused = false;

        // Add segment if it has content
        if (_currentSegmentDuration.inMilliseconds > 500) { // Minimum 0.5 seconds
          _recordedSegments.add(File(videoFile.path));
          _segmentDurations.add(_currentSegmentDuration);
        }
        
        // Auto-process if we have segments
        if (_recordedSegments.isNotEmpty) {
          _processVideo();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to stop recording')));
      }
    }
  }

  Future<void> _processVideo() async {
    if (_recordedSegments.isEmpty || _isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final finalFile = await VideoStitchingService.stitchVideos(
        _recordedSegments,
        _segmentDurations,
        _selectedFilter,
        _playbackSpeed,
        _showTextOverlay ? {
          'text': _overlayText,
          'size': _textSize,
          'color': '#${_textColor.value.toRadixString(16).padLeft(8, '0')}',
          'position': _textPositionY,
        } : null,
        audioOverlayPath: _selectedAudio?.path,
        audioVolume: _audioVolume,
      );

      if (finalFile != null && mounted) {
        await _cameraController?.pausePreview();
        
        // Navigate to enhanced preview
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EnhancedQuipPreviewScreen(
              videoFile: finalFile!,
              segments: _recordedSegments,
              durations: _segmentDurations,
              filter: _selectedFilter,
              speed: _playbackSpeed,
              textOverlay: _showTextOverlay ? {
                'text': _overlayText,
                'size': _textSize,
                'color': _textColor,
                'position': _textPositionY,
              } : null,
            ),
          ),
        ).then((_) {
          _cameraController?.resumePreview();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video processing failed')));
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _toggleCamera() async {
    if (_cameras.length < 2) return;
    
    setState(() {
      _isRearCamera = !_isRearCamera;
      _isInitializing = true;
    });

    try {
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == (_isRearCamera ? CameraLensDirection.back : CameraLensDirection.front),
        orElse: () => _cameras.first
      );

      await _cameraController?.dispose();
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      setState(() => _isInitializing = false);
    } catch (e) {
      setState(() => _isInitializing = false);
    }
  }

  void _toggleFlash() async {
    if (_cameraController == null) return;
    
    try {
      if (_flashOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
      setState(() => _flashOn = !_flashOn);
    } catch (e) {
      // Flash not supported
    }
  }

  void _clearSegments() {
    setState(() {
      _recordedSegments.clear();
      _segmentDurations.clear();
      _currentSegmentDuration = Duration.zero;
    });
  }

  Future<void> _pickAudio() async {
    final result = await Navigator.push<AudioTrack>(
      context,
      MaterialPageRoute(builder: (_) => const AudioLibraryScreen()),
    );
    if (result != null && mounted) {
      setState(() => _selectedAudio = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text('Initializing camera...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),
          
          // Controls overlay
          Positioned.fill(
            child: Column(
              children: [
                // Top controls
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Speed control
                      if (_isRecording || _recordedSegments.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _speedOptions.map((speed) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: GestureDetector(
                                onTap: () => setState(() => _playbackSpeed = speed),
                                child: Text(
                                  '${speed}x',
                                  style: TextStyle(
                                    color: _playbackSpeed == speed ? AppTheme.navyBlue : Colors.white,
                                    fontWeight: _playbackSpeed == speed ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      
                      // Filter selector
                      if (_isRecording || _recordedSegments.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Wrap(
                            spacing: 8,
                            children: _filters.map((filter) => GestureDetector(
                              onTap: () => setState(() => _selectedFilter = filter),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _selectedFilter == filter ? AppTheme.navyBlue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  filter,
                                  style: TextStyle(
                                    color: _selectedFilter == filter ? Colors.white : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Bottom controls
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Progress bar
                      if (_isRecording || _isPaused)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: LinearProgressIndicator(
                            value: _totalRecordedDuration.inMilliseconds / _maxDuration.inMilliseconds,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isPaused ? Colors.orange : Colors.red,
                            ),
                          ),
                        ),
                      
                      // Duration and controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Duration
                          Text(
                            _formatDuration(_totalRecordedDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          
                          // Pause/Resume button
                          if (_isRecording)
                            GestureDetector(
                              onTap: _isPaused ? _resumeRecording : _pauseRecording,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _isPaused ? Colors.orange : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPaused ? Icons.play_arrow : Icons.pause,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          
                          // Stop button
                          if (_isRecording)
                            GestureDetector(
                              onTap: _stopRecording,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.stop,
                                  color: Colors.black,
                                  size: 24,
                                ),
                              ),
                            ),
                          
                          // Clear segments button
                          if (_recordedSegments.isNotEmpty && !_isRecording)
                            GestureDetector(
                              onTap: _clearSegments,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          
                          // Record button
                          if (!_isRecording)
                            GestureDetector(
                              onLongPress: _startRecording,
                              onTap: _startRecording,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                      
                      // Audio track chip (shown when audio is selected)
                      if (_selectedAudio != null && !_isRecording)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Chip(
                                backgroundColor: Colors.deepPurple.shade700,
                                avatar: const Icon(Icons.music_note, color: Colors.white, size: 16),
                                label: Text(
                                  _selectedAudio!.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, color: Colors.white70, size: 16),
                                onDeleted: () => setState(() => _selectedAudio = null),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: Slider(
                                  value: _audioVolume,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: Colors.deepPurple.shade300,
                                  inactiveColor: Colors.white24,
                                  onChanged: (v) => setState(() => _audioVolume = v),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Additional controls row
                      if (_recordedSegments.isNotEmpty && !_isRecording)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Text overlay toggle
                            GestureDetector(
                              onTap: () => setState(() => _showTextOverlay = !_showTextOverlay),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _showTextOverlay ? AppTheme.navyBlue : Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.text_fields,
                                  color: _showTextOverlay ? Colors.white : Colors.white70,
                                  size: 20,
                                ),
                              ),
                            ),

                            // Music / audio overlay button
                            GestureDetector(
                              onTap: _pickAudio,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _selectedAudio != null ? Colors.deepPurple : Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: _selectedAudio != null ? Colors.white : Colors.white70,
                                  size: 20,
                                ),
                              ),
                            ),

                            // Camera toggle
                            GestureDetector(
                              onTap: _toggleCamera,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isRearCamera ? Icons.camera_rear : Icons.camera_front,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),

                            // Flash toggle
                            GestureDetector(
                              onTap: _toggleFlash,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _flashOn ? Colors.yellow : Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _flashOn ? Icons.flash_on : Icons.flash_off,
                                  color: (_flashOn ? Colors.black : Colors.white),
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Text overlay editor (shown when enabled)
          if (_showTextOverlay && !_isRecording)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Add text overlay...',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() => _overlayText = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Size selector
                        Expanded(
                          child: Slider(
                            value: _textSize,
                            min: 12,
                            max: 48,
                            divisions: 4,
                            label: '${_textSize.toInt()}',
                            activeColor: AppTheme.navyBlue,
                            inactiveColor: Colors.white24,
                            onChanged: (value) => setState(() => _textSize = value),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Position selector
                        Expanded(
                          child: Slider(
                            value: _textPositionY,
                            min: 0.0,
                            max: 1.0,
                            label: _textPositionY == 0.0 ? 'Top' : 'Bottom',
                            activeColor: AppTheme.navyBlue,
                            inactiveColor: Colors.white24,
                            onChanged: (value) => setState(() => _textPositionY = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Color picker
                    Row(
                      children: [
                        _buildColorButton(Colors.white),
                        _buildColorButton(Colors.black),
                        _buildColorButton(Colors.red),
                        _buildColorButton(Colors.blue),
                        _buildColorButton(Colors.green),
                        _buildColorButton(Colors.yellow),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Processing video...', style: TextStyle(color: Colors.white)),
                    Text('Applying effects and stitching segments...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildColorButton(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _textColor = color),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: _textColor == color ? Border.all(color: Colors.white) : null,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// Enhanced preview screen
class EnhancedQuipPreviewScreen extends StatefulWidget {
  final File videoFile;
  final List<File> segments;
  final List<Duration> durations;
  final String filter;
  final double speed;
  final Map<String, dynamic>? textOverlay;

  const EnhancedQuipPreviewScreen({
    super.key,
    required this.videoFile,
    required this.segments,
    required this.durations,
    this.filter = 'none',
    this.speed = 1.0,
    this.textOverlay,
  });

  @override
  State<EnhancedQuipPreviewScreen> createState() => _EnhancedQuipPreviewScreenState();
}

class _EnhancedQuipPreviewScreenState extends State<EnhancedQuipPreviewScreen> {
  late VideoPlayerController _videoController;
  bool _isPlaying = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.file(widget.videoFile);
    
    _videoController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    await _videoController.initialize();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _isPlaying = !_isPlaying;
              });
              if (_isPlaying) {
                _videoController.pause();
              } else {
                _videoController.play();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              // Return to recorder with the processed video
              Navigator.pop(context, widget.videoFile);
            },
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Stack(
              children: [
                VideoPlayer(_videoController),
                
                // Text overlay
                if (widget.textOverlay != null)
                  Positioned(
                    bottom: 50 + (widget.textOverlay!['position'] as double) * 300,
                    left: 16,
                    right: 16,
                    child: Text(
                      widget.textOverlay!['text'],
                      style: TextStyle(
                        color: Color(int.parse(widget.textOverlay!['color'])),
                        fontSize: widget.textOverlay!['size'] as double,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                
                // Controls overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () {
                          setState(() {
                            _isPlaying = !_isPlaying;
                          });
                          if (_isPlaying) {
                            _videoController.pause();
                          } else {
                            _videoController.play();
                          }
                        },
                      ),
                      Text(
                        '${widget.filter} • ${widget.speed}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
