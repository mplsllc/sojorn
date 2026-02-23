// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_provider.dart';
import 'auth_provider.dart';

/// Whether onboarding is complete.
/// We now trust the backend `has_completed_onboarding` flag to avoid web
/// storage inconsistencies that can trap users on the interests screen.
final profileExistsProvider = FutureProvider.autoDispose<bool>((ref) async {
  final authenticated = ref.watch(isAuthenticatedProvider);
  if (!authenticated) return false;

  final api = ref.read(apiServiceProvider);
  final authService = ref.read(authServiceProvider);

  try {
    final data = await api.getProfile(); // /profile GET
    final profile = data['profile'];
    final hasCompleted = profile.hasCompletedOnboarding;

    // Keep local cache in sync for faster subsequent boots.
    if (hasCompleted) {
      await authService.markOnboardingCompleteLocally();
    }
    return hasCompleted;
  } catch (_) {
    // Fallback to local cache if network fails.
    return authService.isOnboardingComplete();
  }
});

/// Whether the current user has selected at least one category
final categorySelectionProvider = FutureProvider.autoDispose<bool>((ref) async {
  final authenticated = ref.watch(isAuthenticatedProvider);
  if (!authenticated) {
    return false;
  }

  final apiService = ref.watch(apiServiceProvider);
  return apiService.hasCategorySelection();
});
