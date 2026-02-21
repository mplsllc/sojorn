// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HeaderMode { feed, context }

class HeaderState {
  final HeaderMode mode;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final List<Widget> trailingActions;

  const HeaderState({
    required this.mode,
    required this.title,
    this.onBack,
    this.onRefresh,
    this.trailingActions = const [],
  });

  HeaderState copyWith({
    HeaderMode? mode,
    String? title,
    VoidCallback? onBack,
    VoidCallback? onRefresh,
    List<Widget>? trailingActions,
  }) {
    return HeaderState(
      mode: mode ?? this.mode,
      title: title ?? this.title,
      onBack: onBack ?? this.onBack,
      onRefresh: onRefresh ?? this.onRefresh,
      trailingActions: trailingActions ?? this.trailingActions,
    );
  }

  factory HeaderState.feed({
    VoidCallback? onRefresh,
    List<Widget> trailingActions = const [],
  }) {
    return HeaderState(
      mode: HeaderMode.feed,
      title: 'sojorn',
      onRefresh: onRefresh,
      trailingActions: trailingActions,
    );
  }

  factory HeaderState.context({
    required String title,
    VoidCallback? onBack,
    VoidCallback? onRefresh,
    List<Widget> trailingActions = const [],
  }) {
    return HeaderState(
      mode: HeaderMode.context,
      title: title,
      onBack: onBack,
      onRefresh: onRefresh,
      trailingActions: trailingActions,
    );
  }
}

class HeaderController extends Notifier<HeaderState> {
  VoidCallback? _feedRefresh;
  List<Widget> _feedTrailingActions = const [];

  @override
  HeaderState build() => HeaderState.feed();

  void configureFeed({
    VoidCallback? onRefresh,
    List<Widget> trailingActions = const [],
  }) {
    _feedRefresh = onRefresh;
    _feedTrailingActions = trailingActions;
    if (state.mode == HeaderMode.feed) {
      state = HeaderState.feed(
        onRefresh: _feedRefresh,
        trailingActions: _feedTrailingActions,
      );
    }
  }

  void setFeed() {
    state = HeaderState.feed(
      onRefresh: _feedRefresh,
      trailingActions: _feedTrailingActions,
    );
  }

  void setContext({
    required String title,
    VoidCallback? onBack,
    VoidCallback? onRefresh,
    List<Widget> trailingActions = const [],
  }) {
    state = HeaderState.context(
      title: title,
      onBack: onBack,
      onRefresh: onRefresh,
      trailingActions: trailingActions,
    );
  }
}

final headerControllerProvider =
    NotifierProvider<HeaderController, HeaderState>(HeaderController.new);
