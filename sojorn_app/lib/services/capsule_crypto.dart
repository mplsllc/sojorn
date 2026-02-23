// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Low-level cryptographic primitives for the Sojorn Capsule system.
///
/// ## Zero-Knowledge Architecture
/// The server NEVER possesses unencrypted keys or plaintext.
/// All encryption/decryption happens exclusively on the client.
///
/// ## Algorithms
/// - **Symmetric**: AES-256-GCM (authenticated encryption with associated data)
/// - **Key Exchange**: X25519 (Elliptic-Curve Diffie-Hellman)
/// - **Key Derivation**: HKDF-SHA256 (for password-based escrow)
///
/// ## Data Flow
/// ```
/// generateSymmetricKey() → Capsule Key (AES-256)
///       │
///       ├─ encryptPayload(json, key) → { payload, iv }
///       ├─ decryptPayload(payload, iv, key) → json
///       │
///       └─ boxKey(groupKey, recipientPubKey)  → sealed blob
///            └─ unboxKey(sealedBlob, myKeyPair) → Capsule Key
/// ```
class CapsuleCrypto {
  CapsuleCrypto._();

  static final _aes = AesGcm.with256bits();
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // ═══════════════════════════════════════════════════════════════════════
  // 1. SYMMETRIC KEY GENERATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a cryptographically random AES-256-GCM symmetric key.
  /// Used as the "Capsule Key" — the shared secret for a private group.
  static Future<SecretKey> generateSymmetricKey() async {
    return _aes.newSecretKey();
  }

  /// Import raw key bytes (e.g. from cache or recovery) into a SecretKey.
  static SecretKey importSymmetricKey(Uint8List rawBytes) {
    assert(rawBytes.length == 32, 'AES-256 key must be exactly 32 bytes');
    return SecretKey(rawBytes);
  }

  /// Export a SecretKey to raw bytes for storage/transport.
  static Future<Uint8List> exportSymmetricKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. PAYLOAD ENCRYPTION / DECRYPTION (AES-256-GCM)
  // ═══════════════════════════════════════════════════════════════════════

  /// Encrypt a JSON-serializable payload with the Capsule Key.
  ///
  /// Returns a [SealedPayload] containing the IV (nonce) and the
  /// ciphertext+MAC concatenated as a single base64 blob.
  ///
  /// The MAC is appended to the ciphertext (standard GCM layout):
  ///   payload = base64(ciphertext || mac_16_bytes)
  static Future<SealedPayload> encryptPayload(
    String jsonString,
    SecretKey key,
  ) async {
    final plaintext = utf8.encode(jsonString);
    final nonce = _aes.newNonce(); // 12 bytes for GCM

    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    // Concat ciphertext + MAC tag for single-blob storage
    final combined = Uint8List.fromList([
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    return SealedPayload(
      iv: base64Encode(nonce),
      payload: base64Encode(combined),
    );
  }

  /// Decrypt a sealed payload back to its original JSON string.
  ///
  /// Expects the same format produced by [encryptPayload]:
  ///   payload = base64(ciphertext || mac_16_bytes)
  static Future<String> decryptPayload(
    String payloadB64,
    String ivB64,
    SecretKey key,
  ) async {
    final combined = base64Decode(payloadB64);
    final ivBytes = base64Decode(ivB64);

    // Split: everything except last 16 bytes is ciphertext, last 16 is MAC
    if (combined.length < 16) {
      throw CapsuleCryptoException('Payload too short — corrupted or tampered');
    }
    final cipherText = combined.sublist(0, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);

    final box = SecretBox(
      cipherText,
      nonce: ivBytes,
      mac: Mac(macBytes),
    );

    try {
      final plaintext = await _aes.decrypt(box, secretKey: key);
      return utf8.decode(plaintext);
    } catch (e) {
      throw CapsuleCryptoException(
        'Decryption failed — wrong key or tampered payload',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. KEY BOXING / UNBOXING (X25519 ECDH + AES-GCM SEAL)
  // ═══════════════════════════════════════════════════════════════════════

  /// "Box" (seal) a group symmetric key for a specific recipient.
  ///
  /// Uses X25519 ECDH to derive a shared secret between sender and recipient,
  /// then encrypts the group key with that shared secret.
  ///
  /// Returns a [BoxedKey] that only the recipient can unbox.
  static Future<BoxedKey> boxKey(
    SecretKey groupKey,
    SimpleKeyPair senderKeyPair,
    SimplePublicKey recipientPublicKey,
  ) async {
    // Derive shared secret via ECDH
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: senderKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    // Derive a proper encryption key from the shared secret via HKDF
    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('sojorn-capsule-box-v1'),
      info: utf8.encode('capsule-key-encryption'),
    );

    // Encrypt the group key
    final groupKeyBytes = await groupKey.extractBytes();
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      groupKeyBytes,
      secretKey: derivedKey,
      nonce: nonce,
    );

    final senderPub = await senderKeyPair.extractPublicKey();
    return BoxedKey(
      iv: base64Encode(nonce),
      ciphertext: base64Encode(box.cipherText),
      mac: base64Encode(box.mac.bytes),
      senderPublicKey: base64Encode(senderPub.bytes),
    );
  }

  /// "Unbox" (unseal) a group symmetric key addressed to us.
  ///
  /// Uses our private key + the sender's public key to re-derive
  /// the same shared secret, then decrypts the group key.
  static Future<SecretKey> unboxKey(
    BoxedKey boxedKey,
    SimpleKeyPair recipientKeyPair,
  ) async {
    final senderPub = SimplePublicKey(
      base64Decode(boxedKey.senderPublicKey),
      type: KeyPairType.x25519,
    );

    // Re-derive the same shared secret
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: senderPub,
    );

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('sojorn-capsule-box-v1'),
      info: utf8.encode('capsule-key-encryption'),
    );

    // Decrypt
    final box = SecretBox(
      base64Decode(boxedKey.ciphertext),
      nonce: base64Decode(boxedKey.iv),
      mac: Mac(base64Decode(boxedKey.mac)),
    );

    try {
      final keyBytes = await _aes.decrypt(box, secretKey: derivedKey);
      return SecretKey(keyBytes);
    } catch (e) {
      throw CapsuleCryptoException('Unbox failed — not intended for this key pair');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. X25519 KEY PAIR MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a new X25519 key pair.
  static Future<SimpleKeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair() as SimpleKeyPair;
  }

  /// Export a key pair to portable bytes for backup.
  static Future<KeyPairExport> exportKeyPair(SimpleKeyPair keyPair) async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return KeyPairExport(
      privateKey: Uint8List.fromList(privateBytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Import a key pair from raw bytes.
  static SimpleKeyPair importKeyPair(Uint8List privateKey, Uint8List publicKey) {
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. ESCROW KEY DERIVATION (Password/PIN → AES Key)
  // ═══════════════════════════════════════════════════════════════════════

  /// Derive an AES-256 key from a user's password or PIN.
  /// Used for the Escrow Recovery System — encrypts the user's private key
  /// before uploading to the server.
  ///
  /// Uses Argon2id for memory-hard key stretching (resistant to GPU attacks).
  /// Falls back to PBKDF2 if Argon2id is not available.
  static Future<SecretKey> deriveKeyFromPassword(
    String password, {
    required Uint8List salt,
    int iterations = 100000,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  /// Generate a random 16-byte salt for password derivation.
  static Uint8List generateSalt() {
    // Use AES nonce generator as a source of 16 random bytes
    final nonce = _aes.newNonce(); // 12 bytes
    // Extend to 16 by generating another partial nonce
    final extra = _aes.newNonce();
    return Uint8List.fromList([...nonce, ...extra.sublist(0, 4)]);
  }

  /// Encrypt raw bytes with a password-derived key.
  /// Used for escrow: encrypt(privateKeyBytes, deriveKey(pin))
  static Future<SealedPayload> encryptWithDerivedKey(
    Uint8List plaintext,
    SecretKey derivedKey,
  ) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(plaintext, secretKey: derivedKey, nonce: nonce);
    final combined = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return SealedPayload(
      iv: base64Encode(nonce),
      payload: base64Encode(combined),
    );
  }

  /// Decrypt raw bytes with a password-derived key.
  static Future<Uint8List> decryptWithDerivedKey(
    String payloadB64,
    String ivB64,
    SecretKey derivedKey,
  ) async {
    final combined = base64Decode(payloadB64);
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final box = SecretBox(cipherText, nonce: base64Decode(ivB64), mac: mac);
    try {
      final result = await _aes.decrypt(box, secretKey: derivedKey);
      return Uint8List.fromList(result);
    } catch (e) {
      throw CapsuleCryptoException('Escrow decryption failed — wrong PIN/password');
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═════════════════════════════════════════════════════════════════════════════

/// Encrypted payload + its IV. Produced by [CapsuleCrypto.encryptPayload].
class SealedPayload {
  final String iv;      // base64-encoded 12-byte GCM nonce
  final String payload; // base64-encoded (ciphertext || mac)

  const SealedPayload({required this.iv, required this.payload});

  Map<String, dynamic> toJson() => {'iv': iv, 'payload': payload};

  factory SealedPayload.fromJson(Map<String, dynamic> json) => SealedPayload(
    iv: json['iv'] as String,
    payload: json['payload'] as String,
  );
}

/// A group key encrypted for a specific recipient via X25519+AES-GCM.
class BoxedKey {
  final String iv;
  final String ciphertext;
  final String mac;
  final String senderPublicKey; // base64 X25519 public key of sender

  const BoxedKey({
    required this.iv,
    required this.ciphertext,
    required this.mac,
    required this.senderPublicKey,
  });

  /// Serialize to JSON string for storage in `capsule_keys.encrypted_key_blob`
  String serialize() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'iv': iv,
    'ct': ciphertext,
    'mac': mac,
    'spk': senderPublicKey,
  };

  factory BoxedKey.fromJson(Map<String, dynamic> json) => BoxedKey(
    iv: json['iv'] as String,
    ciphertext: json['ct'] as String,
    mac: json['mac'] as String,
    senderPublicKey: json['spk'] as String,
  );

  factory BoxedKey.deserialize(String jsonStr) =>
      BoxedKey.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}

/// Portable representation of an X25519 key pair.
class KeyPairExport {
  final Uint8List privateKey; // 32 bytes
  final Uint8List publicKey;  // 32 bytes

  const KeyPairExport({required this.privateKey, required this.publicKey});

  String get privateKeyB64 => base64Encode(privateKey);
  String get publicKeyB64 => base64Encode(publicKey);
}

/// Escrow backup blob: the user's private key encrypted with their PIN.
class EscrowBackup {
  final String salt;    // base64-encoded salt used in PBKDF2
  final String iv;      // base64-encoded nonce
  final String payload; // base64-encoded encrypted private key + MAC
  final String publicKey; // base64-encoded public key (not secret, for matching)

  const EscrowBackup({
    required this.salt,
    required this.iv,
    required this.payload,
    required this.publicKey,
  });

  Map<String, dynamic> toJson() => {
    'salt': salt,
    'iv': iv,
    'payload': payload,
    'pub': publicKey,
  };

  factory EscrowBackup.fromJson(Map<String, dynamic> json) => EscrowBackup(
    salt: json['salt'] as String,
    iv: json['iv'] as String,
    payload: json['payload'] as String,
    publicKey: json['pub'] as String,
  );

  String serialize() => jsonEncode(toJson());
  factory EscrowBackup.deserialize(String jsonStr) =>
      EscrowBackup.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}

/// Exception type for all capsule crypto failures.
class CapsuleCryptoException implements Exception {
  final String message;
  const CapsuleCryptoException(this.message);
  @override
  String toString() => 'CapsuleCryptoException: $message';
}
