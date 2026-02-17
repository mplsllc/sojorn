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
    Map<String, dynamic>? textOverlay,
  ) async {
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
        command = "-i '${segments.first.path}' $filterString '${outputFile.path}'";
      } else {
        // Multiple videos - stitch first, then apply effects
        final listFile = File('${tempDir.path}/segments_list.txt');
        final buffer = StringBuffer();
        for (final segment in segments) {
          buffer.writeln("file '${segment.path}'");
        }
        await listFile.writeAsString(buffer.toString());
        
        final tempStitched = File('${tempDir.path}/temp_stitched.mp4');
        
        // First stitch without effects
        final stitchCommand = "-f concat -safe 0 -i '${listFile.path}' -c copy '${tempStitched.path}'";
        final stitchSession = await FFmpegKit.execute(stitchCommand);
        final stitchReturnCode = await stitchSession.getReturnCode();
        
        if (!ReturnCode.isSuccess(stitchReturnCode)) {
          return null;
        }
        
        // Then apply effects to the stitched video
        command = "-i '${tempStitched.path}' $filterString '${outputFile.path}'";
      }
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputFile;
      } else {
        final logs = await session.getOutput();
        print('FFmpeg error: $logs');
        return null;
      }
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
