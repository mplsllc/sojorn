import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';

import '../models/secure_chat.dart';
import 'local_message_store.dart';
import 'simple_e2ee_service.dart';
import 'auth_service.dart';
import 'api_service.dart';
import 'content_guard_service.dart';

/// Secure chat service that ingests from Go WebSockets, writes to Hive, and only
/// exposes local streams to the UI.
class SecureChatService {
  static SecureChatService? _instance;

  static SecureChatService get instance =>
      _instance ??= SecureChatService._internal();

  factory SecureChatService({
    SimpleE2EEService? e2eeService,
  }) {
    _instance ??= SecureChatService._internal(
      e2eeService: e2eeService,
    );
    return _instance!;
  }

  final AuthService _auth = AuthService.instance;
  final SimpleE2EEService _e2ee;
  final ApiService _api;
  final LocalMessageStore _localStore = LocalMessageStore.instance;

  final Map<String, StreamController<List<LocalMessageRecord>>>
      _localControllers = {};
  final Map<String, Set<String>> _processedMessageIds = {};
  final Set<String> _locallyDeletedMessageIds = {};
  Timer? _backgroundSyncTimer;
  bool _disposed = false;
  
  // Conversation list change notifier
  final _conversationListController = StreamController<void>.broadcast();
  Stream<void> get conversationListChanges => _conversationListController.stream;
  
  // WebSocket
  WebSocketChannel? _wsChannel;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeat;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 60; // seconds

  SecureChatService._internal({
    SimpleE2EEService? e2eeService,
    ApiService? apiService,
  })  : _e2ee = e2eeService ?? SimpleE2EEService(),
        _api = apiService ?? ApiService.instance {
    // Set back-reference to avoid circular dependency
    _e2ee.setChatService(this);
  }

  String? get currentUserId => _auth.currentUser?.id;

  // Broadcast key recovery event to all user's devices
  void broadcastKeyRecovery(String userId) {
    if (_wsChannel != null) {
      final keyRecoveryEvent = {
        'type': 'key_recovery',
        'payload': {
          'user_id': userId,
          'timestamp': DateTime.now().toIso8601String(),
        }
      };
      try {
        _wsChannel!.sink.add(jsonEncode(keyRecoveryEvent));
      } catch (e) {
      }
    }
  }

  Future<void> resetIdentityKeys() async {
    await _e2ee.resetIdentityKeys();
  }

  // Manual key upload for testing
  Future<void> uploadKeysManually() async {
    await _e2ee.uploadKeysManually();
  }

  
  Future<void> initialize({bool generateIfMissing = false}) async {
    await _e2ee.initialize();
    if (!_e2ee.isReady && generateIfMissing) {
      await _e2ee.generateNewIdentity();
    }
    connectRealtime();
  }
  
  void connectRealtime() {
      final token = AuthService.instance.accessToken;
      if (token == null) return;
      if (_wsChannel != null) return; // Already connected
      if (_isReconnecting) return;

      final wsUrl = Uri.parse(ApiConfig.baseUrl)
          .replace(scheme: ApiConfig.baseUrl.startsWith('https') ? 'wss' : 'ws', path: '/ws', queryParameters: {'token': token});

      _isReconnecting = true;
      
      try {
        _wsChannel = WebSocketChannel.connect(wsUrl);
        _isReconnecting = false;
        _reconnectAttempts = 0; // Reset on successful connect
        _startHeartbeat();
        
        _wsChannel!.stream.listen((message) {
            _lastHeartbeat = DateTime.now();
            if (message is String) {
                try {
                  final data = jsonDecode(message);
                  final type = data['type'] as String?;
                  
                  // Filter out ping/pong messages completely
                  if (type == 'pong' || type == 'ping') {
                    return; // Silently ignore
                  }
                  
                  
                  if (type == 'new_message') {
                    final payload = data['payload'];
                    final conversationId = payload['conversation_id'];
                    if (conversationId != null) {
                        _ingestRemoteSnapshot(conversationId.toString(), [payload]);
                    }
                  } else if (data['type'] == 'message_deleted') {
                    final payload = data['payload'];
                    final messageId = payload['message_id'];
                    final conversationId = payload['conversation_id'];
                    if (messageId != null && conversationId != null) {
                      _locallyDeletedMessageIds.add(messageId);
                      unawaited(_localStore.deleteMessage(messageId));
                      _processedMessageIds[conversationId]?.remove(messageId);
                      // IMMEDIATE UI update - no delay
                      unawaited(_emitLocal(conversationId));
                      // Check if conversation is now empty
                      unawaited(_checkAndDeleteEmptyConversation(conversationId));
                    }
                  } else if (data['type'] == 'conversation_deleted') {
                    final payload = data['payload'];
                    final conversationId = payload['conversation_id'];
                    if (conversationId != null) {
                      unawaited(_localStore.deleteConversation(conversationId));
                      _processedMessageIds.remove(conversationId);
                      _localControllers[conversationId]?.close();
                      _localControllers.remove(conversationId);
                      // Notify conversation list UI
                      _conversationListController.add(null);
                    }
                  } else if (data['type'] == 'key_recovery') {
                    final payload = data['payload'];
                    final userId = payload['user_id'];
                    final currentUserId = _auth.currentUser?.id;
                    if (userId != null && currentUserId != null && userId == currentUserId) {
                      unawaited(_e2ee.initiateKeyRecovery(currentUserId));
                    }
                  } else if (data['type'] == 'pong') {
                    // Heartbeat response - silent
                    _lastHeartbeat = DateTime.now();
                  }
                } catch (e) {
                }
            }
        }, onError: (e) {
            _cleanup();
            _scheduleReconnect();
        }, onDone: () {
            _cleanup();
            _scheduleReconnect();
        });
      } catch (e) {
          _isReconnecting = false;
          _scheduleReconnect();
      }
  }

  void _startHeartbeat() {
    // Heartbeat disabled - no more ping/pong spam
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    // Exponential backoff: 2s, 4s, 8s, 16s, 32s, 60s cap
    final delay = (_reconnectAttempts < 6)
        ? Duration(seconds: 1 << _reconnectAttempts) // 2, 4, 8, 16, 32
        : Duration(seconds: _maxReconnectDelay);
    Future.delayed(delay, connectRealtime);
  }

  void _cleanup() {
    _wsChannel?.sink.close();
    _wsChannel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isReconnecting = false;
  }

  Future<bool> isReady() async {
    return _e2ee.isReady;
  }

  Future<void> generateNewIdentity() async {
    await _e2ee.generateNewIdentity();
  }

  void startBackgroundSync({Duration interval = const Duration(minutes: 5)}) {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(interval, (_) {
      unawaited(syncAllConversations());
    });
    unawaited(syncAllConversations());
  }

  void stopBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }

  void dispose() {
    _disposed = true;
    for (final controller in _localControllers.values) {
      controller.close();
    }
    _backgroundSyncTimer?.cancel();
    _heartbeatTimer?.cancel();
    _conversationListController.close();
    _localControllers.clear();
    _wsChannel?.sink.close();
  }

  // --- Core Messaging Logic ---

  Future<EncryptedMessage?> sendMessage(
    String conversationId,
    String recipientId,
    String plaintext, {
    Duration? expiresIn,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      // 0. Local content guard — block before encryption
      final guardReason = ContentGuardService.instance.check(plaintext);
      if (guardReason != null) {
        throw ContentBlockedException(guardReason);
      }

      // 0b. Server-side AI moderation — stateless, nothing stored
      final aiReason = await _api.moderateContent(text: plaintext);
      if (aiReason != null) {
        throw ContentBlockedException(aiReason);
      }

      // 1. Encrypt (X3DH)
      final encrypted = await _e2ee.encrypt(recipientId, plaintext);
      
      // 2. Send to Go Backend
      // Go Model expects MessageHeader as a JSON String, not a Map.
      final headerMap = encrypted['header'];
      final headerString = headerMap is String ? headerMap : jsonEncode(headerMap);

      final response = await _api.sendEncryptedMessage(
        conversationId: conversationId,
        receiverId: recipientId,
        ciphertext: encrypted['ciphertext']!,
        iv: encrypted['iv']!,
        messageHeader: headerString, 
        keyVersion: 'x3dh_v1',
        messageType: MessageType.standardMessage,
      );

      final messageJson = response['message'] ?? response;
      final msg = EncryptedMessage.fromJson(
        Map<String, dynamic>.from(messageJson as Map),
      );
      msg.decryptedContent = plaintext;

      // 3. Save to Local Hive Immediately
      await _localStore.saveMessage(
        conversationId: conversationId,
        messageId: msg.id,
        plaintext: plaintext,
        senderId: msg.senderId,
        createdAt: msg.createdAt,
        messageType: msg.messageType,
        deliveredAt: msg.deliveredAt,
        readAt: msg.readAt,
        expiresAt: msg.expiresAt,
      );

      _processedMessageIds
          .putIfAbsent(conversationId, () => <String>{})
          .add(msg.id);
          
      unawaited(_emitLocal(conversationId));
      return msg;
    } catch (e) {
      return null;
    }
  }

  Future<SecureConversation?> getConversationById(String conversationId) async {
     // Fallback to local if API not supported
     final conversations = await getConversations();
     try {
         return conversations.firstWhere((c) => c.id == conversationId);
     } catch (_) {
         return null;
     }
  }

  Future<void> markAsRead(String conversationId) async {
    // Stub: Migrate to Go API
  }

  Future<DeleteResult> deleteMessage(
    String messageId, {
    bool forEveryone = false,
    String? conversationId,
    String? recipientId,
  }) async {
    // IMMEDIATE optimistic delete from local storage
    _locallyDeletedMessageIds.add(messageId);
    unawaited(_localStore.deleteMessage(messageId));

    // IMMEDIATE UI update
    if (conversationId != null) {
      _processedMessageIds[conversationId]?.remove(messageId);
      unawaited(_emitLocal(conversationId));
      
      // Check if conversation is now empty and delete it
      unawaited(_checkAndDeleteEmptyConversation(conversationId));
    }

    // Delete from server (permanent) - fire and forget for speed
    if (forEveryone) {
      unawaited(_api.deleteMessage(messageId).then((success) {
        if (!success) {
        }
      }).catchError((e) {
      }));
    }

    return DeleteResult(success: true);
  }

  Future<void> _checkAndDeleteEmptyConversation(String conversationId) async {
    try {
      // Small delay to ensure message deletion is processed
      await Future.delayed(const Duration(milliseconds: 100));
      
      final messages = await _localStore.getMessagesForConversation(conversationId);
      if (messages.isEmpty) {
        await deleteConversation(conversationId, fullDelete: true);
      }
    } catch (e) {
    }
  }

  Future<DeleteResult> deleteConversation(
    String conversationId, {
    bool fullDelete = false,
  }) async {
    
    // Clear local state IMMEDIATELY
    _processedMessageIds.remove(conversationId);
    _locallyDeletedMessageIds.clear();
    
    // Close and remove stream controller
    _localControllers[conversationId]?.close();
    _localControllers.remove(conversationId);

    // Delete from local IndexedDB storage
    await _localStore.deleteConversation(conversationId);
    
    // Notify conversation list UI IMMEDIATELY
    _conversationListController.add(null);

    // Delete from server (permanent deletion for everyone)
    if (fullDelete) {
      unawaited(_api.deleteConversation(conversationId).then((success) {
        if (success) {
        } else {
        }
      }).catchError((e) {
      }));
    }
    return DeleteResult(success: true);
  }

  void markMessageLocallyDeleted(String messageId) {
    _locallyDeletedMessageIds.add(messageId);
    unawaited(_localStore.deleteMessage(messageId));
  }
  
  // Legacy / No-op
  Future<void> startLiveListener(String conversationId) async {}

  Stream<List<LocalMessageRecord>> getMessagesStream(String conversationId) {
    return watchConversation(conversationId);
  }
  
  // Fix syncAllConversations signature
  Future<void> syncAllConversations({bool force = false}) async {
    final conversations = await getConversations();
    for (final conv in conversations) {
      await syncConversation(conv.id);
    }
  }

  // --- Ingestion & Sync ---

  Future<void> syncConversation(String conversationId) async {
    if (_disposed) return;
    try {
      final rows = await _api.getConversationMessages(conversationId);
      await _ingestRemoteSnapshot(conversationId, rows);
    } catch (e) {
    }
  }

  Future<void> fetchAndDecryptHistory(String conversationId, {int limit = 50}) async {
    if (_disposed) return;
    try {
      final rows = await _api.getConversationMessages(conversationId, limit: limit);
      await _ingestRemoteSnapshot(conversationId, rows); 
    } catch (e) {
    }
  }

  Future<void> _ingestRemoteSnapshot(String conversationId, List<dynamic> rawData) async {
    if (_disposed) return;
    await _e2ee.initialize();
    
    if (!_e2ee.isReady) {
        return;
    }

    final incoming = <EncryptedMessage>[];

    // 1. Filter Check (HIVE Check)
    for (final item in rawData) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        
        // FIX: Ensure messageHeader is passed as Map or String correctly if model expects Object
        // Model expects Object, but _ingest logic needs it to be usable.
        // We let fromJson resolve it.
        final msg = EncryptedMessage.fromJson(map);

        // Check 1: Already Deletion
        if (_locallyDeletedMessageIds.contains(msg.id)) continue;

        // Check 3: Check Hive Store (The Robust Local Check)
        final alreadyHave = await _localStore.getMessage(msg.id);
        if (alreadyHave != null && !_isDecryptionFailurePlaceholder(alreadyHave)) {
            _processedMessageIds.putIfAbsent(conversationId, () => <String>{}).add(msg.id);
            continue;
        }

        incoming.add(msg);
    }
    
    if (incoming.isEmpty) {
        unawaited(_emitLocal(conversationId));
        return;
    }

    // 2. Batch Decrypt
    for (final msg in incoming) {
        if (msg.messageType == MessageType.commandMessage) continue;

        try {
            // SimpleE2EEService.decrypt now handles Map or String (JSON)
            final headerData = msg.messageHeader;

            final plaintext = await _e2ee.decrypt(
                msg.ciphertext, 
                msg.iv, 
                headerData
            );
            
            await _localStore.saveMessage(
                conversationId: conversationId,
                messageId: msg.id,
                plaintext: plaintext,
                senderId: msg.senderId,
                createdAt: msg.createdAt,
                messageType: msg.messageType,
                deliveredAt: msg.deliveredAt,
                readAt: msg.readAt,
                expiresAt: msg.expiresAt,
            );
            
            _processedMessageIds.putIfAbsent(conversationId, () => <String>{}).add(msg.id);
        } catch (e) {
            if (e.toString().contains('Invalid Key') || e.toString().contains('MAC')) {
                 await _localStore.saveMessage(
                    conversationId: conversationId,
                    messageId: msg.id,
                    plaintext: '?? Decryption Error',
                    senderId: msg.senderId,
                    createdAt: msg.createdAt,
                    messageType: msg.messageType
                );
            }
        }
    }

    unawaited(_emitLocal(conversationId));
  }


  bool _isDecryptionFailurePlaceholder(String? plaintext) {
    if (plaintext == null) return true;
    return plaintext.startsWith('?? Decryption Error') ||
        plaintext == '[Unable to decrypt]' ||
        plaintext.isEmpty;
  }

  // --- Local Stream Emit ---

  Future<void> _emitLocal(String conversationId) async {
    final controller = _localControllers[conversationId];
    if (controller == null || controller.isClosed) return;

    final records = (await _localStore.getMessageRecordsForConversation(
      conversationId,
      limit: 200,
    ))
        .where(
          (record) => !_locallyDeletedMessageIds.contains(record.messageId),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (!controller.isClosed) {
      controller.add(records);
    }
  }
  
  // --- Getters & Helpers ---
  
  Stream<List<LocalMessageRecord>> watchConversation(String conversationId) {
    if (_disposed) return const Stream.empty();
    final controller = _localControllers.putIfAbsent(conversationId, () {
      return StreamController<List<LocalMessageRecord>>.broadcast(
        onListen: () {
          unawaited(_emitLocal(conversationId));
          unawaited(syncConversation(conversationId)); 
        },
      );
    });
    // Ensure initial emit
    unawaited(_emitLocal(conversationId));
    if (_wsChannel == null) connectRealtime();
    return controller.stream;
  }
  
  Future<List<SecureConversation>> getConversations() async {
    final userId = currentUserId;
    if (userId == null) return [];
    final response = await _api.getConversations();
    return response.map((row) => SecureConversation.fromJson(row, userId)).toList();
  }

  Future<SecureConversation?> getOrCreateConversation(String otherUserId) async {
    try {
      final id = await _api.getOrCreateConversation(otherUserId);
      return (await getConversations()).firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<MutualFollow>> getMutualFollows() async {
     try {
       final response = await _api.getMutualFollows();
       return response.map((p) => MutualFollow(
           userId: p['id'].toString(),
           handle: p['handle'],
           displayName: p['display_name'],
           avatarUrl: p['avatar_url']
       )).toList();
     } catch (_) { return []; }
  }
  
  Future<void> resetSession(String recipientId) async {
      _processedMessageIds.clear();
      // Also potentially clear local storage encryption keys for them?
  }
}

// Minimal Model Definitions needed if separate file not available
class MutualFollow {
  final String userId;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  MutualFollow({required this.userId, required this.handle, this.displayName, this.avatarUrl});
}
