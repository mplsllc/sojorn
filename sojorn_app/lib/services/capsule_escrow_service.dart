import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'capsule_crypto.dart';

/// Escrow Recovery Service — Encrypts the user's private key with their
/// PIN/password and stores the encrypted blob on the server.
///
/// ## Security Model
/// 1. User's X25519 private key lives in FlutterSecureStorage (local only)
/// 2. On backup: deriveKey(PIN) → encrypt(privateKey) → upload encrypted blob
/// 3. On restore: download blob → deriveKey(PIN) → decrypt → import key pair
/// 4. Server stores ONLY the encrypted blob — it cannot derive the PIN or key
///
/// ## Recovery Flow
/// ```
/// User loses device →
///   Login on new device →
///     Enter PIN →
///       Download encrypted backup →
///         PBKDF2(PIN, salt) → AES key →
///           Decrypt → privateKey restored →
///             All capsule keys can be unboxed again
/// ```
class CapsuleEscrowService {
  static const _storage = FlutterSecureStorage();

  final String apiBaseUrl;
  final Future<String?> Function() getAuthToken;

  CapsuleEscrowService({
    required this.apiBaseUrl,
    required this.getAuthToken,
  });

  // ═══════════════════════════════════════════════════════════════════════
  // BACKUP: Encrypt private key with PIN and upload
  // ═══════════════════════════════════════════════════════════════════════

  /// Create an encrypted backup of the user's private key.
  ///
  /// [pin] — User's chosen PIN or password (minimum 6 characters).
  ///
  /// Steps:
  /// 1. Read the private key from secure storage
  /// 2. Generate a random salt
  /// 3. Derive an AES-256 key from PIN + salt via PBKDF2
  /// 4. Encrypt the private key bytes
  /// 5. Upload the encrypted blob + salt + public key to the server
  Future<EscrowBackupResult> createBackup(String pin) async {
    if (pin.length < 6) {
      throw CapsuleCryptoException('PIN must be at least 6 characters');
    }

    // 1. Read existing private key
    final privateKeyB64 = await _storage.read(key: 'capsule_private_key');
    final publicKeyB64 = await _storage.read(key: 'capsule_public_key');
    if (privateKeyB64 == null || publicKeyB64 == null) {
      throw CapsuleCryptoException('No key pair found — generate one first');
    }

    final privateKeyBytes = base64Decode(privateKeyB64);

    // 2. Generate salt
    final salt = CapsuleCrypto.generateSalt();

    // 3. Derive encryption key from PIN
    final derivedKey = await CapsuleCrypto.deriveKeyFromPassword(
      pin,
      salt: salt,
    );

    // 4. Encrypt the private key
    final sealed = await CapsuleCrypto.encryptWithDerivedKey(
      Uint8List.fromList(privateKeyBytes),
      derivedKey,
    );

    // 5. Build the escrow backup
    final backup = EscrowBackup(
      salt: base64Encode(salt),
      iv: sealed.iv,
      payload: sealed.payload,
      publicKey: publicKeyB64,
    );

    // 6. Upload to server
    await _uploadBackup(backup);

    return EscrowBackupResult(
      backup: backup,
      uploaded: true,
    );
  }

  /// Upload the encrypted backup blob to the server.
  /// The server stores it in `capsule_key_backups` scoped to the authenticated user.
  Future<void> _uploadBackup(EscrowBackup backup) async {
    final token = await getAuthToken();
    if (token == null) throw CapsuleCryptoException('Not authenticated');

    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/v1/capsule/escrow/backup'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: backup.serialize(),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw CapsuleCryptoException(
        'Failed to upload backup: ${response.statusCode}',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RESTORE: Download backup and decrypt with PIN
  // ═══════════════════════════════════════════════════════════════════════

  /// Restore the user's private key from the server-stored encrypted backup.
  ///
  /// [pin] — The same PIN/password used during backup creation.
  ///
  /// Steps:
  /// 1. Download the encrypted backup blob from the server
  /// 2. Derive the same AES key from PIN + stored salt
  /// 3. Decrypt the private key bytes
  /// 4. Store the recovered key pair in secure storage
  Future<void> restoreFromBackup(String pin) async {
    if (pin.length < 6) {
      throw CapsuleCryptoException('PIN must be at least 6 characters');
    }

    // 1. Download backup
    final backup = await _downloadBackup();

    // 2. Derive key from PIN + salt
    final salt = base64Decode(backup.salt);
    final derivedKey = await CapsuleCrypto.deriveKeyFromPassword(
      pin,
      salt: Uint8List.fromList(salt),
    );

    // 3. Decrypt the private key
    final privateKeyBytes = await CapsuleCrypto.decryptWithDerivedKey(
      backup.payload,
      backup.iv,
      derivedKey,
    );

    // 4. Validate: the private key should be 32 bytes (X25519)
    if (privateKeyBytes.length != 32) {
      throw CapsuleCryptoException(
        'Recovered key has wrong length (${privateKeyBytes.length}) — wrong PIN?',
      );
    }

    // 5. Store recovered key pair in secure storage
    await _storage.write(
      key: 'capsule_private_key',
      value: base64Encode(privateKeyBytes),
    );
    await _storage.write(
      key: 'capsule_public_key',
      value: backup.publicKey,
    );
  }

  /// Download the encrypted backup from the server.
  Future<EscrowBackup> _downloadBackup() async {
    final token = await getAuthToken();
    if (token == null) throw CapsuleCryptoException('Not authenticated');

    final response = await http.get(
      Uri.parse('$apiBaseUrl/api/v1/capsule/escrow/backup'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 404) {
      throw CapsuleCryptoException('No backup found for this account');
    }
    if (response.statusCode != 200) {
      throw CapsuleCryptoException(
        'Failed to download backup: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final backupJson = json['backup'] as Map<String, dynamic>?;
    if (backupJson == null) {
      throw CapsuleCryptoException('Invalid backup response');
    }
    return EscrowBackup.fromJson(backupJson);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if a backup exists on the server for the current user.
  Future<bool> hasBackup() async {
    final token = await getAuthToken();
    if (token == null) return false;

    final response = await http.get(
      Uri.parse('$apiBaseUrl/api/v1/capsule/escrow/status'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['has_backup'] as bool? ?? false;
    }
    return false;
  }

  /// Delete the server-stored backup (e.g. when user wants to re-create it).
  Future<void> deleteBackup() async {
    final token = await getAuthToken();
    if (token == null) throw CapsuleCryptoException('Not authenticated');

    await http.delete(
      Uri.parse('$apiBaseUrl/api/v1/capsule/escrow/backup'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Check if a local key pair exists (i.e. user has generated keys).
  static Future<bool> hasLocalKeyPair() async {
    final pk = await _storage.read(key: 'capsule_private_key');
    return pk != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═════════════════════════════════════════════════════════════════════════════

class EscrowBackupResult {
  final EscrowBackup backup;
  final bool uploaded;
  const EscrowBackupResult({required this.backup, required this.uploaded});
}
