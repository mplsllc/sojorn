// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/image_filter.dart';

const String _imageFiltersPrefsKey = 'sojorn_image_filters';

/// State for image filters
class ImageFilterState {
  final List<ImageFilter> customFilters;
  final String? selectedFilterId;
  final bool isLoading;

  const ImageFilterState({
    this.customFilters = const [],
    this.selectedFilterId = 'none',
    this.isLoading = false,
  });

  ImageFilterState copyWith({
    List<ImageFilter>? customFilters,
    String? selectedFilterId,
    bool? isLoading,
  }) {
    return ImageFilterState(
      customFilters: customFilters ?? this.customFilters,
      selectedFilterId: selectedFilterId ?? this.selectedFilterId,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Get all available filters (presets + custom)
  List<ImageFilter> get allFilters {
    final presets = ImageFilter.presets;
    return [...presets, ...customFilters];
  }

  /// Get currently selected filter
  ImageFilter? get selectedFilter {
    if (selectedFilterId == null) return null;
    return allFilters.firstWhere(
      (f) => f.id == selectedFilterId,
      orElse: () => ImageFilter.presets.first,
    );
  }
}

/// Notifier for image filters
class ImageFilterNotifier extends Notifier<ImageFilterState> {
  @override
  ImageFilterState build() {
    loadFilters();
    return const ImageFilterState();
  }

  Future<void> loadFilters() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final filtersJson = prefs.getString(_imageFiltersPrefsKey);

      if (filtersJson != null) {
        final List<dynamic> filterList = jsonDecode(filtersJson);
        final filters = filterList.map((f) => ImageFilter.fromMap(f)).toList();
        state = state.copyWith(customFilters: filters, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> saveFilter(ImageFilter filter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedFilters = List<ImageFilter>.from(state.customFilters);

      final index = updatedFilters.indexWhere((f) => f.id == filter.id);
      if (index >= 0) {
        updatedFilters[index] = filter;
      } else {
        updatedFilters.add(filter);
      }

      final filtersJson =
          jsonEncode(updatedFilters.map((f) => f.toMap()).toList());
      await prefs.setString(_imageFiltersPrefsKey, filtersJson);

      state = state.copyWith(customFilters: updatedFilters);
    } catch (e) {
      // Silently fail for filter save
    }
  }

  Future<void> deleteFilter(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedFilters =
          state.customFilters.where((f) => f.id != id).toList();

      final filtersJson =
          jsonEncode(updatedFilters.map((f) => f.toMap()).toList());
      await prefs.setString(_imageFiltersPrefsKey, filtersJson);

      state = state.copyWith(
        customFilters: updatedFilters,
        selectedFilterId:
            state.selectedFilterId == id ? 'none' : state.selectedFilterId,
      );
    } catch (e) {
      // Silently fail for filter delete
    }
  }

  void selectFilter(String? id) {
    state = state.copyWith(selectedFilterId: id);
  }

  /// Create a new custom filter from current settings
  Future<void> createCustomFilter(String name, ImageFilter base) async {
    final customFilter = ImageFilter(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      brightness: base.brightness,
      contrast: base.contrast,
      saturation: base.saturation,
      warmth: base.warmth,
      fade: base.fade,
      vignette: base.vignette,
      blur: base.blur,
    );
    await saveFilter(customFilter);
  }

  Future<void> resetFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_imageFiltersPrefsKey);
      state = const ImageFilterState();
    } catch (e) {
      // Silently fail
    }
  }
}

/// Provider for image filters
final imageFilterProvider =
    NotifierProvider<ImageFilterNotifier, ImageFilterState>(() {
  return ImageFilterNotifier();
});
