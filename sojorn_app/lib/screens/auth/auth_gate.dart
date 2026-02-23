// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_provider.dart';
import 'category_select_screen.dart';
import 'sign_in_screen.dart';
import '../security/vault_setup_gate.dart';

/// Auth gate - routes to sign in or home based on auth state
class AuthGate extends ConsumerWidget {
  final Widget authenticatedChild;

  const AuthGate({
    super.key,
    required this.authenticatedChild,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final user = ref.watch(currentUserProvider);

    if (isAuthenticated && user != null) {
      // For Go-auth users, profile is created during registration.
      // For Go-auth users, profile is created during registration.
      // We checks profileExistsProvider for strict onboarding completion.
      final onboardingAsync = ref.watch(profileExistsProvider);

      return onboardingAsync.when(
        data: (isComplete) {
          if (!isComplete) {
            // If strictly not complete, we might need to route to category?
            // Actually, if we use profileExistsProvider as the "master" switch:
            // If false -> Category Select (which completes it).
            // (Note: ProfileSetup is skipped as we do it at registration now, or we can handle it if we want to separate it)
            return const CategorySelectScreen();
          }
          return VaultSetupGate(child: authenticatedChild);
        },
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, stack) {
          // On error, go to home anyway to avoid blocking the user
          return authenticatedChild;
        },
      );
    } else {
      return const SignInScreen();
    }
  }
}
