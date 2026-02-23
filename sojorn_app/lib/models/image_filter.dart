// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Image filter presets for processing images before upload
class ImageFilter {
  final String id;
  final String name;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double fade;
  final double vignette;
  final int? blur; // null means no blur

  const ImageFilter({
    required this.id,
    required this.name,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.warmth = 1.0,
    this.fade = 0.0,
    this.vignette = 0.0,
    this.blur,
  });

  /// Creates a copy with modified values
  ImageFilter copyWith({
    String? id,
    String? name,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? fade,
    double? vignette,
    int? blur,
  }) {
    return ImageFilter(
      id: id ?? this.id,
      name: name ?? this.name,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      warmth: warmth ?? this.warmth,
      fade: fade ?? this.fade,
      vignette: vignette ?? this.vignette,
      blur: blur ?? this.blur,
    );
  }

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'warmth': warmth,
      'fade': fade,
      'vignette': vignette,
      'blur': blur,
    };
  }

  /// Create from map
  factory ImageFilter.fromMap(Map<String, dynamic> map) {
    return ImageFilter(
      id: map['id'] as String,
      name: map['name'] as String,
      brightness: (map['brightness'] as num?)?.toDouble() ?? 1.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 1.0,
      warmth: (map['warmth'] as num?)?.toDouble() ?? 1.0,
      fade: (map['fade'] as num?)?.toDouble() ?? 0.0,
      vignette: (map['vignette'] as num?)?.toDouble() ?? 0.0,
      blur: map['blur'] as int?,
    );
  }

  /// Preset filters
  static const List<ImageFilter> presets = [
    ImageFilter(
      id: 'none',
      name: 'Original',
    ),
    ImageFilter(
      id: 'vivid',
      name: 'Vivid',
      contrast: 1.15,
      saturation: 1.2,
    ),
    ImageFilter(
      id: 'warm',
      name: 'Warm',
      warmth: 1.15,
      saturation: 1.1,
    ),
    ImageFilter(
      id: 'cool',
      name: 'Cool',
      warmth: 0.85,
      saturation: 1.1,
      contrast: 1.1,
    ),
    ImageFilter(
      id: 'bw',
      name: 'Black & White',
      saturation: 0.0,
      contrast: 1.1,
    ),
    ImageFilter(
      id: 'sepia',
      name: 'Sepia',
      warmth: 1.2,
      saturation: 0.7,
      contrast: 1.05,
    ),
    ImageFilter(
      id: 'fade',
      name: 'Faded',
      fade: 0.15,
      contrast: 0.9,
      saturation: 0.9,
    ),
    ImageFilter(
      id: 'dramatic',
      name: 'Dramatic',
      contrast: 1.3,
      brightness: 0.95,
      vignette: 0.3,
    ),
    ImageFilter(
      id: 'soft',
      name: 'Soft',
      brightness: 1.05,
      contrast: 0.95,
      saturation: 0.95,
      fade: 0.05,
    ),
    ImageFilter(
      id: 'noir',
      name: 'Noir',
      saturation: 0.0,
      contrast: 1.25,
      brightness: 0.9,
      vignette: 0.4,
    ),
  ];

  /// Get preset by ID
  static ImageFilter? getPreset(String id) {
    try {
      return presets.firstWhere((filter) => filter.id == id);
    } catch (_) {
      return null;
    }
  }
}
