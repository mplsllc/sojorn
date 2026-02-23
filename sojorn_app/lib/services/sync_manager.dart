// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'auth_service.dart';
import 'chat_backup_manager.dart';
import 'secure_chat_service.dart';
import 'simple_e2ee_service.dart';
import 'local_message_store.dart';

class SyncManager with WidgetsBindingObserver {
  final SecureChatService _secureChatService;
  final AuthService _authService;
  final SimpleE2EEService _e2ee = SimpleE2EEService();
  final LocalMessageStore _localStore = LocalMessageStore.instance;
  final Duration _resumeThreshold;
  final Duration _syncInterval;

  Timer? _timer;
  StreamSubscription<AuthState>? _authSub;
  DateTime? _lastSyncAt;
  bool _syncInProgress = false;
  bool _initialized = false;
  bool _hydrating = false;

  SyncManager({
    required SecureChatService secureChatService,
    required AuthService authService,
    Duration resumeThreshold = const Duration(minutes: 2),
    Duration syncInterval = const Duration(minutes: 5),
  })  : _secureChatService = secureChatService,
        _authService = authService,
        _resumeThreshold = resumeThreshold,
        _syncInterval = syncInterval;

  void init() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    _authSub = _authService.authStateChanges.listen(_handleAuthChange);

    if (_authService.isAuthenticated) {
      _startTimer();
      // Defer heavy sync work so the UI thread isn't blocked
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_initialized) return;
        if (kDebugMode) debugPrint('[SyncManager] Deferred startup sync starting');
        // On web, skip eager chat sync — Hive/IndexedDB is too slow to open
        // at startup (~130s). Chat loads lazily when user opens a conversation.
        if (!kIsWeb) {
          unawaited(ensureHistoryLoaded());
          _triggerSync(reason: 'startup');
        }
      });
    }
  }

  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _authSub = null;
    _stopTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_authService.isAuthenticated) {
        _startTimer();
        _syncIfStale();
      }
    } else if (state == AppLifecycleState.paused) {
      _stopTimer();
      // Trigger backup when app goes to background
      ChatBackupManager.instance.triggerBackupIfNeeded();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopTimer();
    }
  }

  void _handleAuthChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.tokenRefreshed) {
      _startTimer();
      if (!kIsWeb) {
        unawaited(ensureHistoryLoaded());
        _triggerSync(reason: 'auth');
      }
    } else if (state.event == AuthChangeEvent.signedOut) {
      _lastSyncAt = null;
      _stopTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_syncInterval, (_) {
      if (_authService.isAuthenticated && !kIsWeb) {
        _triggerSync(reason: 'timer');
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _syncIfStale() {
    if (_lastSyncAt == null ||
        DateTime.now().difference(_lastSyncAt!) > _resumeThreshold) {
      _triggerSync(reason: 'resume');
    }
  }

  Future<void> _triggerSync({required String reason}) async {
    if (!_authService.isAuthenticated || _syncInProgress) return;
    _syncInProgress = true;
    try {

      await _e2ee.initialize();
      if (!_e2ee.isReady) {
        return;
      }

      // On web, skip eager hydration — Hive/IndexedDB startup is too slow.
      if (!kIsWeb) {
        await ensureHistoryLoaded();
      }

      await _secureChatService.syncAllConversations(force: true);
      _lastSyncAt = DateTime.now();

      // Schedule auto-backup after successful sync
      ChatBackupManager.instance.scheduleBackup();
    } catch (e) {
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> ensureHistoryLoaded() async {
    if (!_authService.isAuthenticated || _hydrating) return;
    _hydrating = true;
    try {
      await _e2ee.initialize();
      if (!_e2ee.isReady) {
        return;
      }

      final conversations = await _secureChatService.getConversations();
      for (final conv in conversations) {
        final isEmpty =
            (await _localStore.getMessageIdsForConversation(conv.id)).isEmpty;
        if (isEmpty) {
          await _secureChatService.fetchAndDecryptHistory(conv.id, limit: 50);
        }
        await _secureChatService.startLiveListener(conv.id);
      }
    } catch (e) {
    } finally {
      _hydrating = false;
    }
  }
}
