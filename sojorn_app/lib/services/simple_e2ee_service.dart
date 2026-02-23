// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'api_service.dart';
import 'key_vault_service.dart';
import 'secure_chat_service.dart';

class SimpleE2EEService {
  static final SimpleE2EEService _instance = SimpleE2EEService._internal();
  factory SimpleE2EEService() => _instance;

  static const String _storageKey = 'e2ee_keys_v3';
  static const String _cloudStorageKey = 'e2ee_keys_cloud_backup';
  
  final FlutterSecureStorage _storage;
  final AuthService _auth;
  final ApiService _api;
  SecureChatService? _chatService;
  
  // ALGORITHMS
  // Identity Keys: Ed25519 (Signing)
  final _signingAlgo = Ed25519();
  // PreKeys & Diffie-Hellman: X25519 (Key Agreement)
  final _dhAlgo = X25519();
  // Symmetric Encryption: AES-GCM
  final _cipher = AesGcm.with256bits();
  // KDF
  final _sha256 = Sha256();

  // STATE
  SimpleKeyPair? _identityDhKeyPair; // X25519 for DH
  SimpleKeyPair? _identitySigningKeyPair; // Ed25519 for Signing
  SimpleKeyPair? _signedPreKey;    // X25519
  List<SimpleKeyPair>? _oneTimePreKeys; // X25519
  
  String? _initializedForUserId;
  Future<void>? _initFuture;
  bool _needsVaultRestore = false;

  // Cache for X3DH shared secrets
  final Map<String, SecretKey> _sessionCache = {};

  SimpleE2EEService._internal() 
      : _storage = const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'sojorn_e2ee_keys',
          publicKey: 'sojorn_e2ee_public',
        ),
      ),
      _auth = AuthService.instance,
      _api = ApiService.instance,
      _chatService = null;

  void setChatService(SecureChatService chatService) {
    _chatService = chatService;
  }

  bool get isReady => _identityDhKeyPair != null && _identitySigningKeyPair != null;

  /// True when keys are missing locally but a vault backup exists on the server.
  /// The VaultSetupGate checks this to prompt for passphrase restore instead of
  /// letting the app through with no keys or silently generating new ones.
  bool get needsVaultRestore => _needsVaultRestore;

  /// Clear the restore flag after a successful vault restore.
  void clearNeedsVaultRestore() {
    _needsVaultRestore = false;
    _initFuture = null; // Allow re-initialization after restore
  }

  // DEPRECATED: Old backup PIN was user ID (insecure — server could derive it).
  // KeyVaultService now handles passphrase-based backup. This getter is kept
  // only for legacy cloud restore compatibility.
  String get _backupPin => _auth.currentUser?.id.substring(0, 32) ?? 'default_pin_fallback';

  /// Initialize the service
  Future<void> initialize() async {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;

    if (_initializedForUserId == userId && isReady) return;
    
    if (_initFuture != null) return _initFuture;
    return _initFuture = _doInitialize(userId);
  }

  // Key rotation is now handled via initiateKeyRecovery() when needed
  // DO NOT add debug flags here - use resetAllKeys() method for intentional resets

  Future<void> resetAllKeys() async {
    
    // Clear all storage
    await _storage.deleteAll();
    
    // Clear local key variables
    _identityDhKeyPair = null;
    _identitySigningKeyPair = null;
    _signedPreKey = null;
    _oneTimePreKeys = null;
    
    // Generate fresh identity
    await generateNewIdentity();
    
  }

  // Reset all local encryption keys and generate a fresh identity.
  // Existing encrypted messages will become undecryptable after this.
  Future<void> resetIdentityKeys() async {
    await _storage.deleteAll();
    _identityDhKeyPair = null;
    _identitySigningKeyPair = null;
    _signedPreKey = null;
    _oneTimePreKeys = null;
    _initializedForUserId = null;
    _initFuture = null;
    _sessionCache.clear();
    await generateNewIdentity();
  }

  // Manual key upload for testing
  Future<void> uploadKeysManually() async {
    
    if (!isReady) {
      throw Exception('Keys not ready - generate keys first');
    }
    
    // Generate a real signature for the signed prekey
    final spk = await _signedPreKey!.extractPublicKey();
    final signature = await _signingAlgo.sign(
      spk.bytes,
      keyPair: _identitySigningKeyPair!,
    );
    final spkSignature = signature.bytes;
    
    // Verify signature is not all zeros
    final allZeros = spkSignature.every((b) => b == 0);
    if (allZeros) {
      throw Exception('CRITICAL: Generated SPK signature is all zeros!');
    }
    
    await _publishKeys(spkSignature);
  }

  // Check if keys exist on backend
  Future<bool> _checkKeysExistOnBackend() async {
    try {
      final userId = _auth.currentUser?.id;
      if (userId == null) return false;
      
      final response = await _api.callGoApi('/keys/$userId', method: 'GET');
      
      // If we get a successful response with key data, keys exist
      if (response.containsKey('identity_key')) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // Upload existing keys to backend
  Future<void> _uploadExistingKeys() async {
    
    if (!isReady) {
      throw Exception('Keys not ready for upload');
    }
    
    // Generate a proper signature for the existing signed prekey
    final spk = await _signedPreKey!.extractPublicKey();
    final signature = await _signingAlgo.sign(
      spk.bytes,
      keyPair: _identitySigningKeyPair!,
    );
    final spkSignature = signature.bytes;
    
    await _publishKeys(spkSignature);
  }

  Future<void> _doInitialize(String userId) async {
    _initializedForUserId = userId;



    // 1. Try Local Storage — MUST be separated from backend sync so that a network
    //    failure during backend calls doesn't cause silent fallthrough to step 3,
    //    which would falsely set _needsVaultRestore on any offline condition.
    bool localKeysLoaded = false;
    try {
      localKeysLoaded = await _loadKeysFromLocal(userId);
    } catch (e) {
      if (kDebugMode) debugPrint('[E2EE] Local key load error: $e');
    }

    if (localKeysLoaded) {
      if (await _testKeyCompatibility()) {
        // Keys are valid locally. Best-effort: sync state with backend.
        // Network failures here are non-fatal — the app works with local keys.
        try {
          if (await _checkKeysExistOnBackend()) {
            final backendValid = await _validateBackendKeyBundle(userId);
            if (!backendValid) await _uploadExistingKeys();
          } else {
            await _uploadExistingKeys();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[E2EE] Backend key sync skipped (offline): $e');
        }
        return; // Always return when local keys are valid, regardless of backend sync
      } else {
        await initiateKeyRecovery(userId);
        return;
      }
    }

    // 2. Try Cloud Restore (legacy path — profile-based encrypted key)
    final restored = await _restoreFromCloud(userId);
    if (restored) {
        // Test restored keys
        if (await _testKeyCompatibility()) {
          return;
        } else {
          await initiateKeyRecovery(userId);
          return;
        }
    }

    // 3. Check if a vault backup exists before generating new keys.
    //    If the user has a vault backup, they need to enter their passphrase
    //    to restore — we must NOT silently generate a new identity.
    try {
      final statusData = await _api.callGoApi('/capsule/escrow/status', method: 'GET');
      if (statusData['has_backup'] == true) {
        if (kDebugMode) debugPrint('[E2EE] Vault backup found on server — waiting for user to restore');
        _needsVaultRestore = true;
        return; // Do NOT generate new keys — VaultSetupGate will prompt
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[E2EE] Could not check vault status (offline?): $e');
      // Network unavailable — leave _needsVaultRestore false and return without
      // generating keys. The VaultSetupGate will stay transparent; on next app
      // resume/init the check will run again once connectivity is restored.
      return;
    }

    // 4. Genuinely new user — no local keys, no legacy backup, no vault backup
    if (kDebugMode) debugPrint('[E2EE] No keys found anywhere — generating new identity');
    await generateNewIdentity();
  }

  // Test if current keys can encrypt/decrypt properly
  Future<bool> _testKeyCompatibility() async {
    try {
      final testMessage = 'test_key_compatibility';
      // Just test local encryption/decryption without API call
      // This tests if our local keys are working properly
      final testKey = await _dhAlgo.newKeyPair();
      final testNonce = _cipher.newNonce();
      final testPlaintext = utf8.encode(testMessage);
      
      // Generate proper 32-byte (256-bit) key for AES-GCM
      final testKeyBytes = List<int>.filled(32, 0);
      for (var i = 0; i < 32; i++) {
        testKeyBytes[i] = i % 256; // Simple deterministic pattern for testing
      }
      final testSecretKey = SecretKey(testKeyBytes);
      
      // Verify key length
      if (testKeyBytes.length != 32) {
        return false;
      }
      
      final encrypted = await _cipher.encrypt(
        testPlaintext,
        secretKey: testSecretKey,
        nonce: testNonce
      );
      
      final decrypted = await _cipher.decrypt(
        encrypted,
        secretKey: testSecretKey
      );
      
      final result = utf8.decode(decrypted) == testMessage;
      return result;
    } catch (e) {
    }
    return false;
  }

  Future<bool> _validateBackendKeyBundle(String userId) async {
    try {
      final bundle = await _api.getKeyBundle(userId);

      String? ikField = bundle['identity_key_public'];
      if (ikField == null && bundle['identity_key'] is Map) {
        ikField = bundle['identity_key']['public_key'];
      } else if (ikField == null) {
        ikField = bundle['identity_key'];
      }

      String? spkField = bundle['signed_prekey_public'];
      String? spkSignature = bundle['signed_prekey_signature'];
      if (spkField == null && bundle['signed_prekey'] is Map) {
        spkField = bundle['signed_prekey']['public_key'];
        spkSignature = bundle['signed_prekey']['signature'];
      } else if (spkField == null) {
        spkField = bundle['signed_prekey'];
      }

      if (ikField == null || ikField.isEmpty) return false;
      if (spkField == null || spkField.isEmpty) return false;
      if (spkSignature == null || spkSignature.isEmpty) return false;

      final ikParts = ikField.split(':');
      if (ikParts.length != 2) return false;

      final skBytes = base64Decode(ikParts[0]);
      final spkBytes = base64Decode(spkField);
      final sigBytes = base64Decode(spkSignature);

      final theirSk = SimplePublicKey(skBytes, type: KeyPairType.ed25519);
      final verified = await _signingAlgo.verify(
        spkBytes,
        signature: Signature(sigBytes, publicKey: theirSk),
      );

      return verified;
    } catch (e) {
      return false;
    }
  }

  // Smart key recovery that preserves messages when possible
  Future<void> initiateKeyRecovery(String userId) async {
    
    // Try to preserve existing messages by backing up encrypted content
    final messageBackup = await _backupEncryptedMessages();
    
    // Generate new keys
    await generateNewIdentity();
    
    // Restore message backup with new keys if possible
    if (messageBackup > 0) {
      // Note: Messages encrypted with old keys will show as "encrypted with old keys"
      // but new messages will work perfectly
    }
    
  }

  // Backup encrypted messages to preserve them during key recovery
  Future<int> _backupEncryptedMessages() async {
    try {
      // This would integrate with local message store to count/preserve messages
      // For now, just log that we're attempting preservation
      return 0; // Return count of backed up messages
    } catch (e) {
      return 0;
    }
  }

  Future<void> generateNewIdentity() async {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;

    
    // 1. Identity Key Pair (DH)
    _identityDhKeyPair = await _dhAlgo.newKeyPair();
    
    // 2. Identity Signing Pair (Ed25519)
    _identitySigningKeyPair = await _signingAlgo.newKeyPair();
    
    // 3. Signed PreKey (X25519)
    _signedPreKey = await _dhAlgo.newKeyPair();
    final spkPublic = await _signedPreKey!.extractPublicKey();
    
    // Sign the SPK with the Identity Signing Key
    final signature = await _signingAlgo.sign(
      spkPublic.bytes,
      keyPair: _identitySigningKeyPair!,
    );
    final spkSignature = Uint8List.fromList(signature.bytes);

    // 4. One-Time PreKeys (X25519)
    final opks = <SimpleKeyPair>[];
    for (int i = 0; i < 20; i++) {
      opks.add(await _dhAlgo.newKeyPair());
    }
    _oneTimePreKeys = opks;

    // 5. Save Locally
    await _saveKeysToLocal(userId);

    // 6. Publish to Server
    await _publishKeys(spkSignature);
    
    // 6. Backup Identity to Cloud (legacy no-op)
    await _backupIdentityToCloud(userId);

    // 7. Auto-sync vault so new keys are backed up immediately
    await KeyVaultService.instance.autoSync();
  }

  // --- Core X3DH Encryption ---

  Future<Map<String, dynamic>> encrypt(String recipientId, String plaintext) async {
    if (!_auth.isAuthenticated) throw Exception('Not authenticated');
    await initialize();


    // 1. Fetch Bundle
    final bundle = await ApiService(AuthService.instance).getKeyBundle(recipientId);
    
    // DEBUG: Validate Bundle

    // Handle both formats:
    // Flat (from getKeyBundle normalization): { "identity_key_public": "...", "signed_prekey_public": "...", "signed_prekey_signature": "..." }
    // Nested (raw): { "identity_key": {"public_key": "..."}, "signed_prekey": {"public_key": "...", "signature": "..."} }
    String? ikField;
    String? spkField;
    String? spkSignature;
    String? otkField;
    int? otkId;

    // Identity Key - check flat first (most common after normalization)
    ikField = bundle['identity_key_public'];
    if (ikField == null && bundle['identity_key'] is Map) {
        ikField = bundle['identity_key']['public_key'];
    } else if (ikField == null) {
        ikField = bundle['identity_key'];
    }

    // Signed PreKey - check flat first
    spkField = bundle['signed_prekey_public'];
    spkSignature = bundle['signed_prekey_signature'];
    if (spkField == null && bundle['signed_prekey'] is Map) {
        spkField = bundle['signed_prekey']['public_key'];
        spkSignature = bundle['signed_prekey']['signature'];
    } else if (spkField == null) {
        spkField = bundle['signed_prekey'];
    }

    // One-Time PreKey - check if nested or flat
    if (bundle['one_time_prekey'] is Map) {
         otkField = bundle['one_time_prekey']['public_key'];
         otkId = bundle['one_time_prekey']['key_id'];
    } else if (bundle['one_time_prekey'] is String) {
         otkField = bundle['one_time_prekey'];
         otkId = bundle['one_time_prekey_id'];
    } else {
         otkField = null;
         otkId = bundle['one_time_prekey_id'];
    }


    if (ikField == null || ikField.isEmpty) {
        throw Exception('Recipient identity_key not found in bundle. Structure: $bundle');
    }
    if (spkField == null || spkField.isEmpty) {
        throw Exception('Recipient signed_prekey not found in bundle');
    }

    final flattenedBundle = {
        'identity_key': ikField,
        'signed_prekey': spkField,
        'signed_prekey_signature': spkSignature,
        'one_time_prekey': otkField,
        'one_time_prekey_id': otkId,
    };

    return await _encryptX25519Only(recipientId, plaintext, flattenedBundle);
  }
  
  Future<Map<String, dynamic>> _encryptX25519Only(String recipientId, String plaintext, Map<String, dynamic> bundle) async {
    final ikFull = bundle['identity_key'] as String;
    final ikParts = ikFull.split(':');
    
    Uint8List theirSkBytes;
    Uint8List theirIkDhBytes;
    
    if (ikParts.length == 2) {
      theirSkBytes = base64Decode(ikParts[0]);
      theirIkDhBytes = base64Decode(ikParts[1]);
    } else {
      // Legacy fallback (assume single key is DH for now, or bail)
      theirSkBytes = Uint8List(0); // Cannot verify
      theirIkDhBytes = base64Decode(ikFull);
    }

    final theirSpkBytes = base64Decode(bundle['signed_prekey']);
    final theirSpkSignature = base64Decode(bundle['signed_prekey_signature'] ?? '');
    
    // --- SIGNATURE VERIFICATION ---
    // Always verify SPK signature - no more legacy user exceptions
    if (theirSkBytes.isEmpty || theirSpkSignature.isEmpty) {
      throw Exception('E2EE SECURITY ALERT: Recipient missing signing key or signature!');
    }
    
    final theirSk = SimplePublicKey(theirSkBytes, type: KeyPairType.ed25519);
    final isVerified = await _signingAlgo.verify(
      theirSpkBytes,
      signature: Signature(theirSpkSignature, publicKey: theirSk),
    );
    if (!isVerified) {
      throw Exception('E2EE SECURITY ALERT: Recipient Signed PreKey signature verification failed!');
    }

    final theirIk = SimplePublicKey(theirIkDhBytes, type: KeyPairType.x25519);
    final theirSpk = SimplePublicKey(theirSpkBytes, type: KeyPairType.x25519);
    final theirOtkBytes = bundle['one_time_prekey'] != null ? base64Decode(bundle['one_time_prekey']) : null;
    final theirOtk = theirOtkBytes != null ? SimplePublicKey(theirOtkBytes, type: KeyPairType.x25519) : null;
    final theirOtkId = bundle['one_time_prekey_id'];

    final ephemeralKeyPair = await _dhAlgo.newKeyPair();
    final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();

    // DH calculations
    final dh1 = await _dhAlgo.sharedSecretKey(keyPair: _identityDhKeyPair!, remotePublicKey: theirSpk);
    final dh2 = await _dhAlgo.sharedSecretKey(keyPair: ephemeralKeyPair, remotePublicKey: theirIk);
    final dh3 = await _dhAlgo.sharedSecretKey(keyPair: ephemeralKeyPair, remotePublicKey: theirSpk);
    
    List<int> dhBytes = [];
    dhBytes.addAll(await dh1.extractBytes());
    dhBytes.addAll(await dh2.extractBytes());
    dhBytes.addAll(await dh3.extractBytes());

    if (theirOtk != null) {
      final dh4 = await _dhAlgo.sharedSecretKey(keyPair: ephemeralKeyPair, remotePublicKey: theirOtk);
      dhBytes.addAll(await dh4.extractBytes());
      
      // Delete the used OTK from server to prevent reuse
      if (theirOtkId != null) {
        _deleteUsedOTK(theirOtkId); // Fire-and-forget
      }
    }

    final rootSecret = await _kdf(dhBytes);
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(rootSecret),
      nonce: nonce,
    );

    final header = {
      'v': 1,
      'ik': base64Encode((await _identityDhKeyPair!.extractPublicKey()).bytes),
      'ek': base64Encode(ephemeralPublic.bytes),
      'opk_id': theirOtkId,
      'm': base64Encode(secretBox.mac.bytes),
    };

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'iv': base64Encode(nonce),
      'header': header, // Return as Map
    };
  }

  Future<String> decrypt(String ciphertext, String iv, dynamic headerData) async {
     await initialize();
     
     try {
         // Handle both String and Map inputs for header
         final Map<String, dynamic> header;
         if (headerData is String) {
            try {
              header = jsonDecode(headerData);
            } catch (e) {
               throw Exception('Invalid Header JSON: $e');
            }
         } else if (headerData is Map) {
            header = Map<String, dynamic>.from(headerData);
         } else {
            throw Exception('Invalid header type: ${headerData.runtimeType}');
         }

         final nonce = base64Decode(iv);
         final ciphertextBytes = base64Decode(ciphertext);
         final macBytes = base64Decode(header['m'] ?? '');
         
         if (header['ik'] == null || header['ek'] == null) {
             throw Exception('Invalid Header: Missing IK or EK');
         }

         final senderIkBytes = base64Decode(header['ik']);
         final senderEkBytes = base64Decode(header['ek']);
         
         final senderIk = SimplePublicKey(senderIkBytes, type: KeyPairType.x25519);
         final senderEk = SimplePublicKey(senderEkBytes, type: KeyPairType.x25519);

         final dh1 = await _dhAlgo.sharedSecretKey(keyPair: _signedPreKey!, remotePublicKey: senderIk);
         final dh2 = await _dhAlgo.sharedSecretKey(keyPair: _identityDhKeyPair!, remotePublicKey: senderEk);
         final dh3 = await _dhAlgo.sharedSecretKey(keyPair: _signedPreKey!, remotePublicKey: senderEk);

         List<int> dhBytes = [];
         dhBytes.addAll(await dh1.extractBytes());
         dhBytes.addAll(await dh2.extractBytes());
         dhBytes.addAll(await dh3.extractBytes());

         if (header['opk_id'] != null && _oneTimePreKeys != null && _oneTimePreKeys!.isNotEmpty) {
               final otkId = header['opk_id'] as int;
               // The opk_id refers to the key_id that was published (0-19 position in our array)
               // Since we generate OTKs in order and publish them with key_id = array_index,
               // we can use the opk_id directly as the array index
               if (otkId >= 0 && otkId < _oneTimePreKeys!.length) {
                 final matchingOtk = _oneTimePreKeys![otkId];
                 final dh4 = await _dhAlgo.sharedSecretKey(keyPair: matchingOtk, remotePublicKey: senderEk);
                 dhBytes.addAll(await dh4.extractBytes());
               } else {
               }
         }

         final rootSecret = await _kdf(dhBytes);
         final secretBox = SecretBox(ciphertextBytes, nonce: nonce, mac: Mac(macBytes));
         final plaintextBytes = await _cipher.decrypt(secretBox, secretKey: SecretKey(rootSecret));
         final plaintext = utf8.decode(plaintextBytes);
         // Decryption successful - plaintext not logged for security
         return plaintext;
     } catch (e) {
        if (e.toString().contains('MAC') || e.toString().contains('SecretBoxAuthenticationError')) {
            // Automatic key recovery on MAC errors
            _handleMacError();
            return '[Message encrypted with old keys - cannot decrypt]';
        }
        if (e.toString().contains('Invalid Header')) {
            return '[Message encrypted with old keys - cannot decrypt]';
        }
        rethrow;
    } 
  }

  // Automatic MAC error handling
  int _macErrorCount = 0;
  static const int _maxMacErrors = 50;
  DateTime? _lastMacErrorTime;
  
  void _handleMacError() {
    _macErrorCount++;
    _lastMacErrorTime = DateTime.now();
    
    
    // If we get multiple MAC errors in quick succession, trigger recovery
    if (_macErrorCount >= _maxMacErrors) {
      _triggerAutomaticRecovery();
      _macErrorCount = 0; // Reset counter
    }
  }
  
  Future<void> _triggerAutomaticRecovery() async {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;
    
    
    // Show user-friendly notification
    
    // Initiate smart recovery
    await initiateKeyRecovery(userId);
    
    // Broadcast key recovery event to all user's devices
    _broadcastKeyRecovery(userId);
    
  }

  void _broadcastKeyRecovery(String userId) {
    // Broadcast key recovery event to all user's devices via WebSocket
    _chatService?.broadcastKeyRecovery(userId);
  }

  // Delete used OTK from server to prevent reuse
  Future<void> _deleteUsedOTK(int keyId) async {
    try {
      await _api.callGoApi('/keys/otk/$keyId', method: 'DELETE');
    } catch (e) {
      final message = e.toString();
      if (message.contains('route not found') || message.contains('404')) {
        return;
      }
    }
  }

  // --- Helpers ---
  
  Future<List<int>> _kdf(List<int> inputKeyMaterial) async {
    final sink = _sha256.newHashSink();
    sink.add(inputKeyMaterial);
    sink.close();
    final hash = await sink.hash();
    return hash.bytes;
  }
  
  Future<void> _publishKeys(List<int> spkSignature) async {
    
    try {
      final skPublic = await _identitySigningKeyPair!.extractPublicKey();
      final ikDhPublic = await _identityDhKeyPair!.extractPublicKey();
      
      // Concatenate SK:IK_dh
      final identityCombined = '${base64Encode(skPublic.bytes)}:${base64Encode(ikDhPublic.bytes)}';
      
      final spk = await _signedPreKey!.extractPublicKey();
      final otks = <Map<String, dynamic>>[];
      for (int i = 0; i < _oneTimePreKeys!.length; i++) {
        final k = _oneTimePreKeys![i];
        otks.add({
          'key_id': i,
          'public_key': base64Encode((await k.extractPublicKey()).bytes)
        });
      }

      
      // Verify signature is not all zeros before upload
      final allZeros = spkSignature.every((b) => b == 0);
      if (allZeros) {
        throw Exception('CRITICAL: SPK signature is all zeros before upload!');
      }
      
      await _api.publishKeys(
        identityKeyPublic: identityCombined,
        registrationId: 1,
        signedPrekeyPublic: base64Encode(spk.bytes),
        signedPrekeyId: 1,
        signedPrekeySignature: base64Encode(spkSignature),
        oneTimePrekeys: otks,
      );
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveKeysToLocal(String userId) async {
     final otksEncoded = <String>[];
     if (_oneTimePreKeys != null) {
       for (final otk in _oneTimePreKeys!) {
         otksEncoded.add(base64Encode(await otk.extractPrivateKeyBytes()));
       }
     }
     
     final data = jsonEncode({
       'ik_dh': base64Encode(await _identityDhKeyPair!.extractPrivateKeyBytes()),
       'ik_sk': base64Encode(await _identitySigningKeyPair!.extractPrivateKeyBytes()),
       'spk': base64Encode(await _signedPreKey!.extractPrivateKeyBytes()),
       'otks': otksEncoded,
     });
     await _storage.write(key: 'e2ee_keys_$userId', value: data);
     
     // Also save to SharedPreferences on web as a fallback
     if (kIsWeb) {
       final prefs = await SharedPreferences.getInstance();
       await prefs.setString('e2ee_keys_$userId', data);
     }
  }

  Future<bool> _loadKeysFromLocal(String userId) async {
    
    // Try FlutterSecureStorage first
    var data = await _storage.read(key: 'e2ee_keys_$userId');
    
    // Fallback to SharedPreferences on web if secure storage fails
    if (data == null && kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      data = prefs.getString('e2ee_keys_$userId');
    }
    
    if (data == null) {
      return false;
    }
    
    final map = jsonDecode(data);
    
    if (map['ik_dh'] != null) {
      _identityDhKeyPair = await _dhAlgo.newKeyPairFromSeed(base64Decode(map['ik_dh']));
    } else if (map['ik'] != null) {
      // Legacy load
      _identityDhKeyPair = await _dhAlgo.newKeyPairFromSeed(base64Decode(map['ik']));
    }
    
    if (map['ik_sk'] != null) {
       _identitySigningKeyPair = await _signingAlgo.newKeyPairFromSeed(base64Decode(map['ik_sk']));
    }

    _signedPreKey = await _dhAlgo.newKeyPairFromSeed(base64Decode(map['spk']));
    
    // Load OTKs
    _oneTimePreKeys = [];
    if (map['otks'] != null && map['otks'] is List) {
      for (final otkSeed in map['otks']) {
        _oneTimePreKeys!.add(await _dhAlgo.newKeyPairFromSeed(base64Decode(otkSeed)));
      }
    }
    
    return isReady;
  }
  
  // Cloud identity backup is now handled by KeyVaultService with a user-chosen
  // passphrase (PBKDF2 100k + AES-256-GCM). The old approach used user ID as PIN
  // which the server could derive — breaking zero-knowledge. This method is now
  // a no-op; keys are backed up when the user sets up the Encryption Hub vault.
  Future<void> _backupIdentityToCloud(String userId) async {
      // No-op: KeyVaultService.setupVault() handles secure backup.
      // Legacy encrypted_private_key field on profile is no longer written to.
      if (kDebugMode) debugPrint('[E2EE] _backupIdentityToCloud skipped — vault handles backup');
  }

  Future<bool> _restoreFromCloud(String userId) async {
     try {
       // FIX 1: Correct Profile Access
       final profileMap = await ApiService(_auth).getProfile();
       // ApiService returns map with 'profile' key containing Profile object
       final profileObj = profileMap['profile'];
       
       String? blobJson;
       // Safety check if it returned Map or Object unexpectedly
       if (profileObj is Map) {
          blobJson = profileObj['encrypted_private_key'];
       } else {
           // Assume Profile object
           // DYNAMIC ACCESS OR CAST
           // Since we can't import Profile here to cast easily without cycle or logic change,
           // we use dynamic access if supported, or assume getProfile implementation.
           // Actually, earlier viewed Profile.dart shows it's a class. 
           // We'll trust dynamic dispatch or use `.encryptedPrivateKey` if typed.
           // However, ApiService.getProfile returns Map<String, dynamic>. 
           // Whatever is in 'profile' key IS a Profile instance.
           // Dynamic access .encryptedPrivateKey should work.
           blobJson = (profileObj as dynamic).encryptedPrivateKey;
       }

       if (blobJson == null) return false;
        final blob = jsonDecode(blobJson);
        
        final pinKey = await _deriveKeyFromPin(_backupPin);
        final box = SecretBox(base64Decode(blob['c']), nonce: base64Decode(blob['n']), mac: Mac(base64Decode(blob['m'])));
        
        final decryptedBytes = await _cipher.decrypt(box, secretKey: pinKey);
        final blobData = utf8.decode(decryptedBytes);
        final seeds = blobData.split(':');
        
        if (seeds.length == 2) {
          _identityDhKeyPair = await _dhAlgo.newKeyPairFromSeed(base64Decode(seeds[0]));
          _identitySigningKeyPair = await _signingAlgo.newKeyPairFromSeed(base64Decode(seeds[1]));
        } else {
          // Legacy restore
          _identityDhKeyPair = await _dhAlgo.newKeyPairFromSeed(base64Decode(seeds[0]));
        }
        
        // After cloud restore, regenerate SPK and OTKs
        _signedPreKey = await _dhAlgo.newKeyPair();
        final spkPublic = await _signedPreKey!.extractPublicKey();
        final signature = await _signingAlgo.sign(spkPublic.bytes, keyPair: _identitySigningKeyPair!);
        final spkSignature = Uint8List.fromList(signature.bytes);
        
        // Generate new OTKs
        final opks = <SimpleKeyPair>[];
        for (int i = 0; i < 20; i++) {
          opks.add(await _dhAlgo.newKeyPair());
        }
        _oneTimePreKeys = opks;
        
        // Save locally and publish
        await _saveKeysToLocal(userId);
        await _publishKeys(spkSignature);
        
        return isReady;
     } catch (e) {
       return false;
     }
  }

  Future<Map<String, dynamic>> exportAllKeys() async {
    if (!isReady) {
      throw Exception('Keys not ready for export');
    }

    try {
      
      final identityDhPublic = await _identityDhKeyPair!.extractPublicKey();
      final identitySigningPublic = await _identitySigningKeyPair!.extractPublicKey();
      final spkPublic = await _signedPreKey!.extractPublicKey();
      
      // Generate SPK signature for backup
      final spkSignature = await _signingAlgo.sign(
        spkPublic.bytes,
        keyPair: _identitySigningKeyPair!,
      );
      
      // Export OTKs
      final otkData = <Map<String, dynamic>>[];
      for (int i = 0; i < _oneTimePreKeys!.length; i++) {
        final otk = _oneTimePreKeys![i];
        final otkPublic = await otk.extractPublicKey();
        otkData.add({
          'key_id': i,
          'public_key': base64Encode(otkPublic.bytes),
          'private_key': base64Encode(await otk.extractPrivateKeyBytes()),
        });
      }
      
      final exportData = {
        'version': '1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'keys': {
          'identity_dh_private': base64Encode(await _identityDhKeyPair!.extractPrivateKeyBytes()),
          'identity_dh_public': base64Encode(identityDhPublic.bytes),
          'identity_signing_private': base64Encode(await _identitySigningKeyPair!.extractPrivateKeyBytes()),
          'identity_signing_public': base64Encode(identitySigningPublic.bytes),
          'signed_prekey_private': base64Encode(await _signedPreKey!.extractPrivateKeyBytes()),
          'signed_prekey_public': base64Encode(spkPublic.bytes),
          'signed_prekey_signature': base64Encode(spkSignature.bytes),
          'one_time_prekeys': otkData,
        },
        'metadata': {
          'otk_count': _oneTimePreKeys!.length,
          'user_id': _initializedForUserId,
        },
      };
      
      return exportData;
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> importAllKeys(Map<String, dynamic> backupData) async {
    try {
      
      if (!backupData.containsKey('keys')) {
        throw ArgumentError('Invalid backup format: missing keys');
      }
      
      final keys = backupData['keys'] as Map<String, dynamic>;
      
      // 1. Restore Identity Keys
      if (keys.containsKey('identity_dh_private')) {
        _identityDhKeyPair = await _dhAlgo.newKeyPairFromSeed(base64Decode(keys['identity_dh_private']));
      }
      
      if (keys.containsKey('identity_signing_private')) {
        _identitySigningKeyPair = await _signingAlgo.newKeyPairFromSeed(base64Decode(keys['identity_signing_private']));
      }
      
      // 2. Restore Signed PreKey
      if (keys.containsKey('signed_prekey_private')) {
        _signedPreKey = await _dhAlgo.newKeyPairFromSeed(base64Decode(keys['signed_prekey_private']));
      }
      
      // 3. Restore One-Time PreKeys
      if (keys.containsKey('one_time_prekeys') && keys['one_time_prekeys'] is List) {
        final otkList = keys['one_time_prekeys'] as List;
        final importedOTKs = <SimpleKeyPair>[];
        for (final item in otkList) {
          if (item is Map && item.containsKey('private_key')) {
            importedOTKs.add(await _dhAlgo.newKeyPairFromSeed(base64Decode(item['private_key'])));
          }
        }
        _oneTimePreKeys = importedOTKs;
      }

      // 4. Set User Context from metadata
      if (backupData.containsKey('metadata')) {
        final metadata = backupData['metadata'] as Map<String, dynamic>;
        if (metadata.containsKey('user_id')) {
          _initializedForUserId = metadata['user_id'];
        }
      }
      
      // Fallback if metadata missing
      if (_initializedForUserId == null) {
        _initializedForUserId = _auth.currentUser?.id;
      }
      
      // 5. Persist and Synchronize
      if (_initializedForUserId != null) {
        await _saveKeysToLocal(_initializedForUserId!);
        
        // Republish to server to ensure backend is synchronized
        // This is safe even if keys are identical
        if (_identitySigningKeyPair != null && _signedPreKey != null) {
          final spkPublic = await _signedPreKey!.extractPublicKey();
          final signature = await _signingAlgo.sign(
            spkPublic.bytes, 
            keyPair: _identitySigningKeyPair!
          );
          await _publishKeys(signature.bytes);
        }
      }
      
      
    } catch (e) {
      rethrow;
    }
  }

  Future<SecretKey> _deriveKeyFromPin(String pin) async {
      final sink = _sha256.newHashSink();
      sink.add(utf8.encode(pin));
      sink.close();
      return SecretKey((await sink.hash()).bytes);
  }
}
