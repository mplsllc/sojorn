// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

// Double Ratchet Session
//
// Implements the Double Ratchet Algorithm (Signal Protocol) on top of the
// existing X3DH handshake in SimpleE2EEService.
//
// After an X3DH handshake produces a shared secret, this class manages:
//   1. Symmetric-key ratchet  — every message uses a unique derived key
//      (so compromise of one message key doesn't expose siblings)
//   2. Diffie-Hellman ratchet — each party periodically introduces a new
//      ephemeral key, advancing the root chain and providing forward secrecy
//      even if a long-term chain key is later leaked
//
// Wire format (added to existing message header):
//   "v"  : 2            — version (2 = Double Ratchet)
//   "rk" : base64       — sender's current DH ratchet public key
//   "n"  : int          — message number in current sending chain
//   "pn" : int          — previous sending chain length (for skip handling)
//
// References:
//   https://signal.org/docs/specifications/doubleratchet/
//   https://signal.org/docs/specifications/x3dh/

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _maxSkipKeys = 500;         // cap on stored out-of-order message keys
const _storagePrefix = 'dr_session_v1_'; // storage key prefix

// ─── HKDF helpers ────────────────────────────────────────────────────────────

final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _x25519 = X25519();
final _aes = AesGcm.with256bits();

/// HKDF-SHA256 with a fixed-width info string.
Future<Uint8List> _hkdfDerive(Uint8List ikm, String info, {Uint8List? salt}) async {
  final key = await _hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: salt ?? Uint8List(32), // zero salt if not provided
    info: utf8.encode(info),
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// KDF_RK: advances the root chain with a new DH output.
/// Returns [newRootKey, newChainKey].
Future<(Uint8List, Uint8List)> _kdfRootChain(
    Uint8List rootKey, Uint8List dhOutput) async {
  final newRoot = await _hkdfDerive(dhOutput, 'sojorn-dr-root-v1', salt: rootKey);
  final newChain = await _hkdfDerive(dhOutput, 'sojorn-dr-chain-v1', salt: newRoot);
  return (newRoot, newChain);
}

/// KDF_CK: advances a sending/receiving chain by one step.
/// Returns [messageKey, nextChainKey].
Future<(Uint8List, Uint8List)> _kdfChain(Uint8List chainKey) async {
  final msgKey = await _hkdfDerive(chainKey, 'sojorn-dr-msg-v1');
  final nextCk = await _hkdfDerive(chainKey, 'sojorn-dr-ck-v1');
  return (msgKey, nextCk);
}

// ─── Session State ────────────────────────────────────────────────────────────

class RatchetSession {
  // ── Root chain ──────────────────────────────────────────────────────────────
  Uint8List rootKey;

  // ── Sending chain ───────────────────────────────────────────────────────────
  Uint8List sendingChainKey;
  int sendCount;            // messages sent in current sending chain
  int previousSendCount;    // # messages in previous sending chain (for headers)

  // ── Receiving chain ─────────────────────────────────────────────────────────
  Uint8List? receivingChainKey;
  int receiveCount;         // messages received in current receiving chain

  // ── DH Ratchet state ────────────────────────────────────────────────────────
  SimpleKeyPair ourRatchetKeyPair;          // our current DH ratchet key pair
  Uint8List ourRatchetPubBytes;             // cached public bytes of ourRatchetKeyPair
  Uint8List? theirRatchetPubBytes;          // their most recent DH ratchet public key

  // ── Out-of-order message key cache ──────────────────────────────────────────
  // Key format: "<their_ratchet_pub_b64>:<msg_number>"
  final Map<String, Uint8List> skippedKeys;

  RatchetSession({
    required this.rootKey,
    required this.sendingChainKey,
    this.sendCount = 0,
    this.previousSendCount = 0,
    this.receivingChainKey,
    this.receiveCount = 0,
    required this.ourRatchetKeyPair,
    required this.ourRatchetPubBytes,
    this.theirRatchetPubBytes,
    Map<String, Uint8List>? skippedKeys,
  }) : skippedKeys = skippedKeys ?? {};

  // ─── Factory: Initialize as sender (Alice) ──────────────────────────────────
  // Called after X3DH handshake when WE sent the initial message.
  // sharedSecret: X3DH output bytes
  // ourRatchetKey: ephemeral key pair we'll use for DH ratchet
  // theirRatchetPub: recipient's signed prekey bytes (used as initial ratchet key)
  static Future<RatchetSession> initAsSender({
    required Uint8List sharedSecret,
    required SimpleKeyPair ourRatchetKey,
    required Uint8List theirRatchetPub,
  }) async {
    // Derive initial root key from X3DH shared secret
    final rootKey = await _hkdfDerive(sharedSecret, 'sojorn-dr-init-v1');

    // Perform initial DH ratchet step: DH(ourRatchetKey, theirRatchetPub)
    final theirPub = SimplePublicKey(theirRatchetPub, type: KeyPairType.x25519);
    final dhOut = await _x25519.sharedSecretKey(
        keyPair: ourRatchetKey, remotePublicKey: theirPub);
    final dhBytes = Uint8List.fromList(await dhOut.extractBytes());

    final (newRoot, sendingCk) = await _kdfRootChain(rootKey, dhBytes);
    final pubBytes =
        Uint8List.fromList((await ourRatchetKey.extractPublicKey()).bytes);

    return RatchetSession(
      rootKey: newRoot,
      sendingChainKey: sendingCk,
      ourRatchetKeyPair: ourRatchetKey,
      ourRatchetPubBytes: pubBytes,
      theirRatchetPubBytes: theirRatchetPub,
    );
  }

  // ─── Factory: Initialize as receiver (Bob) ──────────────────────────────────
  // Called after X3DH handshake when THEY sent the initial message.
  // sharedSecret: X3DH output bytes (raw concatenated DH results, not yet hashed)
  // ourSignedPreKey: our SPK (used as receiver-side initial ratchet key)
  //
  // NOTE: theirRatchetPubBytes is intentionally left null. The first call to
  // decrypt() will see ratchetChanged=true and perform the DH ratchet step,
  // deriving the receiving chain from DH(ourSPK, senderRatchetPub).
  static Future<RatchetSession> initAsReceiver({
    required Uint8List sharedSecret,
    required SimpleKeyPair ourSignedPreKey,
  }) async {
    final rootKey = await _hkdfDerive(sharedSecret, 'sojorn-dr-init-v1');

    // Receiver's initial state: no sending chain yet (created on first DH ratchet)
    final pubBytes =
        Uint8List.fromList((await ourSignedPreKey.extractPublicKey()).bytes);

    return RatchetSession(
      rootKey: rootKey,
      sendingChainKey: Uint8List(32), // placeholder — created on first DH ratchet step
      ourRatchetKeyPair: ourSignedPreKey,
      ourRatchetPubBytes: pubBytes,
      theirRatchetPubBytes: null, // set on first decrypt via DH ratchet step
      receivingChainKey: null,    // derived on first received message
    );
  }

  // ─── Encrypt ────────────────────────────────────────────────────────────────

  /// Encrypt [plaintext]. Returns ciphertext bytes and the ratchet header fields
  /// that must be included in the message header alongside the existing
  /// X3DH fields (on the first message) or as a standalone header thereafter.
  Future<EncryptedRatchetPayload> encrypt(String plaintext) async {
    // Advance sending chain → message key
    final (msgKey, nextCk) = await _kdfChain(sendingChainKey);
    sendingChainKey = nextCk;
    final msgNum = sendCount;
    sendCount++;

    // AES-256-GCM encrypt
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(msgKey),
      nonce: nonce,
    );

    return EncryptedRatchetPayload(
      ciphertext: base64Encode(box.cipherText),
      iv: base64Encode(nonce),
      mac: base64Encode(box.mac.bytes),
      ratchetPubKey: base64Encode(ourRatchetPubBytes),
      messageNumber: msgNum,
      previousChainLength: previousSendCount,
    );
  }

  // ─── Decrypt ────────────────────────────────────────────────────────────────

  /// Decrypt a ratchet-encrypted message.
  /// [senderRatchetPub] must be the raw bytes of the sender's ratchet public key
  /// from the message header.
  Future<String> decrypt({
    required String ciphertext,
    required String iv,
    required String mac,
    required Uint8List senderRatchetPub,
    required int messageNumber,
    required int previousChainLength,
  }) async {
    // 1. Check skipped key cache first (handles out-of-order delivery)
    final skipKey =
        '${base64Encode(senderRatchetPub)}:$messageNumber';
    if (skippedKeys.containsKey(skipKey)) {
      final msgKey = skippedKeys.remove(skipKey)!;
      return _aesDecrypt(ciphertext, iv, mac, msgKey);
    }

    // 2. If sender's ratchet key has changed → DH ratchet step needed
    final ratchetChanged = theirRatchetPubBytes == null ||
        !_bytesEqual(senderRatchetPub, theirRatchetPubBytes!);

    if (ratchetChanged) {
      // Store skipped keys in OLD receiving chain (up to previousChainLength)
      await _skipReceiverChain(previousChainLength);

      // Advance root + receiving chain with new DH output
      final theirPub =
          SimplePublicKey(senderRatchetPub, type: KeyPairType.x25519);
      final dhOut = await _x25519.sharedSecretKey(
          keyPair: ourRatchetKeyPair, remotePublicKey: theirPub);
      final dhBytes = Uint8List.fromList(await dhOut.extractBytes());

      final (newRoot, newReceivingCk) = await _kdfRootChain(rootKey, dhBytes);
      rootKey = newRoot;
      receivingChainKey = newReceivingCk;
      receiveCount = 0;
      theirRatchetPubBytes = senderRatchetPub;

      // Advance our own ratchet key and sending chain
      final newOurKey = await _x25519.newKeyPair();
      final newOurPub =
          Uint8List.fromList((await newOurKey.extractPublicKey()).bytes);
      final dhOut2 = await _x25519.sharedSecretKey(
          keyPair: newOurKey, remotePublicKey: theirPub);
      final dhBytes2 = Uint8List.fromList(await dhOut2.extractBytes());
      final (root2, sendingCk) = await _kdfRootChain(rootKey, dhBytes2);
      rootKey = root2;
      previousSendCount = sendCount;
      sendCount = 0;
      sendingChainKey = sendingCk;
      ourRatchetKeyPair = newOurKey;
      ourRatchetPubBytes = newOurPub;
    }

    // 3. Skip to messageNumber in receiving chain, caching intermediate keys
    await _skipReceiverChain(messageNumber);

    // 4. Derive the message key at [messageNumber]
    final (msgKey, nextCk) = await _kdfChain(receivingChainKey!);
    receivingChainKey = nextCk;
    receiveCount++;

    return _aesDecrypt(ciphertext, iv, mac, msgKey);
  }

  // ─── Internal helpers ────────────────────────────────────────────────────────

  /// Store intermediate receiving chain keys for skipped messages.
  Future<void> _skipReceiverChain(int targetCount) async {
    if (receivingChainKey == null) return;
    while (receiveCount < targetCount) {
      if (skippedKeys.length >= _maxSkipKeys) {
        throw RatchetException('Too many skipped messages (${skippedKeys.length})');
      }
      final (msgKey, nextCk) = await _kdfChain(receivingChainKey!);
      final key = '${base64Encode(theirRatchetPubBytes ?? Uint8List(0))}:$receiveCount';
      skippedKeys[key] = msgKey;
      receivingChainKey = nextCk;
      receiveCount++;
    }
  }

  Future<String> _aesDecrypt(
      String ciphertext, String iv, String mac, Uint8List msgKey) async {
    final box = SecretBox(
      base64Decode(ciphertext),
      nonce: base64Decode(iv),
      mac: Mac(base64Decode(mac)),
    );
    try {
      final plaintext = await _aes.decrypt(box, secretKey: SecretKey(msgKey));
      return utf8.decode(plaintext);
    } catch (e) {
      throw RatchetException('MAC verification failed — message tampered or wrong key');
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ─── Serialization ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'root_key': base64Encode(rootKey),
    'sending_ck': base64Encode(sendingChainKey),
    'send_count': sendCount,
    'prev_send_count': previousSendCount,
    'receiving_ck': receivingChainKey != null ? base64Encode(receivingChainKey!) : null,
    'receive_count': receiveCount,
    'our_ratchet_pub': base64Encode(ourRatchetPubBytes),
    'their_ratchet_pub': theirRatchetPubBytes != null ? base64Encode(theirRatchetPubBytes!) : null,
    'skipped': skippedKeys.map((k, v) => MapEntry(k, base64Encode(v))),
  };

  // Note: full deserialization requires re-importing the key pair from seed,
  // which is handled by RatchetSessionStore (it stores the seed separately).
}

// ─── Encrypted output ────────────────────────────────────────────────────────

class EncryptedRatchetPayload {
  final String ciphertext;
  final String iv;
  final String mac;
  final String ratchetPubKey;   // base64 of sender's DH ratchet public key
  final int messageNumber;
  final int previousChainLength;

  const EncryptedRatchetPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
    required this.ratchetPubKey,
    required this.messageNumber,
    required this.previousChainLength,
  });

  /// Merge into a standard message header map alongside X3DH fields.
  Map<String, dynamic> toHeaderAdditions() => {
    'v': 2,
    'rk': ratchetPubKey,
    'n': messageNumber,
    'pn': previousChainLength,
    'm': mac,
  };
}

// ─── Session persistence ─────────────────────────────────────────────────────

/// Stores and retrieves Double Ratchet session state per conversation partner.
/// Keyed by [userId + partnerId] in FlutterSecureStorage.
class RatchetSessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'sojorn_e2ee_keys',
      publicKey: 'sojorn_e2ee_public',
    ),
  );

  static String _key(String userId, String partnerId) =>
      '$_storagePrefix${userId}_$partnerId';

  /// Persist a session's serializable fields + the ratchet key pair seed.
  static Future<void> save(
    String userId,
    String partnerId,
    RatchetSession session,
  ) async {
    final seed = Uint8List.fromList(
        await session.ourRatchetKeyPair.extractPrivateKeyBytes());
    final json = session.toJson();
    json['ratchet_key_seed'] = base64Encode(seed);
    await _storage.write(key: _key(userId, partnerId), value: jsonEncode(json));
  }

  /// Load a persisted session, returning null if none exists.
  static Future<(RatchetSession, Uint8List)?> load(
    String userId,
    String partnerId,
  ) async {
    final raw = await _storage.read(key: _key(userId, partnerId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final seed = base64Decode(json['ratchet_key_seed'] as String);
      final keyPair = await _x25519.newKeyPairFromSeed(seed);
      final pubBytes =
          Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

      final skipped = <String, Uint8List>{};
      if (json['skipped'] is Map) {
        (json['skipped'] as Map).forEach((k, v) {
          skipped[k as String] = base64Decode(v as String);
        });
      }

      final session = RatchetSession(
        rootKey: base64Decode(json['root_key'] as String),
        sendingChainKey: base64Decode(json['sending_ck'] as String),
        sendCount: json['send_count'] as int,
        previousSendCount: json['prev_send_count'] as int,
        receivingChainKey: json['receiving_ck'] != null
            ? base64Decode(json['receiving_ck'] as String)
            : null,
        receiveCount: json['receive_count'] as int,
        ourRatchetKeyPair: keyPair,
        ourRatchetPubBytes: pubBytes,
        theirRatchetPubBytes: json['their_ratchet_pub'] != null
            ? base64Decode(json['their_ratchet_pub'] as String)
            : null,
        skippedKeys: skipped,
      );
      return (session, seed);
    } catch (e) {
      // Corrupted state — caller will re-establish via X3DH
      await _storage.delete(key: _key(userId, partnerId));
      return null;
    }
  }

  static Future<void> delete(String userId, String partnerId) async {
    await _storage.delete(key: _key(userId, partnerId));
  }
}

// ─── Exception ───────────────────────────────────────────────────────────────

class RatchetException implements Exception {
  final String message;
  const RatchetException(this.message);
  @override
  String toString() => 'RatchetException: $message';
}
