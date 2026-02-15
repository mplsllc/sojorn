import 'dart:typed_data';

/// Unified result class for both image and video editing operations.
/// Handles both in-memory bytes and file paths for flexible media handling.
class SojornMediaResult {
  /// The edited media as bytes (used for web or in-memory operations)
  final Uint8List? bytes;
  
  /// The name of the media file
  final String? name;
  
  /// The file path (used for mobile/desktop operations)
  final String? filePath;
  
  /// The thumbnail file path (used for beacon images)
  final String? thumbnailPath;
  
  /// Media type ('image', 'video', or 'beacon_image')
  final String mediaType;

  const SojornMediaResult({
    this.bytes,
    this.name,
    this.filePath,
    this.thumbnailPath,
    required this.mediaType,
  }) : assert(bytes != null || filePath != null, 'Either bytes or filePath must be provided');

  /// Creates a result for image media
  factory SojornMediaResult.image({
    Uint8List? bytes,
    String? name,
    String? filePath,
  }) {
    return SojornMediaResult(
      bytes: bytes,
      name: name,
      filePath: filePath,
      mediaType: 'image',
    );
  }

  /// Creates a result for video media
  factory SojornMediaResult.video({
    Uint8List? bytes,
    String? name,
    String? filePath,
  }) {
    return SojornMediaResult(
      bytes: bytes,
      name: name,
      filePath: filePath,
      mediaType: 'video',
    );
  }

  /// Creates a result for beacon image with dual outputs
  factory SojornMediaResult.beaconImage({
    String? filePath,
    String? thumbnailPath,
    String? name,
  }) {
    return SojornMediaResult(
      filePath: filePath,
      thumbnailPath: thumbnailPath,
      name: name,
      mediaType: 'beacon_image',
    );
  }

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isBeaconImage => mediaType == 'beacon_image';
  bool get hasBytes => bytes != null;
  bool get hasFilePath => filePath != null;
  bool get hasThumbnail => thumbnailPath != null;
}
