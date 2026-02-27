// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analytics_service.dart';

/// Provides [AnalyticsService] singleton via Riverpod.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService.instance;
});

/// Manages the analytics opt-out preference.
final analyticsOptOutProvider =
    NotifierProvider<AnalyticsOptOutNotifier, bool>(AnalyticsOptOutNotifier.new);

class AnalyticsOptOutNotifier extends Notifier<bool> {
  @override
  bool build() => AnalyticsService.instance.isOptedOut;

  Future<void> toggle() async {
    final newValue = !state;
    await AnalyticsService.instance.setOptOut(newValue);
    state = newValue;
  }

  Future<void> set(bool value) async {
    await AnalyticsService.instance.setOptOut(value);
    state = value;
  }
}
