import 'package:flutter/material.dart';

/// Model for text overlays on Quip videos
class QuipTextOverlay {
  final String text;
  final Color color;
  final Offset position; // Normalized 0.0-1.0 coordinates
  final double scale;
  final double rotation; // In radians

  const QuipTextOverlay({
    required this.text,
    required this.color,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  QuipTextOverlay copyWith({
    String? text,
    Color? color,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return QuipTextOverlay(
      text: text ?? this.text,
      color: color ?? this.color,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'color': color.value,
      'position': {'x': position.dx, 'y': position.dy},
      'scale': scale,
      'rotation': rotation,
    };
  }

  factory QuipTextOverlay.fromJson(Map<String, dynamic> json) {
    return QuipTextOverlay(
      text: json['text'] as String,
      color: Color(json['color'] as int),
      position: Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      ),
      scale: (json['scale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
    );
  }
}

/// Placeholder for future music track functionality
class MusicTrack {
  final String id;
  final String name;
  final String artist;
  final Duration duration;

  const MusicTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.duration,
  });
}
