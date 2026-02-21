// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

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
