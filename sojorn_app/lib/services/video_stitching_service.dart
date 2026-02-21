// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:io';
import 'media/ffmpeg.dart';
import 'package:path_provider/path_provider.dart';

class VideoStitchingService {
  /// Enhanced video stitching with filters, speed control, and text overlays
  /// 
  /// Returns the processed video file, or null if processing failed.
  static Future<File?> stitchVideos(
    List<File> segments,
    List<Duration> segmentDurations,
    String filter,
    double playbackSpeed,
    Map<String, dynamic>? textOverlay, {
    String? audioOverlayPath,
    double audioVolume = 0.5,
  }) async {
    if (segments.isEmpty) return null;
    if (segments.length == 1 && filter == 'none' && playbackSpeed == 1.0 && textOverlay == null) {
      return segments.first;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final outputFile = File('${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.mp4');
      
      // Build FFmpeg filter chain
      List<String> filters = [];
      
      // 1. Speed filter
      if (playbackSpeed != 1.0) {
        filters.add('setpts=${1.0/playbackSpeed}*PTS');
        filters.add('atempo=${playbackSpeed}');
      }
      
      // 2. Visual filters
      switch (filter) {
        case 'grayscale':
          filters.add('colorchannelmixer=.299:.587:.114:0:.299:.587:.114:0:.299:.587:.114');
          break;
        case 'sepia':
          filters.add('colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131');
          break;
        case 'vintage':
          filters.add('curves=vintage');
          break;
        case 'cold':
          filters.add('colorbalance=rs=-0.1:gs=0.05:bs=0.2');
          break;
        case 'warm':
          filters.add('colorbalance=rs=0.2:gs=0.05:bs=-0.1');
          break;
        case 'dramatic':
          filters.add('contrast=1.5:brightness=-0.1:saturation=1.2');
          break;
      }
      
      // 3. Text overlay
      if (textOverlay != null && textOverlay!['text'].toString().isNotEmpty) {
        final text = textOverlay!['text'];
        final size = (textOverlay!['size'] as double).toInt();
        final color = textOverlay!['color'];
        final position = (textOverlay!['position'] as double);
        
        // Position: 0.0 = top, 1.0 = bottom
        final yPos = position == 0.0 ? 'h-th' : 'h-h';
        
        filters.add("drawtext=text='$text':fontsize=$size:fontcolor=$color:x=(w-text_w)/2:y=$yPos:enable='between(t,0,30)'");
      }
      
      // Combine all filters
      String filterString = '';
      if (filters.isNotEmpty) {
        filterString = '-vf "${filters.join(',')}"';
      }
      
      // Build FFmpeg command
      String command;
      
      if (segments.length == 1) {
        // Single video with effects
        command = "-i '${segments.first.path}' $filterString -map_metadata -1 '${outputFile.path}'";
      } else {
        // Multiple videos - stitch first, then apply effects
        final listFile = File('${tempDir.path}/segments_list.txt');
        final buffer = StringBuffer();
        for (final segment in segments) {
          buffer.writeln("file '${segment.path}'");
        }
        await listFile.writeAsString(buffer.toString());

        final tempStitched = File('${tempDir.path}/temp_stitched.mp4');

        // First stitch without effects (metadata stripped at final pass)
        final stitchCommand = "-f concat -safe 0 -i '${listFile.path}' -c copy '${tempStitched.path}'";
        final stitchSession = await FFmpegKit.execute(stitchCommand);
        final stitchReturnCode = await stitchSession.getReturnCode();

        if (!ReturnCode.isSuccess(stitchReturnCode)) {
          return null;
        }

        // Then apply effects to the stitched video, stripping metadata at final output
        command = "-i '${tempStitched.path}' $filterString -map_metadata -1 '${outputFile.path}'";
      }

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getOutput();
        print('FFmpeg error: $logs');
        return null;
      }

      // Audio overlay pass (optional second FFmpeg call to mix in background audio)
      if (audioOverlayPath != null && audioOverlayPath.isNotEmpty) {
        final audioOutputFile = File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.mp4');
        final vol = audioVolume.clamp(0.0, 1.0).toStringAsFixed(2);
        final audioCmd =
            "-i '${outputFile.path}' -i '$audioOverlayPath' "
            "-filter_complex '[1:a]volume=${vol}[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=0' "
            "-map_metadata -1 -c:v copy -shortest '${audioOutputFile.path}'";
        final audioSession = await FFmpegKit.execute(audioCmd);
        final audioCode = await audioSession.getReturnCode();
        if (ReturnCode.isSuccess(audioCode)) {
          return audioOutputFile;
        }
        // If audio mix fails, fall through and return the video without the overlay
        print('Audio overlay mix failed — returning video without audio overlay');
      }

      return outputFile;
    } catch (e) {
      print('Video stitching error: $e');
      return null;
    }
  }

  /// Legacy method for backward compatibility
  static Future<File?> stitchVideosLegacy(List<File> segments) async {
    return stitchVideos(segments, [], 'none', 1.0, null);
  }
}
