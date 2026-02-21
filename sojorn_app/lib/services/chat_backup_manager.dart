// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'simple_e2ee_service.dart';
import 'key_vault_service.dart';
import 'local_key_backup_service.dart';
import 'local_message_store.dart';
import 'auth_service.dart';

/// Manages automatic encrypted cloud backups of chat data.
///
/// Unified with KeyVaultService: uses the vault passphrase to encrypt
/// chat message backups. Auto-enabled when the encryption vault is set up.
/// No separate password needed — one passphrase protects everything.
class ChatBackupManager {
  static final ChatBackupManager _instance = ChatBackupManager._internal();
  static ChatBackupManager get instance => _instance;

  ChatBackupManager._internal();

  static const String _passwordKey = 'chat_backup_password_v1'; // Legacy
  static const String _enabledKey = 'chat_backup_enabled';
  static const String _lastBackupKey = 'chat_backup_last_at';
  static const String _lastBackupCountKey = 'chat_backup_last_msg_count';
  static const Duration _minBackupInterval = Duration(minutes: 10);
  static const int _minNewMessages = 1;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final SimpleE2EEService _e2ee = SimpleE2EEService();

  Timer? _debounceTimer;
  bool _backupInProgress = false;
  DateTime? _lastBackupAt;
  int _lastBackupMessageCount = 0;
  bool? _enabledCache;

  /// Whether backup is enabled.
  /// Now auto-enabled when vault is set up — no separate toggle needed.
  Future<bool> get isEnabled async {
    if (_enabledCache != null) return _enabledCache!;
    // Auto-enable if vault is set up
    final vaultReady = await KeyVaultService.instance.isVaultSetup();
    if (vaultReady) {
      _enabledCache = true;
      return true;
    }
    // Fallback: check legacy flag
    final prefs = await SharedPreferences.getInstance();
    _enabledCache = prefs.getBool(_enabledKey) ?? false;
    return _enabledCache!;
  }

  /// Whether a backup password is available (vault passphrase or legacy).
  Future<bool> get hasPassword async {
    // Prefer vault passphrase
    final vaultPw = await _getPassword();
    return vaultPw != null && vaultPw.isNotEmpty;
  }

  /// Get the encryption password — unified from vault passphrase.
  Future<String?> _getPassword() async {
    // 1. Try vault's cached passphrase (primary)
    final vaultPw = await _secureStorage.read(key: 'vault_cached_passphrase');
    if (vaultPw != null && vaultPw.isNotEmpty) return vaultPw;
    // 2. Fallback to legacy separate password
    return await _secureStorage.read(key: _passwordKey);
  }

  /// Last backup timestamp
  Future<DateTime?> get lastBackupAt async {
    if (_lastBackupAt != null) return _lastBackupAt;
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastBackupKey);
    if (ms != null) {
      _lastBackupAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return _lastBackupAt;
  }

  /// Number of messages in last backup
  Future<int> get lastBackupMessageCount async {
    if (_lastBackupMessageCount > 0) return _lastBackupMessageCount;
    final prefs = await SharedPreferences.getInstance();
    _lastBackupMessageCount = prefs.getInt(_lastBackupCountKey) ?? 0;
    return _lastBackupMessageCount;
  }

  /// Set up backup: enable auto-backup using vault passphrase.
  /// The password parameter is accepted for legacy compatibility but
  /// the vault passphrase is preferred automatically.
  Future<void> enable([String? password]) async {
    if (password != null) {
      await _secureStorage.write(key: _passwordKey, value: password);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    _enabledCache = true;

    // Perform initial backup immediately
    await _performBackup();
  }

  /// Disable auto-backup (does NOT clear vault passphrase — that's vault's job).
  Future<void> disable() async {
    await _secureStorage.delete(key: _passwordKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    _enabledCache = false;
    _debounceTimer?.cancel();
  }

  /// Change the backup password. Re-encrypts and uploads immediately.
  /// Deprecated: password now comes from vault passphrase.
  Future<void> changePassword(String newPassword) async {
    await _secureStorage.write(key: _passwordKey, value: newPassword);
    await _performBackup();
  }

  /// Schedule a backup after a debounce period.
  /// Call this after sending/receiving messages.
  void scheduleBackup() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 30), () {
      _tryAutoBackup();
    });
  }

  /// Trigger an immediate backup if conditions are met.
  /// Called by SyncManager after sync, or on app background.
  Future<void> triggerBackupIfNeeded() async {
    await _tryAutoBackup();
  }

  /// Force an immediate backup regardless of schedule.
  Future<void> forceBackup() async {
    await _performBackup();
  }

  /// Restore from cloud backup using the given password.
  /// Returns restore result with counts.
  Future<Map<String, dynamic>> restoreFromCloud(String password) async {
    return await LocalKeyBackupService.restoreFromCloud(
      password: password,
      e2eeService: _e2ee,
    );
  }

  /// Get current local message count for status display.
  Future<int> getLocalMessageCount() async {
    final records = await LocalMessageStore.instance.getAllMessageRecords();
    return records.length;
  }

  /// Clear all local message data.
  Future<void> clearLocalMessages() async {
    await LocalMessageStore.instance.clearAll();
  }

  /// Reset everything on sign-out.
  void reset() {
    _debounceTimer?.cancel();
    _lastBackupAt = null;
    _lastBackupMessageCount = 0;
    _enabledCache = null;
    _backupInProgress = false;
  }

  // --- Private ---

  Future<void> _tryAutoBackup() async {
    if (_backupInProgress) return;
    if (!AuthService.instance.isAuthenticated) return;

    final enabled = await isEnabled;
    if (!enabled) return;

    final hasPw = await hasPassword;
    if (!hasPw) return;

    // Check minimum interval
    final last = await lastBackupAt;
    if (last != null && DateTime.now().difference(last) < _minBackupInterval) {
      return;
    }

    // Check if there are new messages since last backup
    final currentCount = await getLocalMessageCount();
    final lastCount = await lastBackupMessageCount;
    if (currentCount <= 0) return;
    if (currentCount - lastCount < _minNewMessages && last != null) return;

    await _performBackup();
  }

  Future<void> _performBackup() async {
    if (_backupInProgress) return;
    _backupInProgress = true;

    try {
      final password = await _getPassword();
      if (password == null || password.isEmpty) {
        if (kDebugMode) debugPrint('[ChatBackup] No password available (vault not set up?)');
        return;
      }

      if (!_e2ee.isReady) {
        await _e2ee.initialize();
        if (!_e2ee.isReady) return;
      }

      final backup = await LocalKeyBackupService.createEncryptedBackup(
        password: password,
        e2eeService: _e2ee,
        includeMessages: true,
        includeKeys: true,
      );

      await LocalKeyBackupService.uploadToCloud(backup: backup);

      // Record success
      final now = DateTime.now();
      _lastBackupAt = now;
      final msgCount = await getLocalMessageCount();
      _lastBackupMessageCount = msgCount;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastBackupKey, now.millisecondsSinceEpoch);
      await prefs.setInt(_lastBackupCountKey, msgCount);

      if (kDebugMode) debugPrint('[ChatBackup] Auto-backup complete: $msgCount messages');
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatBackup] Auto-backup failed: $e');
    } finally {
      _backupInProgress = false;
    }
  }
}
