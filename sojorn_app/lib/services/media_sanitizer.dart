import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

class MediaSanitizer {
  static Future<File> sanitizeImage(File rawFile) async {
    final tempDir = Directory.systemTemp;
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}sanitized_${DateTime.now().microsecondsSinceEpoch}.jpg';

    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        rawFile.absolute.path,
        targetPath,
        quality: 88,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );

      if (result != null) {
        return File(result.path);
      }
    } on MissingPluginException {
      // Fall through to pure Dart fallback when native plugin isn't available.
    }

    final bytes = await rawFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to sanitize image');
    }

    final sanitized = img.encodeJpg(decoded, quality: 88);
    final output = File(targetPath);
    await output.writeAsBytes(sanitized, flush: true);
    return output;
  }

  static Future<File> sanitizeVideo(File rawFile) async {
    // For videos, we just validate and return the original file
    // Video processing is handled by the video compression library
    // This method ensures the file exists and is readable

    if (!await rawFile.exists()) {
      throw Exception('Video file does not exist');
    }

    final fileSize = await rawFile.length();
    const maxSize = 50 * 1024 * 1024; // 50MB limit for videos

    if (fileSize > maxSize) {
      throw Exception('Video size exceeds 50MB limit');
    }

    // Check if it's a valid video file by extension
    final fileName = rawFile.path.split('/').last.toLowerCase();
    final extension = fileName.split('.').last;
    const validExtensions = {'mp4', 'mov', 'webm'};

    if (!validExtensions.contains(extension)) {
      throw Exception('Unsupported video format: $extension');
    }

    // Return the original file as videos don't need sanitization like images
    return rawFile;
  }
}
