// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final feedRefreshProvider =
    NotifierProvider<FeedRefreshNotifier, int>(FeedRefreshNotifier.new);
