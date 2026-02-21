// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:image/image.dart' as img;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'media_sanitizer.dart';
import '../config/api_config.dart';
import '../models/image_filter.dart';
import 'auth_service.dart';

/// Result of an image upload operation
class UploadResult {
  final String uploadUrl;
  final String publicUrl;
  final String fileName;
  final int fileSize;
  final int? width;
  final int? height;

  const UploadResult({
    required this.uploadUrl,
    required this.publicUrl,
    required this.fileName,
    required this.fileSize,
    this.width,
    this.height,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    final signedUrl = json['signedUrl'] ?? json['signed_url'];
    final resolvedPublicUrl = signedUrl ?? json['publicUrl'] ?? json['public_url'];

    return UploadResult(
      uploadUrl: (json['uploadUrl'] ?? json['upload_url']) as String,
      publicUrl: (resolvedPublicUrl ?? '') as String,
      fileName: (json['fileName'] ?? json['file_name'] ?? '') as String,
      fileSize: (json['fileSize'] ?? json['file_size'] ?? 0) as int,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uploadUrl': uploadUrl,
      'publicUrl': publicUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'width': width,
      'height': height,
    };
  }
}

/// Progress callback for upload operations
typedef UploadProgressCallback = void Function(double progress);

/// Service for uploading images AND videos to Cloudflare R2 via Go Backend
class ImageUploadService {
  final AuthService _auth = AuthService.instance;
  final _storage = const FlutterSecureStorage();

  /// Get the current authentication token
  Future<String?> _getAuthToken() async {
    return _auth.accessToken;
  }

  /// Default upload settings — optimized for mobile-first feed
  static const int defaultMaxWidth = 1080;
  static const int defaultMaxHeight = 1350;
  static const int defaultQuality = 85;

  // =========================================================
  // NEW: Streamed Video Upload (Prevents OutOfMemory Errors)
  // =========================================================
  Future<String> uploadVideo(
    File videoFile, {
    UploadProgressCallback? onProgress,
  }) async {
    final token = await _getAuthToken();
    if (token == null) {
      throw UploadException('Not authenticated. Please sign in again.');
    }

    // Strip metadata (GPS, device info, timestamps) before upload
    final sanitized = await MediaSanitizer.sanitizeVideo(videoFile);

    // Use Go API upload endpoint with R2 integration
    final uri = Uri.parse('${ApiConfig.baseUrl}/upload');

    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $token';

    // CRITICAL: Use fromPath to stream from disk instead of loading into memory
    request.files.add(await http.MultipartFile.fromPath(
      'media', // Field name matches upload-media
      sanitized.path,
      contentType: http_parser.MediaType.parse('video/mp4'),
    ));

    request.fields['type'] = 'video';
    request.fields['fileName'] = sanitized.path.split('/').last;

    onProgress?.call(0.1);

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      onProgress?.call(1.0);

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        throw UploadException(errorData['message'] ?? 'Upload failed');
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      // Return publicUrl or signedUrl depending on your function response
      final url = (responseData['publicUrl'] ?? responseData['signedUrl']) as String;
      return _fixR2Url(url);
    } catch (e) {
      throw UploadException('Video upload failed: $e');
    }
  }

  /// Uploads a video from an [XFile] — works on both mobile and web.
  ///
  /// On mobile, delegates to [uploadVideo] which streams from disk and sanitizes.
  /// On web, reads bytes from the blob URL and uploads via [MultipartFile.fromBytes].
  Future<String> uploadVideoXFile(
    XFile xFile, {
    UploadProgressCallback? onProgress,
  }) async {
    if (!kIsWeb) {
      // Mobile: use the existing efficient streaming path
      return uploadVideo(File(xFile.path), onProgress: onProgress);
    }

    // Web: read the blob into memory and multipart-upload it
    final token = await _getAuthToken();
    if (token == null) throw UploadException('Not authenticated. Please sign in again.');

    final bytes = await xFile.readAsBytes();
    final uri = Uri.parse('${ApiConfig.baseUrl}/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'media',
      bytes,
      filename: xFile.name.isNotEmpty ? xFile.name : 'video.webm',
      contentType: http_parser.MediaType.parse('video/webm'),
    ));
    request.fields['type'] = 'video';
    request.fields['fileName'] = xFile.name.isNotEmpty ? xFile.name : 'video.webm';

    onProgress?.call(0.5);
    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      onProgress?.call(1.0);
      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        throw UploadException(errorData['message'] ?? 'Upload failed');
      }
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final url = (responseData['publicUrl'] ?? responseData['signedUrl']) as String;
      return _fixR2Url(url);
    } catch (e) {
      throw UploadException('Video upload failed: $e');
    }
  }

  // =========================================================
  // Existing Image Logic (Preserved)
  // =========================================================

  /// Uploads an image file with optional filtering
  Future<String> uploadImage(
    File imageFile, {
    ImageFilter? filter,
    int maxWidth = defaultMaxWidth,
    int maxHeight = defaultMaxHeight,
    int quality = defaultQuality,
    UploadProgressCallback? onProgress,
  }) async {
    // 1. Auth Check
    final token = await _getAuthToken();
    if (token == null) {
      throw UploadException('Not authenticated. Please sign in again.');
    }

    File sanitizedFile;
    bool useRawUpload = false;
    try {
      sanitizedFile = await MediaSanitizer.sanitizeImage(imageFile);
    } catch (e) {
      final message = e.toString();
      if (message.contains('Unsupported operation') || message.contains('_Namespace')) {
        // Fallback: upload original bytes without processing for unsupported formats.
        useRawUpload = true;
        sanitizedFile = imageFile;
      } else {
        throw UploadException('Image sanitization failed: $e');
      }
    }

    final fileName = sanitizedFile.path.split('/').last;
    final contentType = useRawUpload ? _contentTypeForFileName(fileName) : 'image/jpeg';

    // 2. Process image with filter if provided
    Uint8List fileBytes;

    if (useRawUpload) {
      fileBytes = await sanitizedFile.readAsBytes();
    } else if (filter != null && filter.id != 'none') {
      onProgress?.call(0.1);
      final processed = await _processImage(sanitizedFile, filter, maxWidth, maxHeight, quality);
      fileBytes = processed.bytes;
    } else {
      // Just resize without filter
      final resized = await _resizeImage(sanitizedFile, maxWidth, maxHeight, quality);
      fileBytes = resized.bytes;
    }

    onProgress?.call(0.2);


    return _uploadBytes(
      fileBytes: fileBytes,
      fileName: fileName,
      contentType: contentType,
      token: token,
      onProgress: onProgress,
    );
  }

  /// Uploads image bytes directly (web-safe).
  Future<String> uploadImageBytes(
    Uint8List imageBytes, {
    String? fileName,
    ImageFilter? filter,
    int maxWidth = defaultMaxWidth,
    int maxHeight = defaultMaxHeight,
    int quality = defaultQuality,
    UploadProgressCallback? onProgress,
  }) async {
    final token = await _getAuthToken();
    if (token == null) {
      throw UploadException('Not authenticated. Please sign in again.');
    }

    final safeName = (fileName != null && fileName.isNotEmpty)
        ? fileName
        : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
    const contentType = 'image/jpeg';

    Uint8List fileBytes;
    if (filter != null && filter.id != 'none') {
      onProgress?.call(0.1);
      final processed =
          await _processImageBytes(imageBytes, filter, maxWidth, maxHeight, quality);
      fileBytes = processed.bytes;
    } else {
      final resized =
          await _resizeImageBytes(imageBytes, maxWidth, maxHeight, quality);
      fileBytes = resized.bytes;
    }

    onProgress?.call(0.2);

    return _uploadBytes(
      fileBytes: fileBytes,
      fileName: safeName,
      contentType: contentType,
      token: token,
      onProgress: onProgress,
    );
  }

  /// Uploads multiple images
  Future<List<String>> uploadMultiple(
    List<File> imageFiles, {
    ImageFilter? filter,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <String>[];
    final total = imageFiles.length;

    for (int i = 0; i < imageFiles.length; i++) {
      try {
        final url = await uploadImage(imageFiles[i], filter: filter);
        results.add(url);
        onProgress?.call(i + 1, total);
      } catch (e) {
        throw UploadException('Failed to upload image ${i + 1}/$total: $e');
      }
    }

    return results;
  }

  // --- Internal Processing Helpers ---

  Future<_ProcessedImage> _processImage(
    File imageFile,
    ImageFilter filter,
    int maxWidth,
    int maxHeight,
    int quality,
  ) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) {
      throw UploadException('Failed to decode image');
    }

    if (filter.brightness != 1.0) {
      img.adjustColor(image, brightness: filter.brightness - 1.0);
    }
    if (filter.contrast != 1.0) {
      img.adjustColor(image, contrast: filter.contrast - 1.0);
    }
    if (filter.saturation != 1.0) {
      img.adjustColor(image, saturation: filter.saturation - 1.0);
    }

    if (filter.vignette > 0) {
      _applyVignette(image, filter.vignette);
    }

    final resized = _resizeMaintainAspectRatio(image, maxWidth, maxHeight);
    final outputBytes = img.encodeJpg(resized, quality: quality);

    return _ProcessedImage(
      bytes: outputBytes,
      width: resized.width,
      height: resized.height,
    );
  }

  Future<_ProcessedImage> _processImageBytes(
    Uint8List bytes,
    ImageFilter filter,
    int maxWidth,
    int maxHeight,
    int quality,
  ) async {
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw UploadException('Failed to decode image');
    }

    if (filter.brightness != 1.0) {
      img.adjustColor(image, brightness: filter.brightness - 1.0);
    }
    if (filter.contrast != 1.0) {
      img.adjustColor(image, contrast: filter.contrast - 1.0);
    }
    if (filter.saturation != 1.0) {
      img.adjustColor(image, saturation: filter.saturation - 1.0);
    }

    if (filter.vignette > 0) {
      _applyVignette(image, filter.vignette);
    }

    final resized = _resizeMaintainAspectRatio(image, maxWidth, maxHeight);
    final outputBytes = img.encodeJpg(resized, quality: quality);

    return _ProcessedImage(
      bytes: outputBytes,
      width: resized.width,
      height: resized.height,
    );
  }

  Future<_ProcessedImage> _resizeImage(
    File imageFile,
    int maxWidth,
    int maxHeight,
    int quality,
  ) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) {
      throw UploadException('Failed to decode image');
    }

    final resized = _resizeMaintainAspectRatio(image, maxWidth, maxHeight);
    final outputBytes = img.encodeJpg(resized, quality: quality);

    return _ProcessedImage(
      bytes: outputBytes,
      width: resized.width,
      height: resized.height,
    );
  }

  img.Image _resizeMaintainAspectRatio(img.Image image, int maxWidth, int maxHeight) {
    if (image.width <= maxWidth && image.height <= maxHeight) {
      return image;
    }

    final widthRatio = maxWidth / image.width;
    final heightRatio = maxHeight / image.height;
    final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;

    final newWidth = (image.width * ratio).round();
    final newHeight = (image.height * ratio).round();

    return img.copyResize(image, width: newWidth, height: newHeight);
  }

  void _applyVignette(img.Image image, double intensity) {
    // Vignette logic placeholder
  }

  Future<_ProcessedImage> _resizeImageBytes(
    Uint8List bytes,
    int maxWidth,
    int maxHeight,
    int quality,
  ) async {
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw UploadException('Failed to decode image');
    }

    final resized = _resizeMaintainAspectRatio(image, maxWidth, maxHeight);
    final outputBytes = img.encodeJpg(resized, quality: quality);

    return _ProcessedImage(
      bytes: outputBytes,
      width: resized.width,
      height: resized.height,
    );
  }

  Future<ImageValidationResult> validateImage(File imageFile) async {
    final fileName = imageFile.path.split('/').last;
    final extension = fileName.split('.').last.toLowerCase();
    
    const supportedFormats = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    if (!supportedFormats.contains(extension)) {
      return ImageValidationResult(
        isValid: false,
        error: 'Unsupported file format: $extension',
      );
    }

    final fileSize = await imageFile.length();
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (fileSize > maxSize) {
      return ImageValidationResult(
        isValid: false,
        error: 'File size exceeds 10MB limit',
      );
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return ImageValidationResult(
          isValid: false,
          error: 'Invalid image file',
        );
      }

      return ImageValidationResult(
        isValid: true,
        width: image.width,
        height: image.height,
        fileSize: fileSize,
        format: extension,
      );
    } catch (e) {
      return ImageValidationResult(
        isValid: false,
        error: 'Failed to read image: $e',
      );
    }
  }

  Future<String> _uploadBytes({
    required Uint8List fileBytes,
    required String fileName,
    required String contentType,
    required String token,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/upload');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(http.MultipartFile.fromBytes(
        'image',
        fileBytes,
        filename: fileName,
        contentType: http_parser.MediaType.parse(contentType),
      ));

      request.fields['fileName'] = fileName;

      onProgress?.call(0.3);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      onProgress?.call(0.9);

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMsg = errorData['error'] ?? 'Unknown error';
        throw UploadException('Upload failed: $errorMsg');
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final signedUrl = responseData['signedUrl'] ?? responseData['signed_url'];
      final publicUrl = (signedUrl ?? responseData['publicUrl']) as String;

      onProgress?.call(1.0);
      
      // FORCE FIX: Ensure custom domain is used even if backend returns raw R2 URL
      return _fixR2Url(publicUrl);
    } catch (e, stack) {
      throw UploadException(e.toString());
    }
  }

  /// Helper to force custom domains if raw R2 URLs slip through
  String _fixR2Url(String url) {
    if (url.contains('gosojorn.com')) {
      return url.replaceAll('gosojorn.com', 'sojorn.net');
    }

    if (!url.contains('.r2.cloudflarestorage.com')) return url;

    // Fix Image URLs
    if (url.contains('/sojorn-media/')) {
      final key = url.split('/sojorn-media/').last;
      return 'https://img.sojorn.net/$key';
    }

    // Fix Video URLs
    if (url.contains('/sojorn-videos/')) {
      final key = url.split('/sojorn-videos/').last;
      return 'https://quips.sojorn.net/$key';
    }

    return url;
  }

  String _contentTypeForFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
}

class ImageValidationResult {
  final bool isValid;
  final String? error;
  final int? width;
  final int? height;
  final int? fileSize;
  final String? format;

  const ImageValidationResult({
    required this.isValid,
    this.error,
    this.width,
    this.height,
    this.fileSize,
    this.format,
  });

  String getFormattedSize() {
    if (fileSize == null) return 'Unknown';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _ProcessedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

class UploadException implements Exception {
  final String message;
  UploadException(this.message);
  @override
  String toString() => message;
}
