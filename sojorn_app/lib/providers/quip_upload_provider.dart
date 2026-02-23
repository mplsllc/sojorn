// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/media/ffmpeg.dart';
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/image_upload_service.dart';
import 'feed_refresh_provider.dart';

// Define the state class
class QuipUploadState {
  final bool isUploading;
  final double progress;
  final String? error;
  final String? successMessage;

  QuipUploadState({
    required this.isUploading,
    required this.progress,
    this.error,
    this.successMessage,
  });

  QuipUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return QuipUploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
    );
  }
}

class QuipUploadNotifier extends Notifier<QuipUploadState> {
  @override
  QuipUploadState build() {
    return QuipUploadState(isUploading: false, progress: 0.0);
  }

  Future<void> startUpload(
    XFile videoXFile,
    String caption, {
    double? thumbnailTimestampMs,
    String? overlayJson,
  }) async {
    try {
      state = state.copyWith(
          isUploading: true, progress: 0.0, error: null, successMessage: null);

      final auth = AuthService.instance;
      final uid = auth.currentUser?.id;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final uploadService = ImageUploadService();
      String? thumbnailUrl;

      // Generate thumbnail using FFmpeg — mobile only (ffmpeg_kit is not available on web)
      if (!kIsWeb) {
        try {
          final tempDir = await getTemporaryDirectory();
          final thumbnailPath = '${tempDir.path}/${timestamp}_thumb.jpg';
          final ss = thumbnailTimestampMs != null
              ? (thumbnailTimestampMs / 1000.0).toStringAsFixed(3)
              : '00:00:01';

          final session = await FFmpegKit.execute(
              '-y -ss $ss -i "${videoXFile.path}" -vframes 1 -q:v 2 "$thumbnailPath"');
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            final thumbnail = File(thumbnailPath);
            if (thumbnail.existsSync()) {
              thumbnailUrl = await uploadService.uploadImage(
                thumbnail,
                onProgress: (p) =>
                    state = state.copyWith(progress: 0.1 + (p * 0.3)),
              );
            }
          }
        } catch (_) {
          // Thumbnail is optional — continue without it
        }
      }

      state = state.copyWith(progress: 0.4);

      // Upload video (uses XFile — works on both mobile and web)
      final videoUrl = await uploadService.uploadVideoXFile(
        videoXFile,
        onProgress: (p) => state = state.copyWith(progress: 0.4 + (p * 0.5)),
      );

      state = state.copyWith(progress: 0.9);

      // Publish post via Go API
      await ApiService.instance.publishPost(
        body: caption.isNotEmpty ? caption : ' ',
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        categoryId: null,
        overlayJson: overlayJson,
      );

      // Trigger feed refresh
      ref.read(feedRefreshProvider.notifier).increment();

      state = state.copyWith(
          isUploading: false,
          progress: 1.0,
          successMessage: 'Upload successful');

      // Auto-reset after 3 seconds so UI goes back to + button
      Future.delayed(const Duration(seconds: 3), () {
        if (state.progress == 1.0 && !state.isUploading) {
          state = QuipUploadState(isUploading: false, progress: 0.0);
        }
      });
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
    }
  }
}

// Create the provider using the new Riverpod 3.2.0+ syntax
final quipUploadProvider =
    NotifierProvider<QuipUploadNotifier, QuipUploadState>(
  QuipUploadNotifier.new,
);
