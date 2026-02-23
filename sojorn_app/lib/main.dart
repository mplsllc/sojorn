// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:ui';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as flutter_quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'config/firebase_web_config.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/secure_chat_service.dart';
import 'services/simple_e2ee_service.dart';
import 'services/key_vault_service.dart';
import 'services/local_message_store.dart';
import 'services/sync_manager.dart';
import 'services/network_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart' as theme_provider;
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/feed_refresh_provider.dart';
import 'providers/header_state_provider.dart';
import 'services/chat_backup_manager.dart';
import 'providers/vault_provider.dart';
import 'routes/app_routes.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Register platform-native crypto implementations (WebCrypto on web,
      // SecureRandom/OS crypto on mobile). Must be called before any
      // AesGcm / X25519 / Hkdf operations.
      FlutterCryptography.enable();

      // Pre-warm message store so IndexedDB/Hive is ready before first chat open.
      unawaited(LocalMessageStore.instance.prewarm());

      // ── Global error handlers for freeze/crash diagnosis ──────────────
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        if (!kIsWeb) FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        debugPrint('\n╔══ FLUTTER ERROR ══════════════════════════════════');
        debugPrint('║ ${DateTime.now().toIso8601String()}');
        debugPrint('║ Library: ${details.library}');
        debugPrint('║ Context: ${details.context?.toDescription()}');
        debugPrint('║ Exception: ${details.exception}');
        if (details.stack != null) {
          debugPrint('║ Stack (first 8 frames):');
          final frames = details.stack.toString().split('\n').take(8);
          for (final f in frames) {
            debugPrint('║   $f');
          }
        }
        debugPrint('╚═══════════════════════════════════════════════════\n');
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        if (!kIsWeb) FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        debugPrint('\n╔══ PLATFORM ERROR ═════════════════════════════════');
        debugPrint('║ ${DateTime.now().toIso8601String()}');
        debugPrint('║ Error: $error');
        final frames = stack.toString().split('\n').take(8);
        for (final f in frames) {
          debugPrint('║   $f');
        }
        debugPrint('╚═══════════════════════════════════════════════════\n');
        return true;
      };

      if (kIsWeb) {
        await Firebase.initializeApp(options: FirebaseWebConfig.options);
      } else {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // NotoColorEmoji removed — OS provides emoji glyphs natively.
      // Loading it via GoogleFonts added ~10MB download on first load.

      // ── Frame timing watcher (web only) — logs jank > 100ms ──────────
      if (kIsWeb && kDebugMode) {
        SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
          for (final t in timings) {
            final buildMs = t.buildDuration.inMilliseconds;
            final rasterMs = t.rasterDuration.inMilliseconds;
            final totalMs = t.totalSpan.inMilliseconds;
            if (totalMs > 100) {
              debugPrint('⚠️ JANK FRAME: total=${totalMs}ms  build=${buildMs}ms  raster=${rasterMs}ms');
            }
          }
        });
      }

      usePathUrlStrategy();
      runApp(
        const ProviderScope(
          child: sojornApp(),
        ),
      );
    },
    (error, stackTrace) {
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      debugPrint('\n╔══ UNCAUGHT ASYNC ERROR ═══════════════════════════');
      debugPrint('║ ${DateTime.now().toIso8601String()}');
      debugPrint('║ Error: $error');
      final frames = stackTrace.toString().split('\n').take(8);
      for (final f in frames) {
        debugPrint('║   $f');
      }
      debugPrint('╚═══════════════════════════════════════════════════\n');
    },
  );
}

class sojornApp extends ConsumerStatefulWidget {
  const sojornApp({super.key});

  @override
  ConsumerState<sojornApp> createState() => _sojornAppState();
}

class _sojornAppState extends ConsumerState<sojornApp> with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  late final AuthService _authService = AuthService();
  SyncManager? _syncManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode) debugPrint('[APP] initState start ${DateTime.now().toIso8601String()}');
    _initDeepLinks();
    _listenForAuth();
    // Initialize network monitoring
    NetworkService().initialize();
    
    if (kDebugMode) debugPrint('[APP] initState sync complete — deferring heavy init');
    // Defer heavy work with real delays to avoid jank on first paint
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) debugPrint('[APP] Post-frame: starting deferred init');
      // E2EE init is now handled by VaultSetupGate to avoid racing ahead
      // of the vault restore prompt. Only notifications and sync here.
      Future.delayed(const Duration(milliseconds: 800), () {
        _initNotifications();
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        _initSyncManagerIfAuthenticated();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _authSub?.cancel();
    _notificationSub?.cancel();
    _syncManager?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) debugPrint('[APP] Lifecycle: $state  ${DateTime.now().toIso8601String()}');
    if (state == AppLifecycleState.resumed && _authService.isAuthenticated) {
      // Quick check: if chat keys were wiped (cache clear, etc.),
      // re-evaluate the vault gate so it can prompt for restore.
      if (!SimpleE2EEService().isReady) {
        if (kDebugMode) debugPrint('[APP] Keys missing after resume — re-checking vault');
        ref.invalidate(vaultSetupProvider);
      }
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[APP] Deep link init error: $e');
    }

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) { if (kDebugMode) debugPrint('[APP] Deep link stream error: $e'); },
    );
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'sojorn') return;
    if (uri.host == 'beacon') {
      final lat = double.tryParse(uri.queryParameters['lat'] ?? '');
      final long = double.tryParse(uri.queryParameters['long'] ?? '');
      if (lat != null && long != null) {
        AppRoutes.router.go(
          '/beacon?lat=${lat.toStringAsFixed(6)}&long=${long.toStringAsFixed(6)}',
        );
      }
    } else if (uri.host == 'verified') {
        ref.read(emailVerifiedEventProvider.notifier).set(true);
        
        if (_authService.isAuthenticated) {
             _authService.refreshSession();
        }
    }
  }

  void _initE2ee() async {
    if (_authService.isAuthenticated) {
      if (kDebugMode) debugPrint('[APP] Initializing E2EE…');
      await SimpleE2EEService().initialize();
      // Auto-sync vault after E2EE init (picks up any key changes)
      KeyVaultService.instance.autoSync();
    }
  }

  void _initNotifications() {
    if (_authService.isAuthenticated) {
      if (kDebugMode) debugPrint('[APP] Initializing notifications…');
      NotificationService.instance.init();
      _listenForNotifications();
    }
  }

  void _listenForAuth() {
    _authSub = _authService.authStateChanges.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        // Only re-init E2EE on token refresh (keys already loaded).
        // Initial sign-in E2EE is handled by VaultSetupGate.
        if (data.event == AuthChangeEvent.tokenRefreshed) {
          _initE2ee();
        }
        NotificationService.instance.init();
        _listenForNotifications();
        _ensureSyncManager();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _syncManager?.dispose();
        _syncManager = null;
        // Invalidate all user-specific providers to prevent data leaking between accounts
        ref.invalidate(settingsProvider);
        ref.invalidate(feedRefreshProvider);
        ref.invalidate(headerControllerProvider);
        ChatBackupManager.instance.reset();
      }
    });
  }

  void _initSyncManagerIfAuthenticated() {
    if (_authService.isAuthenticated) {
      _ensureSyncManager();
    }
  }

  void _ensureSyncManager() {
    if (_syncManager != null) return;
    if (kDebugMode) debugPrint('[APP] Starting SyncManager…');
    _syncManager = SyncManager(
      secureChatService: SecureChatService.instance,
      authService: _authService,
    );
    _syncManager!.init();
  }

  StreamSubscription? _notificationSub;

  void _listenForNotifications() {
    _notificationSub?.cancel();
    _notificationSub =
        NotificationService.instance.foregroundMessages.listen((message) {
      final context = AppRoutes.rootNavigatorKey.currentContext;
      if (context != null) {
        NotificationService.instance.showNotificationBanner(context, message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(theme_provider.themeProvider);

    AppTheme.setThemeType(themeMode == theme_provider.ThemeMode.pop
        ? AppThemeType.pop
        : AppThemeType.basic);

    return MaterialApp.router(
      title: 'sojorn',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalWidgetsLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        flutter_quill.FlutterQuillLocalizations.delegate,
      ],
      routerConfig: AppRoutes.router,
    );
  }
}
