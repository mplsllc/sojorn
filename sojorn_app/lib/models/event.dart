// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:equatable/equatable.dart';

enum RSVPStatus {
  going('going'),
  interested('interested'),
  notGoing('not_going');

  const RSVPStatus(this.value);
  final String value;

  static RSVPStatus? fromString(String? value) {
    if (value == null) return null;
    return RSVPStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => RSVPStatus.going,
    );
  }
}

class GroupEvent extends Equatable {
  final String id;
  final String groupId;
  final String? groupName;
  final String createdBy;
  final String title;
  final String description;
  final String? locationName;
  final double? lat;
  final double? long;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isPublic;
  final String? coverImageUrl;
  final int? maxAttendees;
  final int attendeeCount;
  final RSVPStatus? myRsvp;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupEvent({
    required this.id,
    required this.groupId,
    this.groupName,
    required this.createdBy,
    required this.title,
    required this.description,
    this.locationName,
    this.lat,
    this.long,
    required this.startsAt,
    this.endsAt,
    required this.isPublic,
    this.coverImageUrl,
    this.maxAttendees,
    required this.attendeeCount,
    this.myRsvp,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupEvent.fromJson(Map<String, dynamic> json) {
    return GroupEvent(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      groupName: json['group_name'] as String?,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      locationName: json['location_name'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      long: (json['long'] as num?)?.toDouble(),
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      isPublic: json['is_public'] as bool? ?? false,
      coverImageUrl: json['cover_image_url'] as String?,
      maxAttendees: json['max_attendees'] as int?,
      attendeeCount: json['attendee_count'] as int? ?? 0,
      myRsvp: RSVPStatus.fromString(json['my_rsvp'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'location_name': locationName,
        'lat': lat,
        'long': long,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'is_public': isPublic,
        'cover_image_url': coverImageUrl,
        'max_attendees': maxAttendees,
      };

  GroupEvent copyWith({
    RSVPStatus? myRsvp,
    int? attendeeCount,
  }) {
    return GroupEvent(
      id: id,
      groupId: groupId,
      groupName: groupName,
      createdBy: createdBy,
      title: title,
      description: description,
      locationName: locationName,
      lat: lat,
      long: long,
      startsAt: startsAt,
      endsAt: endsAt,
      isPublic: isPublic,
      coverImageUrl: coverImageUrl,
      maxAttendees: maxAttendees,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      myRsvp: myRsvp ?? this.myRsvp,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, groupId, title, startsAt, myRsvp, attendeeCount];
}
