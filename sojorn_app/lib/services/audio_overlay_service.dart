// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import 'media/ffmpeg.dart';

class AudioOverlayService {
  /// Mixes audio with video using FFmpeg
  static Future<File?> mixAudioWithVideo(
    File videoFile,
    File? audioFile,
    double volume, // 0.0 to 1.0
    bool fadeIn,
    bool fadeOut,
  ) async {
    if (audioFile == null) return videoFile;

    try {
      final tempDir = await getTemporaryDirectory();
      final outputFile = File('${tempDir.path}/audio_mix_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Build audio filter
      List<String> audioFilters = [];
      
      // Volume adjustment
      if (volume != 1.0) {
        audioFilters.add('volume=${volume}');
      }
      
      // Fade in
      if (fadeIn) {
        audioFilters.add('afade=t=in:st=0:d=1');
      }
      
      // Fade out
      if (fadeOut) {
        audioFilters.add('afade=t=out:st=3:d=1');
      }
      
      String audioFilterString = '';
      if (audioFilters.isNotEmpty) {
        audioFilterString = '-af "${audioFilters.join(',')}"';
      }

      // FFmpeg command to mix audio
      final command = "-i '${videoFile.path}' -i '${audioFile.path}' $audioFilterString -c:v copy -c:a aac -shortest '${outputFile.path}'";
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputFile;
      } else {
        final logs = await session.getOutput();
        print('Audio mixing error: $logs');
        return null;
      }
    } catch (e) {
      print('Audio mixing error: $e');
      return null;
    }
  }

  /// Pick audio file from device
  static Future<File?> pickAudioFile() async {
    try {
      // Request storage permission if needed
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (status != PermissionStatus.granted) {
          return null;
        }
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      print('Audio file picker error: $e');
      return null;
    }
  }

  /// Get audio duration
  static Future<Duration?> getAudioDuration(File audioFile) async {
    try {
      final command = "-i '${audioFile.path}' -f null -";
      final session = await FFmpegKit.execute(command);
      final output = await session.getOutput() ?? '';
      final logs = output.split('\n');

      for (final message in logs) {
        if (message.contains('Duration:')) {
          // Parse duration from FFmpeg output
          final durationMatch = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})').firstMatch(message);
          if (durationMatch != null) {
            final hours = int.parse(durationMatch.group(1)!);
            final minutes = int.parse(durationMatch.group(2)!);
            final seconds = double.parse(durationMatch.group(3)!);
            return Duration(
              hours: hours,
              minutes: minutes,
              seconds: seconds.toInt(),
              milliseconds: ((seconds - seconds.toInt()) * 1000).toInt(),
            );
          }
        }
      }
      return null;
    } catch (e) {
      print('Audio duration error: $e');
      return null;
    }
  }

  /// Built-in music library (demo tracks)
  static List<MusicTrack> getBuiltInTracks() {
    return [
      MusicTrack(
        id: 'upbeat_pop',
        title: 'Upbeat Pop',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 30),
        genre: 'Pop',
        mood: 'Happy',
        isBuiltIn: true,
      ),
      MusicTrack(
        id: 'chill_lofi',
        title: 'Chill Lo-Fi',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 45),
        genre: 'Lo-Fi',
        mood: 'Relaxed',
        isBuiltIn: true,
      ),
      MusicTrack(
        id: 'energetic_dance',
        title: 'Energetic Dance',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 30),
        genre: 'Dance',
        mood: 'Excited',
        isBuiltIn: true,
      ),
      MusicTrack(
        id: 'acoustic_guitar',
        title: 'Acoustic Guitar',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 40),
        genre: 'Acoustic',
        mood: 'Calm',
        isBuiltIn: true,
      ),
      MusicTrack(
        id: 'electronic_beats',
        title: 'Electronic Beats',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 35),
        genre: 'Electronic',
        mood: 'Modern',
        isBuiltIn: true,
      ),
      MusicTrack(
        id: 'cinematic_ambient',
        title: 'Cinematic Ambient',
        artist: 'Sojorn Library',
        duration: const Duration(seconds: 50),
        genre: 'Ambient',
        mood: 'Dramatic',
        isBuiltIn: true,
      ),
    ];
  }
}

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String genre;
  final String mood;
  final bool isBuiltIn;
  final File? audioFile;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.genre,
    required this.mood,
    required this.isBuiltIn,
    this.audioFile,
  });

  MusicTrack copyWith({
    String? id,
    String? title,
    String? artist,
    Duration? duration,
    String? genre,
    String? mood,
    bool? isBuiltIn,
    File? audioFile,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      genre: genre ?? this.genre,
      mood: mood ?? this.mood,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      audioFile: audioFile ?? this.audioFile,
    );
  }
}

class AudioOverlayControls extends StatefulWidget {
  final Function(MusicTrack?) onTrackSelected;
  final Function(double) onVolumeChanged;
  final Function(bool) onFadeInChanged;
  final Function(bool) onFadeOutChanged;

  const AudioOverlayControls({
    super.key,
    required this.onTrackSelected,
    required this.onVolumeChanged,
    required this.onFadeInChanged,
    required this.onFadeOutChanged,
  });

  @override
  State<AudioOverlayControls> createState() => _AudioOverlayControlsState();
}

class _AudioOverlayControlsState extends State<AudioOverlayControls> {
  MusicTrack? _selectedTrack;
  double _volume = 0.5;
  bool _fadeIn = true;
  bool _fadeOut = true;
  List<MusicTrack> _availableTracks = [];

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final builtInTracks = AudioOverlayService.getBuiltInTracks();
    setState(() {
      _availableTracks = builtInTracks;
    });
  }

  Future<void> _pickCustomAudio() async {
    final audioFile = await AudioOverlayService.pickAudioFile();
    if (audioFile != null) {
      final duration = await AudioOverlayService.getAudioDuration(audioFile);
      final customTrack = MusicTrack(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Custom Audio',
        artist: 'User Upload',
        duration: duration ?? const Duration(seconds: 30),
        genre: 'Custom',
        mood: 'User',
        isBuiltIn: false,
        audioFile: audioFile,
      );
      
      setState(() {
        _availableTracks.insert(0, customTrack);
        _selectedTrack = customTrack;
      });
      
      widget.onTrackSelected(customTrack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Audio Overlay',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _pickCustomAudio,
                icon: const Icon(Icons.upload_file, color: Colors.white, size: 16),
                label: const Text('Upload', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Track selection
          if (_availableTracks.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Track',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableTracks.length,
                    itemBuilder: (context, index) {
                      final track = _availableTracks[index];
                      final isSelected = _selectedTrack?.id == track.id;
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTrack = track;
                          });
                          widget.onTrackSelected(track);
                        },
                        child: Container(
                          width: 100,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue : AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: Colors.blue) : null,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                track.isBuiltIn ? Icons.music_note : Icons.audiotrack,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDuration(track.duration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Volume control
          Row(
            children: [
              const Icon(Icons.volume_down, color: Colors.white, size: 20),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(_volume * 100).toInt()}%',
                  activeColor: Colors.blue,
                  inactiveColor: AppTheme.textDisabled,
                  onChanged: (value) {
                    setState(() {
                      _volume = value;
                    });
                    widget.onVolumeChanged(value);
                  },
                ),
              ),
              const Icon(Icons.volume_up, color: Colors.white, size: 20),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Fade controls
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _fadeIn = !_fadeIn;
                    });
                    widget.onFadeInChanged(_fadeIn);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _fadeIn ? Colors.blue : AppTheme.textDisabled,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.volume_up,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Fade In',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _fadeOut = !_fadeOut;
                    });
                    widget.onFadeOutChanged(_fadeOut);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _fadeOut ? Colors.blue : AppTheme.textDisabled,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.volume_down,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Fade Out',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
