import 'dart:io';
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
    File videoFile,
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

      // Generate thumbnail using FFmpeg
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = '${tempDir.path}/${timestamp}_thumb.jpg';

      final ss = thumbnailTimestampMs != null 
        ? (thumbnailTimestampMs / 1000.0).toStringAsFixed(3)
        : '00:00:01';

      final session = await FFmpegKit.execute(
        '-y -ss $ss -i "${videoFile.path}" -vframes 1 -q:v 2 "$thumbnailPath"'
      );
      
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        throw Exception('Failed to generate thumbnail via FFmpeg');
      }

      final thumbnail = File(thumbnailPath);
      if (!await thumbnail.exists()) {
        throw Exception('Thumbnail file mismatch');
      }

      state = state.copyWith(progress: 0.1);

      final uploadService = ImageUploadService();
      
      // Upload video to Go Backend / R2
      final videoUrl = await uploadService.uploadVideo(
        videoFile,
        onProgress: (p) => state = state.copyWith(progress: 0.1 + (p * 0.4)),
      );

      state = state.copyWith(progress: 0.5);


      // Upload thumbnail to Go Backend / R2
      String? thumbnailUrl;
      try {
        thumbnailUrl = await uploadService.uploadImage(
          thumbnail,
          onProgress: (p) => state = state.copyWith(progress: 0.5 + (p * 0.3)),
        );
      } catch (e) {
        // Continue without thumbnail - video is more important
      }

      state = state.copyWith(progress: 0.8);

      // Publish post via Go API
      await ApiService.instance.publishPost(
        body: caption.isNotEmpty ? caption : ' ',
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        categoryId: null, // Default
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
