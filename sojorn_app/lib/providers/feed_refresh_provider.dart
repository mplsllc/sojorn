import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final feedRefreshProvider =
    NotifierProvider<FeedRefreshNotifier, int>(FeedRefreshNotifier.new);
