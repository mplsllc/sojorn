// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_report.dart';
import '../services/api_service.dart';

class ReportHistoryState {
  final List<UserReport> reports;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  ReportHistoryState({
    this.reports = const [],
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  ReportHistoryState copyWith({
    List<UserReport>? reports,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return ReportHistoryState(
      reports: reports ?? this.reports,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
    );
  }

  bool get hasMore => reports.length < total;
}

class ReportHistoryNotifier extends Notifier<ReportHistoryState> {
  @override
  ReportHistoryState build() {
    Future.microtask(() => refresh());
    return ReportHistoryState();
  }

  ApiService get _api => ApiService.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getMyReports(limit: 20, offset: 0);
      final reports = (data['reports'] as List<dynamic>?)
              ?.map((e) => UserReport.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      state = state.copyWith(
        reports: reports,
        total: (data['total'] as num?)?.toInt() ?? 0,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final data = await _api.getMyReports(
        limit: 20,
        offset: state.reports.length,
      );
      final more = (data['reports'] as List<dynamic>?)
              ?.map((e) => UserReport.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      state = state.copyWith(
        reports: [...state.reports, ...more],
        total: (data['total'] as num?)?.toInt() ?? state.total,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final reportHistoryProvider =
    NotifierProvider<ReportHistoryNotifier, ReportHistoryState>(ReportHistoryNotifier.new);
