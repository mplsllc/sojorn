// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'media/ffmpeg.dart';

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
    if (!await rawFile.exists()) {
      throw Exception('Video file does not exist');
    }

    final fileSize = await rawFile.length();
    const maxSize = 50 * 1024 * 1024; // 50MB limit for videos

    if (fileSize > maxSize) {
      throw Exception('Video size exceeds 50MB limit');
    }

    final fileName = rawFile.path.split('/').last.toLowerCase();
    final extension = fileName.split('.').last;
    const validExtensions = {'mp4', 'mov', 'webm'};

    if (!validExtensions.contains(extension)) {
      throw Exception('Unsupported video format: $extension');
    }

    // Strip all metadata (GPS, device info, timestamps) via FFmpeg remux — no re-encode.
    try {
      final tempDir = Directory.systemTemp;
      final output = File(
        '${tempDir.path}${Platform.pathSeparator}stripped_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final session = await FFmpegKit.execute(
        '-y -i "${rawFile.path}" -map_metadata -1 -c copy "${output.path}"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && await output.exists()) {
        return output;
      }
    } catch (_) {
      // FFmpeg unavailable — fall through and return original
    }

    return rawFile;
  }
}
