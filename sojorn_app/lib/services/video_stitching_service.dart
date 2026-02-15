import 'dart:io';
import 'media/ffmpeg.dart';
import 'package:path_provider/path_provider.dart';

class VideoStitchingService {
  /// Stitches multiple video files into a single video file using FFmpeg.
  /// 
  /// Returns the stitched file, or null if stitching failed or input is empty.
  static Future<File?> stitchVideos(List<File> segments) async {
    if (segments.isEmpty) return null;
    if (segments.length == 1) return segments.first;

    try {
      // 1. Create a temporary file listing all segments for FFmpeg concat demuxer
      final tempDir = await getTemporaryDirectory();
      final listFile = File('${tempDir.path}/segments_list.txt');
      
      final buffer = StringBuffer();
      for (final segment in segments) {
        // FFmpeg requires safe paths (escaping special chars might be needed, but usually basic paths are fine)
        // IMPORTANT: pathways in list file for concat demuxer must be absolute.
        buffer.writeln("file '${segment.path}'");
      }
      await listFile.writeAsString(buffer.toString());

      // 2. Define output path
      final outputFile = File('${tempDir.path}/stitched_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // 3. Execute FFmpeg command
      // -f concat: format
      // -safe 0: allow unsafe paths (required for absolute paths)
      // -i listFile: input list
      // -c copy: stream copy (fast, no re-encoding)
      final command = "-f concat -safe 0 -i '${listFile.path}' -c copy '${outputFile.path}'";
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputFile;
      } else {
        // Fallback: return the last segment or first one to at least save something?
        // For strict correctness, return null or throw. 
        // Let's print logs.
        final logs = await session.getOutput();
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
