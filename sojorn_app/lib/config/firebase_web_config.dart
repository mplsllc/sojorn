// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:firebase_core/firebase_core.dart';

class FirebaseWebConfig {
  static const FirebaseOptions options = FirebaseOptions(
    apiKey: 'FIREBASE_API_KEY_REDACTED',
    authDomain: 'sojorn-a7a78.firebaseapp.com',
    projectId: 'sojorn-a7a78',
    storageBucket: 'sojorn-a7a78.firebasestorage.app',
    messagingSenderId: '486753572104',
    appId: '1:486753572104:web:d3e6ab825d1e008f9fc8bd',
    // measurementId intentionally omitted — Sojorn does not use Firebase Analytics.
    // Adding firebase_analytics package + measurementId would enable behavioral tracking,
    // which violates our privacy policy.
  );

  // IMPORTANT: Web push notifications require a VAPID key.
  // To generate one:
  // 1. Go to Firebase Console > Project Settings > Cloud Messaging
  // 2. Under "Web configuration", click "Generate key pair"
  // 3. Copy the public key and paste it below
  // Without a valid VAPID key, web push notifications will not work.
  
  // VAPID key for web push notifications
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
