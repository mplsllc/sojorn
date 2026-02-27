// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/violation.dart';
import '../services/api_service.dart';

class ViolationsState {
  final ViolationSummary? summary;
  final List<UserViolation> violations;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  ViolationsState({
    this.summary,
    this.violations = const [],
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  ViolationsState copyWith({
    ViolationSummary? summary,
    List<UserViolation>? violations,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return ViolationsState(
      summary: summary ?? this.summary,
      violations: violations ?? this.violations,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
    );
  }

  bool get hasMore => violations.length < total;
}

class ViolationsNotifier extends Notifier<ViolationsState> {
  @override
  ViolationsState build() {
    Future.microtask(() => refresh());
    return ViolationsState();
  }

  ApiService get _api => ApiService.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        _api.getViolationSummary(),
        _api.getMyViolations(limit: 20, offset: 0),
      ]);
      final summary = ViolationSummary.fromJson(results[0]);
      final listData = results[1];
      final violations = (listData['violations'] as List<dynamic>?)
              ?.map((e) => UserViolation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      state = state.copyWith(
        summary: summary,
        violations: violations,
        total: (listData['total'] as num?)?.toInt() ?? 0,
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
      final data = await _api.getMyViolations(
        limit: 20,
        offset: state.violations.length,
      );
      final more = (data['violations'] as List<dynamic>?)
              ?.map((e) => UserViolation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      state = state.copyWith(
        violations: [...state.violations, ...more],
        total: (data['total'] as num?)?.toInt() ?? state.total,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<bool> submitAppeal({
    required String violationId,
    required String reason,
    String? context,
    List<String>? evidenceUrls,
  }) async {
    try {
      await _api.createAppeal(
        violationId: violationId,
        reason: reason,
        context: context,
        evidenceUrls: evidenceUrls,
      );
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final violationsProvider =
    NotifierProvider<ViolationsNotifier, ViolationsState>(ViolationsNotifier.new);
