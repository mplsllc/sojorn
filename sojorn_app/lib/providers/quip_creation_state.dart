// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quip_text_overlay.dart';

/// State for the Quip creation session
class QuipCreationState {
  final List<File> segments; // Raw video files recorded so far
  final double totalDuration; // Sum of all segment durations in seconds
  final List<QuipTextOverlay> overlays;
  final MusicTrack? selectedMusic;

  const QuipCreationState({
    this.segments = const [],
    this.totalDuration = 0.0,
    this.overlays = const [],
    this.selectedMusic,
  });

  QuipCreationState copyWith({
    List<File>? segments,
    double? totalDuration,
    List<QuipTextOverlay>? overlays,
    MusicTrack? selectedMusic,
  }) {
    return QuipCreationState(
      segments: segments ?? this.segments,
      totalDuration: totalDuration ?? this.totalDuration,
      overlays: overlays ?? this.overlays,
      selectedMusic: selectedMusic ?? this.selectedMusic,
    );
  }

  bool get hasSegments => segments.isNotEmpty;
  bool get isAtMaxDuration => totalDuration >= 60.0; // 60s max
  bool get canRecordMore => totalDuration < 60.0;
}

/// Controller for managing the Quip creation session
class QuipCreationController extends Notifier<QuipCreationState> {
  @override
  QuipCreationState build() {
    return const QuipCreationState();
  }

  /// Add a new video segment to the collection
  void addSegment(File segment, Duration duration) {
    final newTotal = state.totalDuration + duration.inMilliseconds / 1000.0;
    if (newTotal > 60.0) {
      // Don't add if it would exceed the limit
      return;
    }

    state = state.copyWith(
      segments: [...state.segments, segment],
      totalDuration: newTotal,
    );
  }

  /// Remove the last recorded segment
  void removeLastSegment() {
    if (state.segments.isEmpty) return;

    final lastSegment = state.segments.last;
    // Note: We can't easily get duration from file, so we'll estimate or require it
    // For now, remove and adjust duration (this is a simplification)
    final estimatedDuration = 3.0; // Assume 3s average, will be refined
    final newTotal = (state.totalDuration - estimatedDuration).clamp(0.0, 60.0);

    state = state.copyWith(
      segments: state.segments.sublist(0, state.segments.length - 1),
      totalDuration: newTotal,
    );
  }

  /// Delete a specific segment at index
  void deleteSegmentAt(int index) {
    if (index < 0 || index >= state.segments.length) return;

    final newSegments = List<File>.from(state.segments)..removeAt(index);
    // Simplified duration adjustment - in real implementation, you'd track per-segment durations
    final estimatedDuration = 3.0;
    final newTotal = (state.totalDuration - estimatedDuration).clamp(0.0, 60.0);

    state = state.copyWith(
      segments: newSegments,
      totalDuration: newTotal,
    );
  }

  /// Reorder segments from oldIndex to newIndex
  void reorderSegments(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.segments.length ||
        newIndex < 0 || newIndex >= state.segments.length) return;

    final newSegments = List<File>.from(state.segments);
    final segment = newSegments.removeAt(oldIndex);
    newSegments.insert(newIndex, segment);

    state = state.copyWith(segments: newSegments);
  }

  /// Add a new text overlay
  void addTextOverlay(QuipTextOverlay overlay) {
    state = state.copyWith(
      overlays: [...state.overlays, overlay],
    );
  }

  /// Update an existing text overlay
  void updateTextOverlay(int index, QuipTextOverlay overlay) {
    if (index < 0 || index >= state.overlays.length) return;

    final newOverlays = List<QuipTextOverlay>.from(state.overlays);
    newOverlays[index] = overlay;

    state = state.copyWith(overlays: newOverlays);
  }

  /// Remove a text overlay
  void removeTextOverlay(int index) {
    if (index < 0 || index >= state.overlays.length) return;

    final newOverlays = List<QuipTextOverlay>.from(state.overlays)..removeAt(index);
    state = state.copyWith(overlays: newOverlays);
  }

  /// Clear the entire session (for cleanup)
  void clearSession() {
    state = const QuipCreationState();
  }
}

/// Provider for the Quip creation session
final quipCreationProvider =
    NotifierProvider<QuipCreationController, QuipCreationState>(() {
  return QuipCreationController();
});
