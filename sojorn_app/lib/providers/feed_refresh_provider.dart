// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final feedRefreshProvider =
    NotifierProvider<FeedRefreshNotifier, int>(FeedRefreshNotifier.new);
