// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final currentUserProvider = Provider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  ref.watch(authStateProvider);
  return authService.currentUser;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  ref.watch(authStateProvider);
  
  return authService.currentUser != null;
});

class EmailVerifiedEventNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final emailVerifiedEventProvider =
    NotifierProvider<EmailVerifiedEventNotifier, bool>(
        EmailVerifiedEventNotifier.new);
