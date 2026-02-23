// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hardened local message store with retry logic, integrity verification,
/// and batch operations for reliable message persistence.
class LocalMessageStore {
  LocalMessageStore._internal();

  static final LocalMessageStore instance = LocalMessageStore._internal();

  static const String _keyStorageKey = 'secure_chat_cache_key_v2';
  static const String _messageBoxName = 'secure_chat_messages_v3';
  static const String _conversationBoxName = 'secure_chat_conversations_v3';
  static const String _messageIndexBoxName = 'secure_chat_message_index_v3';
  static const String _walBoxName = 'secure_chat_wal_v3';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(milliseconds: 100);
  static const int _currentVersion = 2;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Cipher _cipher = AesGcm.with256bits();

  SecretKey? _cachedKey;
  Box<String>? _messageBox;
  Box<List>? _conversationBox;
  Box<String>? _messageIndexBox;
  Box<String>? _walBox;
  bool _boxesReady = false;
  Future<void>? _boxesOpenFuture;

  /// In-memory write-ahead log for pending saves (survives async delays)
  final Map<String, _PendingSave> _writeAheadLog = {};

  /// Track save timestamps for sync verification
  final Map<String, DateTime> _lastSaveTimestamps = {};

  // ── Decrypted record cache — avoids re-decrypting unchanged msgs ──
  final Map<String, LocalMessageRecord> _recordCache = {};

  Future<void> _ensureBoxes() async {
    if (_boxesReady) return;
    _boxesOpenFuture ??= _openBoxes();
    await _boxesOpenFuture;
  }

  /// Pre-warm Hive storage in the background (call at app startup).
  /// Ensures IndexedDB/Hive is ready before the user opens a chat.
  Future<void> prewarm() async {
    _boxesOpenFuture ??= _openBoxes();
  }

  Future<void> _openBoxes() async {
    final sw = Stopwatch()..start();
    await Hive.initFlutter();
    if (kDebugMode) debugPrint('[LocalStore] Hive.initFlutter: ${sw.elapsedMilliseconds}ms');
    _messageBox = await Hive.openBox<String>(_messageBoxName);
    if (kDebugMode) debugPrint('[LocalStore] openBox messages: ${sw.elapsedMilliseconds}ms');
    _conversationBox = await Hive.openBox<List>(_conversationBoxName);
    if (kDebugMode) debugPrint('[LocalStore] openBox conversations: ${sw.elapsedMilliseconds}ms');
    _messageIndexBox = await Hive.openBox<String>(_messageIndexBoxName);
    if (kDebugMode) debugPrint('[LocalStore] openBox index: ${sw.elapsedMilliseconds}ms');
    _walBox = await Hive.openBox<String>(_walBoxName);
    if (kDebugMode) debugPrint('[LocalStore] openBox WAL: ${sw.elapsedMilliseconds}ms');
    
    // Recovery: Load WAL from disk into memory
    for (var key in _walBox!.keys) {
      final json = _walBox!.get(key);
      if (json != null) {
        try {
          final map = jsonDecode(json);
          _writeAheadLog[key.toString()] = _PendingSave.fromJson(map);
        } catch (_) {}
      }
    }
    
    if (kDebugMode) debugPrint('[LocalStore] All boxes ready: ${sw.elapsedMilliseconds}ms total');
    _boxesReady = true;
  }

  Future<SecretKey> _getKey() async {
    if (_cachedKey != null) return _cachedKey!;

    try {
      final stored = await _secureStorage.read(key: _keyStorageKey);
      if (stored != null && stored.isNotEmpty) {
        _cachedKey = SecretKey(base64Decode(stored));
        return _cachedKey!;
      }
    } catch (e) {
    }

    final bytes = _generateRandomBytes(32);
    _cachedKey = SecretKey(bytes);

    // Retry key storage with exponential backoff
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _secureStorage.write(
          key: _keyStorageKey,
          value: base64Encode(bytes),
        );
        return _cachedKey!;
      } catch (e) {
        if (attempt == _maxRetries - 1) rethrow;
        await Future.delayed(_retryDelay * (attempt + 1));
      }
    }
    return _cachedKey!;
  }

  /// Save a message with retry logic and integrity verification.
  /// Uses write-ahead logging to prevent data loss during async operations.
  Future<bool> saveMessage({
    required String conversationId,
    required String messageId,
    required String plaintext,
    String? senderId,
    DateTime? createdAt,
    int? messageType,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? expiresAt,
  }) async {
    // Add to write-ahead log immediately (memory-safe copy)
    final pending = _PendingSave(
      conversationId: conversationId,
      messageId: messageId,
      plaintext: plaintext,
      timestamp: DateTime.now(),
      senderId: senderId,
      createdAt: createdAt,
      messageType: messageType,
      deliveredAt: deliveredAt,
      readAt: readAt,
      expiresAt: expiresAt,
    );
    
    _writeAheadLog[messageId] = pending;
    
    // PERSIST WAL to Disk Immediately
    try {
      await _ensureBoxes();
      await _walBox?.put(messageId, jsonEncode(pending.toJson()));
    } catch (_) {}

    bool success = false;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _ensureBoxes();
        final key = await _getKey();
        final nonce = _cipher.newNonce();
        final secretBox = await _cipher.encrypt(
          utf8.encode(plaintext),
          secretKey: key,
          nonce: nonce,
        );

        // Include integrity hash and version in payload
        final plaintextHash = _computeHash(plaintext);
        final payload = jsonEncode({
          'v': _currentVersion,
          'c': base64Encode(secretBox.cipherText),
          'n': base64Encode(secretBox.nonce),
          'm': base64Encode(secretBox.mac.bytes),
          'h': plaintextHash,
          't': DateTime.now().toIso8601String(),
          if (senderId != null) 'sender_id': senderId,
          if (createdAt != null) 'created_at': createdAt.toIso8601String(),
          if (messageType != null) 'message_type': messageType,
          if (deliveredAt != null)
            'delivered_at': deliveredAt.toIso8601String(),
          if (readAt != null) 'read_at': readAt.toIso8601String(),
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        });

        await _messageBox!.put(messageId, payload);

        final existingConversation = _messageIndexBox!.get(messageId);
        if (existingConversation != conversationId) {
          if (existingConversation != null &&
              existingConversation != conversationId) {
            final oldIds = await _getConversationIndex(existingConversation);
            oldIds.remove(messageId);
            await _conversationBox!.put(existingConversation, oldIds);
          }

          final ids = await _getConversationIndex(conversationId);
          if (!ids.contains(messageId)) {
            ids.add(messageId);
            await _conversationBox!.put(conversationId, ids);
          }
          await _messageIndexBox!.put(messageId, conversationId);
        }

        _lastSaveTimestamps[messageId] = DateTime.now();
        success = true;
        break;
      } catch (e) {
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay * (attempt + 1));
        }
      }
    }

    // Remove from write-ahead log only on success
    if (success) {
      _writeAheadLog.remove(messageId);
      await _walBox?.delete(messageId);
    }

    return success;
  }

  /// Get a message with integrity verification and fallback to write-ahead log.
  Future<String?> getMessage(String messageId) async {
    // First check write-ahead log for very recent saves
    final pending = _writeAheadLog[messageId];
    if (pending != null) {
      if (DateTime.now().difference(pending.timestamp).inSeconds < 5) {
        return pending.plaintext;
      }
    }

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _ensureBoxes();
        final payload = _messageBox!.get(messageId);
        if (payload == null || payload.isEmpty) {
          return pending?.plaintext;
        }

        final data = jsonDecode(payload) as Map<String, dynamic>;
        final version = data['v'] as int? ?? 1;
        final ciphertext = base64Decode(data['c'] as String);
        final nonce = base64Decode(data['n'] as String);
        final mac = base64Decode(data['m'] as String);
        final storedHash = data['h'] as String?;

        final key = await _getKey();
        final secretBox = SecretBox(
          ciphertext,
          nonce: nonce,
          mac: Mac(mac),
        );
        final bytes = await _cipher.decrypt(secretBox, secretKey: key);
        final plaintext = utf8.decode(bytes);

        if (version >= 2 && storedHash != null) {
          final computedHash = _computeHash(plaintext);
          if (computedHash != storedHash) {
            return pending?.plaintext;
          }
        }

        return plaintext;
      } catch (e) {
        if (e.toString().contains('SecretBoxAuthenticationError')) {
          await _messageBox!.delete(messageId);
          return pending?.plaintext;
        }
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay * (attempt + 1));
        }
      }
    }

    return pending?.plaintext;
  }

  /// Batch load messages for a conversation (more efficient than individual loads).
  Future<Map<String, String>> getMessagesForConversation(
    String conversationId, {
    int? limit,
  }) async {
    final results = <String, String>{};

    try {
      await _ensureBoxes();
      var messageIds = await _getConversationIndex(conversationId);
      final effectiveLimit = limit ?? 50;
      if (effectiveLimit > 0 && messageIds.length > effectiveLimit) {
        messageIds = messageIds.sublist(messageIds.length - effectiveLimit);
      }

      const batchSize = 20;
      for (var i = 0; i < messageIds.length; i += batchSize) {
        final batch = messageIds.skip(i).take(batchSize).toList();
        final futures = batch.map((id) async {
          final plaintext = await getMessage(id);
          if (plaintext != null) {
            return MapEntry(id, plaintext);
          }
          return null;
        });

        final entries = await Future.wait(futures);
        for (final entry in entries) {
          if (entry != null) {
            results[entry.key] = entry.value;
          }
        }

        if (batch.length == batchSize) {
          await Future.delayed(Duration.zero);
        }
      }
    } catch (e) {
    }

    // Include any pending saves from WAL
    for (final pending in _writeAheadLog.values) {
      if (pending.conversationId == conversationId) {
        results[pending.messageId] = pending.plaintext;
      }
    }

    return results;
  }

  /// Batch load message records (plaintext + metadata) for a conversation.
  Future<List<LocalMessageRecord>> getMessageRecordsForConversation(
    String conversationId, {
    int? limit,
  }) async {
    final results = <LocalMessageRecord>[];
    final seen = <String>{};

    try {
      await _ensureBoxes();
      var messageIds = await _getConversationIndex(conversationId);
      final effectiveLimit = limit ?? 50;
      if (effectiveLimit > 0 && messageIds.length > effectiveLimit) {
        messageIds = messageIds.sublist(messageIds.length - effectiveLimit);
      }

      final key = await _getKey();

      const batchSize = 20;
      for (var i = 0; i < messageIds.length; i += batchSize) {
        final batch = messageIds.skip(i).take(batchSize).toList();
        final entries = await Future.wait(batch.map((id) async {
          final payload = _messageBox!.get(id);
          if (payload == null || payload.isEmpty) return null;
          return _readMessageRecord(
            conversationId: conversationId,
            messageId: id,
            payload: payload,
            key: key,
          );
        }));

        for (final entry in entries) {
          if (entry != null && seen.add(entry.messageId)) {
            results.add(entry);
          }
        }

        if (batch.length == batchSize) {
          await Future.delayed(Duration.zero);
        }
      }
    } catch (e) {
    }

    // Include any pending saves from WAL
    for (final pending in _writeAheadLog.values) {
      if (pending.conversationId != conversationId) continue;
      if (!seen.add(pending.messageId)) continue;
      results.add(LocalMessageRecord(
        conversationId: pending.conversationId,
        messageId: pending.messageId,
        plaintext: pending.plaintext,
        senderId: pending.senderId,
        messageType: pending.messageType,
        createdAt: pending.createdAt ?? pending.timestamp,
        deliveredAt: pending.deliveredAt,
        readAt: pending.readAt,
        expiresAt: pending.expiresAt,
      ));
    }

    results.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return results;
  }

  /// Get ALL message records across ALL conversations (for backup).
  Future<List<LocalMessageRecord>> getAllMessageRecords() async {
    final results = <LocalMessageRecord>[];
    try {
      await _ensureBoxes();
      final allConversations = await getAllConversationIds();
      
      for (final conversationId in allConversations) {
        final messages = await getMessageRecordsForConversation(conversationId, limit: 10000); // High limit for backup
        results.addAll(messages);
      }
    } catch (e) {
    }
    return results;
  }
  
  /// Get all conversation IDs.
  Future<List<String>> getAllConversationIds() async {
    await _ensureBoxes();
    return _conversationBox!.keys.cast<String>().toList();
  }

  /// Save a raw message record (for restore).
  Future<bool> saveMessageRecord(LocalMessageRecord record) async {
    return saveMessage(
      conversationId: record.conversationId,
      messageId: record.messageId,
      plaintext: record.plaintext,
      senderId: record.senderId,
      createdAt: record.createdAt,
      messageType: record.messageType,
      deliveredAt: record.deliveredAt,
      readAt: record.readAt,
      expiresAt: record.expiresAt,
    );
  }

  /// Get list of message IDs for a conversation.
  Future<List<String>> getMessageIdsForConversation(String conversationId) async {
    try {
      return await _getConversationIndex(conversationId);
    } catch (e) {
      return <String>[];
    }
  }

  /// Check if a message exists in local storage.
  Future<bool> hasMessage(String messageId) async {
    if (_writeAheadLog.containsKey(messageId)) return true;
    try {
      await _ensureBoxes();
      return _messageBox!.containsKey(messageId);
    } catch (e) {
      return false;
    }
  }

  /// Delete a message with verification.
  Future<bool> deleteMessage(String messageId) async {
    _writeAheadLog.remove(messageId);
    _lastSaveTimestamps.remove(messageId);
    _recordCache.remove(messageId);

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _ensureBoxes();
        final conversationId = _messageIndexBox!.get(messageId);
        await _messageBox!.delete(messageId);
        await _messageIndexBox!.delete(messageId);

        if (conversationId != null) {
          final ids = await _getConversationIndex(conversationId);
          ids.remove(messageId);
          await _conversationBox!.put(conversationId, ids);
        }

        return true;
      } catch (e) {
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay * (attempt + 1));
        }
      }
    }
    return false;
  }

  /// Delete all messages in a conversation.
  Future<bool> deleteConversation(String conversationId) async {
    _writeAheadLog.removeWhere((_, v) => v.conversationId == conversationId);

    // Invalidate cache for this conversation's messages
    final idsToEvict = _recordCache.entries
        .where((e) => e.value.conversationId == conversationId)
        .map((e) => e.key)
        .toList();
    for (final id in idsToEvict) {
      _recordCache.remove(id);
    }

    try {
      await _ensureBoxes();
      final ids = await _getConversationIndex(conversationId);

      const batchSize = 50;
      for (var i = 0; i < ids.length; i += batchSize) {
        final batch = ids.skip(i).take(batchSize).toList();
        for (final id in batch) {
          _lastSaveTimestamps.remove(id);
          await _messageBox!.delete(id);
          await _messageIndexBox!.delete(id);
        }
        if (batch.length == batchSize) {
          await Future.delayed(Duration.zero);
        }
      }

      await _conversationBox!.delete(conversationId);
      
      // Also clean WAL for this conversation
      final walKeysToDelete = _writeAheadLog.entries
          .where((e) => e.value.conversationId == conversationId)
          .map((e) => e.key)
          .toList();
      for (var key in walKeysToDelete) {
        _writeAheadLog.remove(key);
        await _walBox?.delete(key);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Flush any pending writes from the write-ahead log.
  Future<void> flushPendingWrites() async {
    final pendingCopy = Map<String, _PendingSave>.from(_writeAheadLog);

    for (final entry in pendingCopy.entries) {
      final pending = entry.value;
      final success = await saveMessage(
        conversationId: pending.conversationId,
        messageId: pending.messageId,
        plaintext: pending.plaintext,
        senderId: pending.senderId,
        createdAt: pending.createdAt,
        messageType: pending.messageType,
        deliveredAt: pending.deliveredAt,
        readAt: pending.readAt,
        expiresAt: pending.expiresAt,
      );
      if (success) {
      }
    }
  }

  /// Fast check for any pending writes.
  Future<bool> hasPendingWrites() async {
    return _writeAheadLog.isNotEmpty;
  }

  /// Get sync metadata for a conversation (for cross-device sync verification).
  Future<Map<String, dynamic>> getSyncMetadata(String conversationId) async {
    final messageIds = await getMessageIdsForConversation(conversationId);
    final timestamps = <String, String>{};

    for (final id in messageIds) {
      final ts = _lastSaveTimestamps[id];
      if (ts != null) {
        timestamps[id] = ts.toIso8601String();
      }
    }

    return {
      'conversation_id': conversationId,
      'message_count': messageIds.length,
      'message_ids': messageIds,
      'save_timestamps': timestamps,
      'pending_writes': _writeAheadLog.keys
          .where((k) => _writeAheadLog[k]?.conversationId == conversationId)
          .toList(),
    };
  }

  /// Clear all cached data (for logout).
  Future<void> clearAll() async {
    _cachedKey = null;
    _writeAheadLog.clear();
    _lastSaveTimestamps.clear();
    _recordCache.clear();

    if (_boxesReady) {
      await _messageBox?.clear();
      await _conversationBox?.clear();
      await _messageIndexBox?.clear();
    }
  }

  String _computeHash(String plaintext) {
    var hash = 0;
    for (var i = 0; i < plaintext.length; i++) {
      hash = ((hash << 5) - hash) + plaintext.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<List<String>> _getConversationIndex(String conversationId) async {
    await _ensureBoxes();
    final raw = _conversationBox!.get(conversationId);
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return <String>[];
  }

  Future<LocalMessageRecord?> _readMessageRecord({
    required String conversationId,
    required String messageId,
    required String payload,
    required SecretKey key,
  }) async {
    // Return cached record to avoid redundant AES-GCM decryptions
    final cached = _recordCache[messageId];
    if (cached != null) return cached;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final version = data['v'] as int? ?? 1;
      final ciphertext = base64Decode(data['c'] as String);
      final nonce = base64Decode(data['n'] as String);
      final mac = base64Decode(data['m'] as String);
      final storedHash = data['h'] as String?;

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(mac),
      );
      final bytes = await _cipher.decrypt(secretBox, secretKey: key);
      final plaintext = utf8.decode(bytes);

      if (version >= 2 && storedHash != null) {
        final computedHash = _computeHash(plaintext);
        if (computedHash != storedHash) {
          return null;
        }
      }

      final senderId = data['sender_id'] as String?;
      final createdAt =
          _parseTimestamp(data['created_at']) ??
          _parseTimestamp(data['t']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final messageType = _parseInt(data['message_type']);
      final deliveredAt = _parseTimestamp(data['delivered_at']);
      final readAt = _parseTimestamp(data['read_at']);
      final expiresAt = _parseTimestamp(data['expires_at']);

      final record = LocalMessageRecord(
        conversationId: conversationId,
        messageId: messageId,
        plaintext: plaintext,
        senderId: senderId,
        messageType: messageType,
        createdAt: createdAt,
        deliveredAt: deliveredAt,
        readAt: readAt,
        expiresAt: expiresAt,
      );
      _recordCache[messageId] = record;
      return record;
    } catch (e) {
      if (e.toString().contains('SecretBoxAuthenticationError')) {
        _messageBox!.delete(messageId);
        return null;
      }
      return null;
    }
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<int> _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  
}

/// Internal class for write-ahead log entries.
class _PendingSave {
  final String conversationId;
  final String messageId;
  final String plaintext;
  final DateTime timestamp;
  final String? senderId;
  final DateTime? createdAt;
  final int? messageType;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? expiresAt;

  _PendingSave({
    required this.conversationId,
    required this.messageId,
    required this.plaintext,
    required this.timestamp,
    this.senderId,
    this.createdAt,
    this.messageType,
    this.deliveredAt,
    this.readAt,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'messageId': messageId,
    'plaintext': plaintext,
    'timestamp': timestamp.toIso8601String(),
    'senderId': senderId,
    'createdAt': createdAt?.toIso8601String(),
    'messageType': messageType,
    'deliveredAt': deliveredAt?.toIso8601String(),
    'readAt': readAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory _PendingSave.fromJson(Map<String, dynamic> json) => _PendingSave(
    conversationId: json['conversationId'],
    messageId: json['messageId'],
    plaintext: json['plaintext'],
    timestamp: DateTime.parse(json['timestamp']),
    senderId: json['senderId'],
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    messageType: json['messageType'],
    deliveredAt: json['deliveredAt'] != null ? DateTime.parse(json['deliveredAt']) : null,
    readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
    expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
  );
}

/// Local message record with plaintext and metadata.
class LocalMessageRecord {
  final String conversationId;
  final String messageId;
  final String plaintext;
  final String? senderId;
  final int? messageType;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? expiresAt;

  LocalMessageRecord({
    required this.conversationId,
    required this.messageId,
    required this.plaintext,
    required this.createdAt,
    this.senderId,
    this.messageType,
    this.deliveredAt,
    this.readAt,
    this.expiresAt,
  });
}
