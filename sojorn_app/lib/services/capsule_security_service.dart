import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'capsule_crypto.dart';
import 'key_vault_service.dart';

/// CapsuleSecurityService — High-level orchestrator for Private Capsule E2EE.
///
/// Delegates all cryptographic primitives to [CapsuleCrypto].
/// This layer manages:
/// - User key pair lifecycle (generate, store, retrieve from secure storage)
/// - Key boxing/unboxing for invite flows
/// - Content encryption/decryption using cached capsule keys
/// - Key rotation coordination
/// - Local key cache in FlutterSecureStorage
class CapsuleSecurityService {
  static const _storage = FlutterSecureStorage();

  // ── Key Generation ──────────────────────────────────────────────────

  /// Generate a new random AES-256 Capsule Key (for creating a new capsule)
  static Future<SecretKey> generateCapsuleKey() =>
      CapsuleCrypto.generateSymmetricKey();

  /// Generate or retrieve the user's X25519 key pair from secure storage
  static Future<SimpleKeyPair> getOrCreateUserKeyPair() async {
    final existing = await _storage.read(key: 'capsule_private_key');
    if (existing != null) {
      final publicKeyB64 = await _storage.read(key: 'capsule_public_key');
      return CapsuleCrypto.importKeyPair(
        base64Decode(existing),
        base64Decode(publicKeyB64!),
      );
    }

    final keyPair = await CapsuleCrypto.generateKeyPair();
    final exported = await CapsuleCrypto.exportKeyPair(keyPair);

    await _storage.write(
      key: 'capsule_private_key',
      value: exported.privateKeyB64,
    );
    await _storage.write(
      key: 'capsule_public_key',
      value: exported.publicKeyB64,
    );

    // Auto-sync vault so new capsule keys are backed up immediately
    KeyVaultService.instance.autoSync();

    return keyPair;
  }

  /// Get the user's public key as base64 (to share with others)
  static Future<String> getUserPublicKeyB64() async {
    final keyPair = await getOrCreateUserKeyPair();
    final exported = await CapsuleCrypto.exportKeyPair(keyPair);
    return exported.publicKeyB64;
  }

  // ── Key Distribution (Invite Flow) ──────────────────────────────────

  /// Box (seal) a Capsule Key for a specific recipient.
  /// Returns serialized [BoxedKey] JSON for storage in `capsule_keys.encrypted_key_blob`.
  static Future<String> encryptCapsuleKeyForUser({
    required SecretKey capsuleKey,
    required String recipientPublicKeyB64,
  }) async {
    final senderKeyPair = await getOrCreateUserKeyPair();
    final recipientPub = SimplePublicKey(
      base64Decode(recipientPublicKeyB64),
      type: KeyPairType.x25519,
    );

    final boxed = await CapsuleCrypto.boxKey(
      capsuleKey,
      senderKeyPair,
      recipientPub,
    );
    return boxed.serialize();
  }

  /// Unbox (unseal) an encrypted group key to recover the Capsule Key
  static Future<SecretKey> decryptCapsuleKey({
    required String encryptedGroupKeyJson,
  }) async {
    final boxed = BoxedKey.deserialize(encryptedGroupKeyJson);
    final myKeyPair = await getOrCreateUserKeyPair();
    return CapsuleCrypto.unboxKey(boxed, myKeyPair);
  }

  // ── Content Encryption/Decryption ───────────────────────────────────

  /// Encrypt a JSON payload for a capsule entry
  static Future<EncryptedEntry> encryptPayload({
    required Map<String, dynamic> payload,
    required SecretKey capsuleKey,
  }) async {
    final sealed = await CapsuleCrypto.encryptPayload(
      jsonEncode(payload),
      capsuleKey,
    );
    return EncryptedEntry(iv: sealed.iv, encryptedPayload: sealed.payload);
  }

  /// Decrypt a capsule entry back to its JSON payload
  static Future<Map<String, dynamic>> decryptPayload({
    required String iv,
    required String encryptedPayload,
    required SecretKey capsuleKey,
  }) async {
    final json = await CapsuleCrypto.decryptPayload(
      encryptedPayload,
      iv,
      capsuleKey,
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  // ── Key Rotation ────────────────────────────────────────────────────

  /// Generate a new Capsule Key and box it for each member.
  static Future<KeyRotationResult> rotateKeys({
    required List<String> memberPublicKeysB64,
    required List<String> memberUserIds,
  }) async {
    final newCapsuleKey = await generateCapsuleKey();

    final memberKeys = <String, String>{};
    for (var i = 0; i < memberPublicKeysB64.length; i++) {
      final encrypted = await encryptCapsuleKeyForUser(
        capsuleKey: newCapsuleKey,
        recipientPublicKeyB64: memberPublicKeysB64[i],
      );
      memberKeys[memberUserIds[i]] = encrypted;
    }

    return KeyRotationResult(
      newCapsuleKey: newCapsuleKey,
      newPublicKey: await getUserPublicKeyB64(),
      memberKeys: memberKeys,
    );
  }

  // ── Local Key Cache ─────────────────────────────────────────────────

  /// Cache a decrypted capsule key locally for faster access
  static Future<void> cacheCapsuleKey(String groupId, SecretKey key) async {
    final bytes = await CapsuleCrypto.exportSymmetricKey(key);
    await _storage.write(
      key: 'capsule_key_$groupId',
      value: base64Encode(bytes),
    );
  }

  /// Retrieve a cached capsule key
  static Future<SecretKey?> getCachedCapsuleKey(String groupId) async {
    final stored = await _storage.read(key: 'capsule_key_$groupId');
    if (stored == null) return null;
    return CapsuleCrypto.importSymmetricKey(
      Uint8List.fromList(base64Decode(stored)),
    );
  }

  /// Clear cached key (on key rotation or leave)
  static Future<void> clearCachedCapsuleKey(String groupId) async {
    await _storage.delete(key: 'capsule_key_$groupId');
  }
}

// ── Data Classes (re-exported for backward compat) ────────────────────────

/// Encrypted capsule entry (iv + payload) for posting to the server.
class EncryptedEntry {
  final String iv;
  final String encryptedPayload;
  EncryptedEntry({required this.iv, required this.encryptedPayload});
}

/// Result of a key rotation operation.
class KeyRotationResult {
  final SecretKey newCapsuleKey;
  final String newPublicKey;
  final Map<String, String> memberKeys;

  KeyRotationResult({
    required this.newCapsuleKey,
    required this.newPublicKey,
    required this.memberKeys,
  });
}
