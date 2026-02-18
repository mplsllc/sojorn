import 'package:flutter/material.dart';

/// Type of overlay item on a Quip video.
enum QuipOverlayType { text, sticker }

/// A single overlay item (text or sticker/emoji) placed on a Quip video.
/// Position is normalized (0.0–1.0) relative to the video dimensions so it
/// renders correctly at any screen size.
class QuipOverlayItem {
  final String id; // unique identifier for widget keying
  final QuipOverlayType type;
  final String content; // text string or emoji/sticker character
  final Color color; // text color (default white)
  final Offset position; // normalized 0.0–1.0
  final double scale;
  final double rotation; // radians

  const QuipOverlayItem({
    required this.id,
    required this.type,
    required this.content,
    this.color = Colors.white,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  QuipOverlayItem copyWith({
    String? id,
    QuipOverlayType? type,
    String? content,
    Color? color,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return QuipOverlayItem(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      color: color ?? this.color,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'color': color.value,
      'position': {'x': position.dx, 'y': position.dy},
      'scale': scale,
      'rotation': rotation,
    };
  }

  factory QuipOverlayItem.fromJson(Map<String, dynamic> json) {
    return QuipOverlayItem(
      id: json['id'] as String? ?? UniqueKey().toString(),
      type: QuipOverlayType.values.byName(
        (json['type'] as String?) ?? 'text',
      ),
      content: (json['content'] ?? json['text'] ?? '') as String,
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

/// Backward-compat alias so existing screens that reference QuipTextOverlay
/// do not require immediate migration.
typedef QuipTextOverlay = QuipOverlayItem;

/// Placeholder for music track metadata.
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
