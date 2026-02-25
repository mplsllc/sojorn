// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:firebase_core/firebase_core.dart';

// Firebase config is injected at build time via --dart-define flags.
// For local web builds, create sojorn_app/dart-defines.env (gitignored):
//   FIREBASE_API_KEY=AIzaSy...
//   FIREBASE_APP_ID=1:486753572104:web:...
// Then build with: flutter build web $(cat dart-defines.env | sed 's/^/--dart-define=/' | tr '\n' ' ')

class FirebaseWebConfig {
  static const FirebaseOptions options = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    authDomain: 'sojorn-a7a78.firebaseapp.com',
    projectId: 'sojorn-a7a78',
    storageBucket: 'sojorn-a7a78.firebasestorage.app',
    messagingSenderId: '486753572104',
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    // measurementId intentionally omitted — Sojorn does not use Firebase Analytics.
    // Adding firebase_analytics package + measurementId would enable behavioral tracking,
    // which violates our privacy policy.
  );

  /// Whether Firebase is properly configured for web (API key + App ID provided via --dart-define).
  /// When false, FCM should be skipped gracefully — push notifications won't work but the app runs fine.
  static bool get isConfigured =>
      options.apiKey.isNotEmpty && options.appId.isNotEmpty;

  // VAPID key for web push notifications (public key — safe to commit).
  // From Firebase Console > Cloud Messaging > Web Push certificates
  static const String _vapidKey = 'BKD_nCyWx5aIrsHQ_bXj4nKK0_N1dURrJU0t9t2FxjzlExaOC7dpvnPKsbGZ228yP7EEAU60dGq1UER8sjwQ4Ls';

  /// Returns the VAPID key if configured, null otherwise
  static String? get vapidKey {
    if (_vapidKey.isEmpty || _vapidKey == 'YOUR_VAPID_KEY_HERE') {
      return null;
    }
    return _vapidKey;
  }
}
