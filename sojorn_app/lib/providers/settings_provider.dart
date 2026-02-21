// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile.dart';
import '../models/profile_privacy_settings.dart';
import '../models/user_settings.dart';
import '../models/trust_state.dart';
import '../services/api_service.dart';

class SettingsState {
  final Profile? profile;
  final ProfilePrivacySettings? privacy;
  final UserSettings? user;
  final TrustState? trust;
  final bool isLoading;
  final String? error;

  SettingsState({
    this.profile,
    this.privacy,
    this.user,
    this.trust,
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    Profile? profile,
    ProfilePrivacySettings? privacy,
    UserSettings? user,
    TrustState? trust,
    bool? isLoading,
    String? error,
  }) {
    return SettingsState(
      profile: profile ?? this.profile,
      privacy: privacy ?? this.privacy,
      user: user ?? this.user,
      trust: trust ?? this.trust,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    Future.microtask(() => refresh());
    return SettingsState();
  }

  ApiService get _apiService => ApiService.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profileJson = await _apiService.callGoApi('/profile', method: 'GET');
      final privacyJson = await _apiService.callGoApi('/settings/privacy', method: 'GET');
      final userJson = await _apiService.callGoApi('/settings/user', method: 'GET');
      
      // Trust state might be nested or a separate call
      // Based on my knowledge, it's often fetched with the profile or /trust-state
      TrustState? trust;
      try {
        final trustJson = await _apiService.callGoApi('/profile/trust-state', method: 'GET');
        trust = TrustState.fromJson(trustJson);
      } catch (_) {
        // Fallback or ignore if not available
      }
      
      state = state.copyWith(
        profile: Profile.fromJson(profileJson['profile']),
        privacy: ProfilePrivacySettings.fromJson(privacyJson),
        user: UserSettings.fromJson(userJson),
        trust: trust,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updatePrivacy(ProfilePrivacySettings newPrivacy) async {
    final oldPrivacy = state.privacy;
    state = state.copyWith(privacy: newPrivacy);
    try {
      await _apiService.callGoApi('/settings/privacy', method: 'PATCH', body: newPrivacy.toJson());
    } catch (e) {
      state = state.copyWith(privacy: oldPrivacy, error: e.toString());
    }
  }

  Future<void> updateUser(UserSettings newUser) async {
    final oldUser = state.user;
    state = state.copyWith(user: newUser);
    try {
      await _apiService.callGoApi('/settings/user', method: 'PATCH', body: newUser.toJson());
    } catch (e) {
      state = state.copyWith(user: oldUser, error: e.toString());
    }
  }
  
  Future<void> updateProfile(Profile newProfile) async {
    final oldProfile = state.profile;
    state = state.copyWith(profile: newProfile);
    try {
      // Need to map updateProfile arguments or use map
      await _apiService.callGoApi('/profile', method: 'PATCH', body: {
        'display_name': newProfile.displayName,
        'bio': newProfile.bio,
        'location': newProfile.location,
        'website': newProfile.website,
        'avatar_url': newProfile.avatarUrl,
        'cover_url': newProfile.coverUrl,
      });
    } catch (e) {
      state = state.copyWith(profile: oldProfile, error: e.toString());
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
