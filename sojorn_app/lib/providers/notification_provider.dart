// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

final badgeStreamProvider = StreamProvider<UnreadBadge>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.badgeStream;
});

final currentBadgeProvider = Provider<UnreadBadge>((ref) {
  final badgeAsync = ref.watch(badgeStreamProvider);
  return badgeAsync.when(
    data: (badge) => badge,
    loading: () => NotificationService.instance.currentBadge,
    error: (_, __) => NotificationService.instance.currentBadge,
  );
});
