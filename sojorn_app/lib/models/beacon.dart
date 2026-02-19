import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Beacon severity levels — controls pin color and alert priority
enum BeaconSeverity {
  low('low', 'Info', Color(0xFF4CAF50), Icons.info_outline),
  medium('medium', 'Caution', Color(0xFFFFC107), Icons.warning_amber),
  high('high', 'Danger', Color(0xFFFF5722), Icons.error_outline),
  critical('critical', 'Critical', SojornColors.destructive, Icons.dangerous);

  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const BeaconSeverity(this.value, this.label, this.color, this.icon);

  static BeaconSeverity fromString(String value) {
    return BeaconSeverity.values.firstWhere(
      (s) => s.value == value,
      orElse: () => BeaconSeverity.medium,
    );
  }
}

/// Beacon incident lifecycle status
enum BeaconIncidentStatus {
  active('active', 'Active'),
  resolved('resolved', 'Resolved'),
  falseAlarm('false_alarm', 'False Alarm');

  final String value;
  final String label;

  const BeaconIncidentStatus(this.value, this.label);

  static BeaconIncidentStatus fromString(String value) {
    return BeaconIncidentStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => BeaconIncidentStatus.active,
    );
  }
}

/// Two distinct beacon modes for routing to map vs board
enum BeaconMode { geoAlert, discussion }

/// Beacon type enum for different alert categories
/// Uses neutral naming for App Store compliance
enum BeaconType {
  // ── Geo-Alerts (rendered on the Map) ──────────────────────────────────
  suspiciousActivity('suspicious', 'Suspicious Activity', 'Report unusual behavior or people', Icons.visibility, Color(0xFFFF9800), BeaconMode.geoAlert),
  officialPresence('official_presence', 'Official Presence', 'General presence (patrols, checkpoints)', Icons.local_police, Color(0xFF2196F3), BeaconMode.geoAlert),
  checkpoint('checkpoint', 'Checkpoint / Stop', 'Report stationary stops, roadblocks, or inspection points.', Icons.stop_circle, Color(0xFF3F51B5), BeaconMode.geoAlert),
  taskForce('taskForce', 'Task Force / Operation', 'Report heavy coordinated activity or multiple units.', Icons.warning, Color(0xFFFF5722), BeaconMode.geoAlert),
  hazard('hazard', 'Road Hazard', 'Physical danger (Debris, Ice, Floods)', Icons.report_problem, Color(0xFFFFC107), BeaconMode.geoAlert),
  fire('fire', 'Fire', 'Report fires or smoke', Icons.local_fire_department, Color(0xFFF44336), BeaconMode.geoAlert),
  safety('safety', 'Safety Alert', 'Events (Fights, Gunshots, Active threats)', Icons.shield, Color(0xFFF44336), BeaconMode.geoAlert),
  camera('camera', 'Traffic Camera', 'Live MN DOT traffic camera feed', Icons.videocam, Color(0xFF26C6DA), BeaconMode.geoAlert),
  sign('sign', 'Road Sign', 'MN DOT electronic road sign', Icons.signpost, Color(0xFFFFAB00), BeaconMode.geoAlert),
  weatherStation('weather_station', 'Weather Station', 'MN DOT road weather sensor', Icons.cloud, Color(0xFF42A5F5), BeaconMode.geoAlert),

  // ── Discussion (rendered on the Neighborhood Board) ───────────────────
  community('community', 'Community Event', 'Helpful (Food drives, Meetups)', Icons.volunteer_activism, Color(0xFF009688), BeaconMode.discussion),
  lostPet('lost_pet', 'Lost Pet', 'Help find a missing pet', Icons.pets, Color(0xFF8D6E63), BeaconMode.discussion),
  question('question', 'General Question', 'Ask your neighborhood something', Icons.help_outline, Color(0xFF78909C), BeaconMode.discussion),
  event('event', 'Local Event', 'Share an upcoming event nearby', Icons.event, Color(0xFF7E57C2), BeaconMode.discussion),
  resource('resource', 'Resource Sharing', 'Offer or request items/help', Icons.handshake, Color(0xFF26A69A), BeaconMode.discussion);

  final String value;
  final String displayName;
  final String description;
  final IconData icon;
  final Color color;
  final BeaconMode mode;

  const BeaconType(this.value, this.displayName, this.description, this.icon, this.color, this.mode);

  /// Whether this type shows on the map
  bool get isGeoAlert => mode == BeaconMode.geoAlert;

  /// Whether this type shows on the neighborhood board
  bool get isDiscussion => mode == BeaconMode.discussion;

  static BeaconType fromString(String value) {
    return BeaconType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => BeaconType.community,
    );
  }

  /// All types that belong to the map layer
  static List<BeaconType> get geoAlertTypes =>
      values.where((t) => t.isGeoAlert).toList();

  /// All types that belong to the neighborhood board
  static List<BeaconType> get discussionTypes =>
      values.where((t) => t.isDiscussion).toList();
  
  /// Get helper text for checkpoint and task force types
  String? get helperText {
    switch (this) {
      case BeaconType.checkpoint:
        return 'Report stationary stops, roadblocks, or inspection points.';
      case BeaconType.taskForce:
        return 'Report heavy coordinated activity or multiple units.';
      default:
        return null;
    }
  }
}

/// Beacon status color based on confidence score
enum BeaconStatus {
  green('green', 'Verified', 'High confidence - Community verified'),
  yellow('yellow', 'Caution', 'Pending verification'),
  red('red', 'Unverified', 'Low confidence - Needs verification');

  final String value;
  final String label;
  final String description;

  const BeaconStatus(this.value, this.label, this.description);

  static BeaconStatus fromConfidence(double score) {
    if (score > 0.7) {
      return BeaconStatus.green;
    } else if (score >= 0.3 && score <= 0.7) {
      return BeaconStatus.yellow;
    } else {
      return BeaconStatus.red;
    }
  }
}

/// Beacon model representing a location-based safety/community alert
class Beacon {
  final String id;
  final String body;
  final String authorId;
  final BeaconType beaconType;
  final double confidenceScore;
  final bool isActiveBeacon;
  final BeaconStatus status;
  final DateTime createdAt;
  final double distanceMeters;
  final String? imageUrl;

  // Location info
  final double? beaconLat;
  final double? beaconLong;

  // Author info
  final String? authorHandle;
  final String? authorDisplayName;
  final String? authorAvatarUrl;

  // Vote info
  final int? vouchCount;
  final int? reportCount;
  final String? userVote; // 'vouch', 'report', or null

  // Group association (neighborhood)
  final String? groupId;

  // Safety system fields
  final BeaconSeverity severity;
  final BeaconIncidentStatus incidentStatus;
  final int radius; // area of effect in meters
  final int verificationCount; // "I see this too" vouches

  // Official/government source fields
  final bool isOfficial;
  final String? officialSource;

  // Camera-specific: HLS m3u8 stream URL
  final String? streamUrl;

  Beacon({
    required this.id,
    required this.body,
    required this.authorId,
    required this.beaconType,
    required this.confidenceScore,
    required this.isActiveBeacon,
    required this.status,
    required this.createdAt,
    this.distanceMeters = 0,
    this.imageUrl,
    this.beaconLat,
    this.beaconLong,
    this.authorHandle,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.vouchCount,
    this.reportCount,
    this.userVote,
    this.groupId,
    this.severity = BeaconSeverity.medium,
    this.incidentStatus = BeaconIncidentStatus.active,
    this.radius = 500,
    this.verificationCount = 0,
    this.isOfficial = false,
    this.officialSource,
    this.streamUrl,
  });

  /// Parse double from various types
  static double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return fallback;
  }

  /// Parse int from various types
  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  factory Beacon.fromJson(Map<String, dynamic> json) {
    final statusColor = json['status_color'] as String? ?? 'yellow';
    final status = _getStatusFromColor(statusColor);
    final beaconType = BeaconType.fromString(json['beacon_type'] as String? ?? 'community');

    return Beacon(
      id: json['id'] as String,
      body: json['body'] as String,
      authorId: json['author_id'] as String? ?? '',
      beaconType: beaconType,
      confidenceScore: _parseDouble(json['confidence_score']),
      isActiveBeacon: json['is_active_beacon'] as bool? ?? true,
      status: status,
      createdAt: DateTime.parse(json['created_at'] as String),
      distanceMeters: _parseDouble(json['distance_meters']),
      imageUrl: json['image_url'] as String?,
      beaconLat: json['beacon_lat'] != null ? _parseDouble(json['beacon_lat']) : null,
      beaconLong: json['beacon_long'] != null ? _parseDouble(json['beacon_long']) : null,
      authorHandle: json['author_handle'] as String?,
      authorDisplayName: json['author_display_name'] as String?,
      authorAvatarUrl: json['author_avatar_url'] as String?,
      vouchCount: _parseInt(json['vouch_count']),
      reportCount: _parseInt(json['report_count']),
      userVote: json['user_vote'] as String?,
      groupId: json['group_id'] as String?,
      severity: BeaconSeverity.fromString(json['severity'] as String? ?? 'medium'),
      incidentStatus: BeaconIncidentStatus.fromString(json['incident_status'] as String? ?? 'active'),
      radius: _parseInt(json['radius'] ?? 500),
      verificationCount: _parseInt(json['verification_count'] ?? 0),
      isOfficial: json['is_official'] as bool? ?? false,
      officialSource: json['official_source'] as String?,
      streamUrl: json['video_url'] as String?,
    );
  }

  static BeaconStatus _getStatusFromColor(String color) {
    switch (color) {
      case 'green':
        return BeaconStatus.green;
      case 'yellow':
        return BeaconStatus.yellow;
      case 'red':
      default:
        return BeaconStatus.red;
    }
  }

  /// Get human-readable distance
  String getFormattedDistance() {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    } else {
      final km = distanceMeters / 1000;
      return '${km.toStringAsFixed(1)}km';
    }
  }

  /// Get time ago string
  String getTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Whether this beacon was reported in the last 30 minutes (for pulse animation)
  bool get isRecent => DateTime.now().difference(createdAt).inMinutes < 30;

  /// Color for the map pin based on severity
  Color get pinColor => severity.color;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
      'author_id': authorId,
      'beacon_type': beaconType.value,
      'confidence_score': confidenceScore,
      'is_active_beacon': isActiveBeacon,
      'status_color': status.value,
      'created_at': createdAt.toIso8601String(),
      'distance_meters': distanceMeters,
      'image_url': imageUrl,
      'beacon_lat': beaconLat,
      'beacon_long': beaconLong,
      'author_handle': authorHandle,
      'author_display_name': authorDisplayName,
      'author_avatar_url': authorAvatarUrl,
      'vouch_count': vouchCount,
      'report_count': reportCount,
      'user_vote': userVote,
      'severity': severity.value,
      'incident_status': incidentStatus.value,
      'radius': radius,
      'verification_count': verificationCount,
      'is_official': isOfficial,
      if (officialSource != null) 'official_source': officialSource,
      if (streamUrl != null) 'video_url': streamUrl,
      if (groupId != null) 'group_id': groupId,
    };
  }
}

/// Beacon creation request
class CreateBeaconRequest {
  final double lat;
  final double long;
  final String title;
  final String description;
  final BeaconType type;
  final BeaconSeverity severity;
  final String? imageUrl;

  CreateBeaconRequest({
    required this.lat,
    required this.long,
    required this.title,
    required this.description,
    required this.type,
    this.severity = BeaconSeverity.medium,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'long': long,
      'title': title,
      'description': description,
      'type': type.value,
      'severity': severity.value,
      if (imageUrl != null) 'image_url': imageUrl,
    };
  }
}
