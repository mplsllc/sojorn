import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'simple_e2ee_service.dart';
import 'capsule_security_service.dart';
import 'api_service.dart';

/// KeyVaultService — Unified encryption key manager.
///
/// Wraps BOTH chat E2EE keys and capsule keys into a single
/// passphrase-encrypted vault. The server stores only an opaque
/// AES-256-GCM ciphertext blob — it CANNOT derive the key.
///
/// Recovery flow:
///   1. User sets a recovery passphrase at first launch
///   2. All private keys are encrypted with passphrase-derived key (PBKDF2 100k + SHA-256)
///   3. Encrypted vault is stored server-side via capsule_key_backups (zero-knowledge)
///   4. On new device: user enters passphrase → vault decrypted → keys restored
class KeyVaultService {
  static final KeyVaultService instance = KeyVaultService._();
  KeyVaultService._();

  static const _passphraseHashKey = 'vault_passphrase_hash';
  static const _vaultSetupCompleteKey = 'vault_setup_complete';
  static const _vaultSaltKey = 'vault_salt';
  static const _cachedPassphraseKey = 'vault_cached_passphrase';
  bool _syncInProgress = false;

  final _storage = const FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'sojorn_key_vault',
      publicKey: 'sojorn_vault_public',
    ),
  );
  final _cipher = AesGcm.with256bits();
  final _sha256 = Sha256();

  // ── Status ──────────────────────────────────────────────────────────

  /// Whether the user has completed vault setup (set a recovery passphrase)
  Future<bool> isVaultSetup() async {
    // Check local flag first
    final local = await _storage.read(key: _vaultSetupCompleteKey);
    if (local == 'true') return true;

    // Fallback: check server for existing backup
    try {
      final data = await ApiService.instance.callGoApi(
        '/capsule/escrow/status',
        method: 'GET',
      );
      return data['has_backup'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Check health of all key systems
  Future<VaultStatus> getVaultStatus() async {
    final e2ee = SimpleE2EEService();
    final hasPassphrase = await _storage.read(key: _passphraseHashKey) != null;
    final isSetup = await isVaultSetup();

    // Check chat keys
    final chatKeysReady = e2ee.isReady;

    // Check capsule keys
    bool capsuleKeysExist = false;
    try {
      final pubKey = await _storage.read(key: 'capsule_public_key');
      capsuleKeysExist = pubKey != null;
    } catch (_) {}

    // Check server backup exists
    bool serverBackupExists = false;
    try {
      final data = await ApiService.instance.callGoApi(
        '/capsule/escrow/status',
        method: 'GET',
      );
      serverBackupExists = data['has_backup'] == true;
    } catch (_) {}

    return VaultStatus(
      isSetup: isSetup,
      hasPassphrase: hasPassphrase,
      chatKeysReady: chatKeysReady,
      capsuleKeysExist: capsuleKeysExist,
      serverBackupExists: serverBackupExists,
    );
  }

  // ── Setup & Passphrase ──────────────────────────────────────────────

  /// Initial vault setup: user chooses a recovery passphrase.
  /// Encrypts all current keys and uploads to server.
  /// If [recoveryKey] is provided, also uploads a second backup encrypted with it.
  Future<void> setupVault(String passphrase, {String? recoveryKey}) async {
    if (passphrase.length < 8) {
      throw ArgumentError('Passphrase must be at least 8 characters');
    }

    // 1. Generate and store salt
    final salt = _generateRandom(32);
    await _storage.write(key: _vaultSaltKey, value: base64Encode(salt));

    // 2. Store passphrase hash locally (for quick verification, NOT for encryption)
    final passphraseHash = await _hashPassphrase(passphrase);
    await _storage.write(key: _passphraseHashKey, value: passphraseHash);

    // 3. Cache passphrase for auto-sync (secure storage is hardware-backed)
    await _storage.write(key: _cachedPassphraseKey, value: passphrase);

    // 4. Encrypt all keys and upload (passphrase backup)
    await _encryptAndUploadVault(passphrase, salt);

    // 5. Also upload a recovery-key-encrypted backup if provided
    if (recoveryKey != null && recoveryKey.isNotEmpty) {
      final recoverySalt = _generateRandom(32);
      await _encryptAndUploadVault(recoveryKey, recoverySalt, backupType: 'recovery_key');
    }

    // 6. Mark setup complete
    await _storage.write(key: _vaultSetupCompleteKey, value: 'true');
  }

  /// Re-encrypt and upload vault (e.g. after key changes)
  Future<void> syncVault(String passphrase) async {
    final saltB64 = await _storage.read(key: _vaultSaltKey);
    if (saltB64 == null) throw Exception('Vault not setup — no salt found');
    final salt = base64Decode(saltB64);
    await _encryptAndUploadVault(passphrase, salt);
    // Cache passphrase on successful manual sync too
    await _storage.write(key: _cachedPassphraseKey, value: passphrase);
  }

  /// Auto-sync vault using cached passphrase.
  /// Call this after any key generation/change event.
  /// Safe to call frequently — silently no-ops if vault isn't set up
  /// or passphrase isn't cached.
  Future<void> autoSync() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final isSetup = await _storage.read(key: _vaultSetupCompleteKey);
      if (isSetup != 'true') return;

      final passphrase = await _storage.read(key: _cachedPassphraseKey);
      if (passphrase == null || passphrase.isEmpty) {
        if (kDebugMode) debugPrint('[Vault] Auto-sync skipped — no cached passphrase');
        return;
      }

      final saltB64 = await _storage.read(key: _vaultSaltKey);
      if (saltB64 == null) return;

      await _encryptAndUploadVault(passphrase, base64Decode(saltB64));
      if (kDebugMode) debugPrint('[Vault] Auto-sync completed successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[Vault] Auto-sync failed: $e');
    } finally {
      _syncInProgress = false;
    }
  }

  /// Verify a passphrase matches the stored hash
  Future<bool> verifyPassphrase(String passphrase) async {
    final storedHash = await _storage.read(key: _passphraseHashKey);
    if (storedHash == null) return false;
    final hash = await _hashPassphrase(passphrase);
    return hash == storedHash;
  }

  // ── Restore ─────────────────────────────────────────────────────────

  /// Restore all keys from server backup using the recovery key.
  /// Fetches the recovery_key backup type from the server.
  Future<RestoreResult> restoreFromRecoveryKey(String recoveryKey) async {
    // Strip dashes and normalize
    final key = recoveryKey.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return _restoreFromServer(key, backupType: 'recovery_key');
  }

  /// Restore all keys from server backup using passphrase
  Future<RestoreResult> restoreFromPassphrase(String passphrase) async {
    return _restoreFromServer(passphrase);
  }

  /// Internal: restore from server backup with given passphrase and backup type
  Future<RestoreResult> _restoreFromServer(String passphrase, {String backupType = 'passphrase'}) async {
    // 1. Download encrypted vault from server
    Map<String, dynamic> backupData;
    try {
      backupData = await ApiService.instance.callGoApi(
        '/capsule/escrow/backup?type=$backupType',
        method: 'GET',
      );
    } catch (e) {
      throw Exception('No backup found on server');
    }

    final backup = backupData['backup'] as Map<String, dynamic>?;
    if (backup == null) throw Exception('No backup data');

    final salt = base64Decode(backup['salt'] as String);
    final iv = base64Decode(backup['iv'] as String);
    final payload = base64Decode(backup['payload'] as String);

    // 2. Derive key from passphrase
    final derivedKey = await _deriveKey(passphrase, salt);

    // 3. Decrypt vault
    Map<String, dynamic> vault;
    try {
      // The payload is: ciphertext + MAC (last 16 bytes for GCM)
      // But we stored it as a JSON blob with 'c', 'n', 'm' — let's handle both formats
      String vaultJson;
      try {
        // New format: raw AES-GCM (ciphertext is payload, iv was stored separately)
        // payload = ciphertext bytes, we need to split mac
        if (payload.length > 16) {
          final ciphertext = payload.sublist(0, payload.length - 16);
          final mac = Mac(payload.sublist(payload.length - 16));
          final box = SecretBox(ciphertext, nonce: iv, mac: mac);
          final plainBytes = await _cipher.decrypt(box, secretKey: SecretKey(derivedKey));
          vaultJson = utf8.decode(plainBytes);
        } else {
          throw Exception('Payload too short');
        }
      } catch (_) {
        // Fallback: try decoding payload as JSON envelope {c, n, m}
        final envelope = jsonDecode(utf8.decode(payload));
        final c = base64Decode(envelope['c']);
        final n = base64Decode(envelope['n']);
        final m = Mac(base64Decode(envelope['m']));
        final box = SecretBox(c, nonce: n, mac: m);
        final plainBytes = await _cipher.decrypt(box, secretKey: SecretKey(derivedKey));
        vaultJson = utf8.decode(plainBytes);
      }
      vault = jsonDecode(vaultJson);
    } catch (e) {
      throw Exception('Wrong passphrase or corrupted backup');
    }

    // 4. Restore chat E2EE keys
    bool chatRestored = false;
    if (vault.containsKey('chat_keys')) {
      try {
        final e2ee = SimpleE2EEService();
        await e2ee.importAllKeys({'keys': vault['chat_keys'], 'metadata': vault['metadata']});
        chatRestored = true;
      } catch (e) {
        if (kDebugMode) debugPrint('[Vault] Chat key restore failed: $e');
      }
    }

    // 5. Restore capsule keys
    bool capsuleRestored = false;
    if (vault.containsKey('capsule_private_key') && vault.containsKey('capsule_public_key')) {
      try {
        await _storage.write(key: 'capsule_private_key', value: vault['capsule_private_key']);
        await _storage.write(key: 'capsule_public_key', value: vault['capsule_public_key']);
        capsuleRestored = true;
      } catch (e) {
        if (kDebugMode) debugPrint('[Vault] Capsule key restore failed: $e');
      }
    }

    // 6. Store passphrase hash + salt + cached passphrase locally
    final passphraseHash = await _hashPassphrase(passphrase);
    await _storage.write(key: _passphraseHashKey, value: passphraseHash);
    await _storage.write(key: _vaultSaltKey, value: base64Encode(salt));
    await _storage.write(key: _cachedPassphraseKey, value: passphrase);
    await _storage.write(key: _vaultSetupCompleteKey, value: 'true');

    return RestoreResult(
      chatKeysRestored: chatRestored,
      capsuleKeysRestored: capsuleRestored,
    );
  }

  // ── Internal ────────────────────────────────────────────────────────

  Future<void> _encryptAndUploadVault(String passphrase, Uint8List salt, {String backupType = 'passphrase'}) async {
    // 1. Collect all private keys
    final vault = <String, dynamic>{};

    // Chat E2EE keys
    final e2ee = SimpleE2EEService();
    if (e2ee.isReady) {
      try {
        final exported = await e2ee.exportAllKeys();
        vault['chat_keys'] = exported['keys'];
        vault['metadata'] = exported['metadata'];
      } catch (e) {
        if (kDebugMode) debugPrint('[Vault] Failed to export chat keys: $e');
      }
    }

    // Capsule keys
    final capsulePriv = await _storage.read(key: 'capsule_private_key');
    final capsulePub = await _storage.read(key: 'capsule_public_key');
    if (capsulePriv != null) {
      vault['capsule_private_key'] = capsulePriv;
      vault['capsule_public_key'] = capsulePub;
    }

    vault['vault_version'] = 1;
    vault['created_at'] = DateTime.now().toIso8601String();

    if (vault.isEmpty) {
      throw Exception('No keys to back up');
    }

    // 2. Derive encryption key from passphrase (PBKDF2 100k iterations)
    final derivedKey = await _deriveKey(passphrase, salt);

    // 3. Encrypt with AES-256-GCM
    final nonce = _generateRandom(12);
    final plaintext = utf8.encode(jsonEncode(vault));
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(derivedKey),
      nonce: nonce,
    );

    // 4. Combine ciphertext + MAC into single payload
    final payload = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);

    // 5. Get user's public key for the escrow record
    String pubKeyB64 = '';
    try {
      pubKeyB64 = await CapsuleSecurityService.getUserPublicKeyB64();
    } catch (_) {
      pubKeyB64 = 'vault_backup';
    }

    // 6. Upload to server (zero-knowledge — server sees only opaque blobs)
    await ApiService.instance.callGoApi(
      '/capsule/escrow/backup',
      method: 'POST',
      body: {
        'salt': base64Encode(salt),
        'iv': base64Encode(nonce),
        'payload': base64Encode(payload),
        'pub': pubKeyB64,
        'backup_type': backupType,
      },
    );
  }

  Future<Uint8List> _deriveKey(String passphrase, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = SecretKey(utf8.encode(passphrase));
    final derived = await pbkdf2.deriveKey(secretKey: secretKey, nonce: salt);
    return Uint8List.fromList(await derived.extractBytes());
  }

  Future<String> _hashPassphrase(String passphrase) async {
    // Hash for local verification only (not used as encryption key)
    final sink = _sha256.newHashSink();
    sink.add(utf8.encode('sojorn_vault_verify:$passphrase'));
    sink.close();
    return base64Encode((await sink.hash()).bytes);
  }

  Uint8List _generateRandom(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  // ── Recovery Key ────────────────────────────────────────────────────

  /// Generate a human-readable recovery key (32 chars, grouped).
  /// Shown once at vault setup — cannot be retrieved later.
  String generateRecoveryKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No 0/O/1/I confusion
    final random = Random.secure();
    final key = List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
    // Format as XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
    final groups = <String>[];
    for (var i = 0; i < key.length; i += 4) {
      groups.add(key.substring(i, i + 4));
    }
    return groups.join('-');
  }

}

/// Status of the key vault
class VaultStatus {
  final bool isSetup;
  final bool hasPassphrase;
  final bool chatKeysReady;
  final bool capsuleKeysExist;
  final bool serverBackupExists;

  const VaultStatus({
    required this.isSetup,
    required this.hasPassphrase,
    required this.chatKeysReady,
    required this.capsuleKeysExist,
    required this.serverBackupExists,
  });

  bool get isHealthy => isSetup && chatKeysReady && serverBackupExists;
}

/// Result of a vault restore operation
class RestoreResult {
  final bool chatKeysRestored;
  final bool capsuleKeysRestored;

  const RestoreResult({
    required this.chatKeysRestored,
    required this.capsuleKeysRestored,
  });
}
