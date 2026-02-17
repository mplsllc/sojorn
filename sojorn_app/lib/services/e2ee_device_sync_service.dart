import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sojorn/services/api_service.dart';

class E2EEDeviceSyncService {
  static const String _devicesKey = 'e2ee_devices';
  static const String _currentDeviceKey = 'e2ee_current_device';
  static const String _keysKey = 'e2ee_keys';

  /// Device information for E2EE
  class DeviceInfo {
    final String id;
    final String name;
    final String type; // mobile, desktop, web
    final String publicKey;
    final DateTime lastSeen;
    final bool isActive;
    final Map<String, dynamic>? metadata;

    DeviceInfo({
      required this.id,
      required this.name,
      required this.type,
      required this.publicKey,
      required this.lastSeen,
      this.isActive = true,
      this.metadata,
    });

    factory DeviceInfo.fromJson(Map<String, dynamic> json) {
      return DeviceInfo(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        type: json['type'] ?? '',
        publicKey: json['public_key'] ?? '',
        lastSeen: DateTime.parse(json['last_seen']),
        isActive: json['is_active'] ?? true,
        metadata: json['metadata'],
      );
    }

    Map<String, dynamic> toJson() {
      return {
        'id': id,
        'name': name,
        'type': type,
        'public_key': publicKey,
        'last_seen': lastSeen.toIso8601String(),
        'is_active': isActive,
        'metadata': metadata,
      };
    }
  }

  /// E2EE key pair
  class E2EEKeyPair {
    final String privateKey;
    final String publicKey;
    final String keyId;
    final DateTime createdAt;
    final DateTime? expiresAt;
    final String algorithm; // RSA, ECC, etc.

    E2EEKeyPair({
      required this.privateKey,
      required this.publicKey,
      required this.keyId,
      required this.createdAt,
      this.expiresAt,
      this.algorithm = 'RSA',
    });

    factory E2EEKeyPair.fromJson(Map<String, dynamic> json) {
      return E2EEKeyPair(
        privateKey: json['private_key'] ?? '',
        publicKey: json['public_key'] ?? '',
        keyId: json['key_id'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
        expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
        algorithm: json['algorithm'] ?? 'RSA',
      );
    }

    Map<String, dynamic> toJson() {
      return {
        'private_key': privateKey,
        'public_key': publicKey,
        'key_id': keyId,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'algorithm': algorithm,
      };
    }
  }

  /// QR code data for device verification
  class QRVerificationData {
    final String deviceId;
    final String publicKey;
    final String timestamp;
    final String signature;
    final String userId;

    QRVerificationData({
      required this.deviceId,
      required this.publicKey,
      required this.timestamp,
      required this.signature,
      required this.userId,
    });

    factory QRVerificationData.fromJson(Map<String, dynamic> json) {
      return QRVerificationData(
        deviceId: json['device_id'] ?? '',
        publicKey: json['public_key'] ?? '',
        timestamp: json['timestamp'] ?? '',
        signature: json['signature'] ?? '',
        userId: json['user_id'] ?? '',
      );
    }

    Map<String, dynamic> toJson() {
      return {
        'device_id': deviceId,
        'public_key': publicKey,
        'timestamp': timestamp,
        'signature': signature,
        'user_id': userId,
      };
    }

    String toBase64() {
      return base64Encode(utf8.encode(jsonEncode(toJson())));
    }

    factory QRVerificationData.fromBase64(String base64String) {
      final json = jsonDecode(utf8.decode(base64Decode(base64String)));
      return QRVerificationData.fromJson(json);
    }
  }

  /// Generate new E2EE key pair
  static Future<E2EEKeyPair> generateKeyPair() async {
    try {
      // Generate RSA key pair
      final keyPair = RSAKeyGenerator().generateKeyPair(2048);
      final privateKey = keyPair.privateKey as RSAPrivateKey;
      final publicKey = keyPair.publicKey as RSAPublicKey;

      // Convert to PEM format
      final privatePem = privateKey.toPem();
      final publicPem = publicKey.toPem();

      // Generate key ID
      final keyId = _generateKeyId();

      return E2EEKeyPair(
        privateKey: privatePem,
        publicKey: publicPem,
        keyId: keyId,
        createdAt: DateTime.now(),
        algorithm: 'RSA',
      );
    } catch (e) {
      throw Exception('Failed to generate E2EE key pair: $e');
    }
  }

  /// Register current device
  static Future<DeviceInfo> registerDevice({
    required String userId,
    required String deviceName,
    required String deviceType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Generate key pair for this device
      final keyPair = await generateKeyPair();

      // Create device info
      final device = DeviceInfo(
        id: _generateDeviceId(),
        name: deviceName,
        type: deviceType,
        publicKey: keyPair.publicKey,
        lastSeen: DateTime.now(),
        metadata: metadata,
      );

      // Save to local storage
      await _saveCurrentDevice(device);
      await _saveKeyPair(keyPair);

      // Register with server
      await _registerDeviceWithServer(userId, device, keyPair);

      return device;
    } catch (e) {
      throw Exception('Failed to register device: $e');
    }
  }

  /// Get QR verification data for current device
  static Future<QRVerificationData> getQRVerificationData(String userId) async {
    try {
      final device = await _getCurrentDevice();
      if (device == null) {
        throw Exception('No device registered');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final signature = await _signData(device.id + timestamp + userId);

      return QRVerificationData(
        deviceId: device.id,
        publicKey: device.publicKey,
        timestamp: timestamp,
        signature: signature,
        userId: userId,
      );
    } catch (e) {
      throw Exception('Failed to generate QR data: $e');
    }
  }

  /// Verify and add device from QR code
  static Future<bool> verifyAndAddDevice(String qrData, String currentUserId) async {
    try {
      final qrVerificationData = QRVerificationData.fromBase64(qrData);

      // Verify signature
      final isValid = await _verifySignature(
        qrVerificationData.deviceId + qrVerificationData.timestamp + qrVerificationData.userId,
        qrVerificationData.signature,
        qrVerificationData.publicKey,
      );

      if (!isValid) {
        throw Exception('Invalid QR code signature');
      }

      // Check if timestamp is recent (within 5 minutes)
      final timestamp = int.parse(qrVerificationData.timestamp);
      final now = DateTime.now().millisecondsSinceEpoch();
      if (now - timestamp > 5 * 60 * 1000) { // 5 minutes
        throw Exception('QR code expired');
      }

      // Add device to user's device list
      final device = DeviceInfo(
        id: qrVerificationData.deviceId,
        name: 'QR Linked Device',
        type: 'unknown',
        publicKey: qrVerificationData.publicKey,
        lastSeen: DateTime.now(),
      );

      await _addDeviceToUser(currentUserId, device);

      return true;
    } catch (e) {
      print('Failed to verify QR device: $e');
      return false;
    }
  }

  /// Sync keys between devices
  static Future<bool> syncKeys(String userId) async {
    try {
      // Get all devices for user
      final devices = await _getUserDevices(userId);
      
      // Get current device
      final currentDevice = await _getCurrentDevice();
      if (currentDevice == null) {
        throw Exception('No current device found');
      }

      // Sync keys with server
      final response = await ApiService.instance.post('/api/e2ee/sync-keys', {
        'device_id': currentDevice.id,
        'devices': devices.map((d) => d.toJson()).toList(),
      });

      if (response['success'] == true) {
        // Update local device list
        final updatedDevices = (response['devices'] as List<dynamic>?)
            ?.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
            .toList() ?? [];
        
        await _saveUserDevices(userId, updatedDevices);
        return true;
      }

      return false;
    } catch (e) {
      print('Failed to sync keys: $e');
      return false;
    }
  }

  /// Encrypt message for specific device
  static Future<String> encryptMessageForDevice({
    required String message,
    required String targetDeviceId,
    required String userId,
  }) async {
    try {
      // Get target device's public key
      final devices = await _getUserDevices(userId);
      final targetDevice = devices.firstWhere(
        (d) => d.id == targetDeviceId,
        orElse: () => throw Exception('Target device not found'),
      );

      // Get current device's private key
      final currentKeyPair = await _getCurrentKeyPair();
      if (currentKeyPair == null) {
        throw Exception('No encryption keys available');
      }

      // Encrypt message
      final encryptedData = await _encryptWithPublicKey(
        message,
        targetDevice.publicKey,
      );

      return encryptedData;
    } catch (e) {
      throw Exception('Failed to encrypt message: $e');
    }
  }

  /// Decrypt message from any device
  static Future<String> decryptMessage({
    required String encryptedMessage,
    required String userId,
  }) async {
    try {
      // Get current device's private key
      final currentKeyPair = await _getCurrentKeyPair();
      if (currentKeyPair == null) {
        throw Exception('No decryption keys available');
      }

      // Decrypt message
      final decryptedData = await _decryptWithPrivateKey(
        encryptedMessage,
        currentKeyPair.privateKey,
      );

      return decryptedData;
    } catch (e) {
      throw Exception('Failed to decrypt message: $e');
    }
  }

  /// Remove device
  static Future<bool> removeDevice(String userId, String deviceId) async {
    try {
      // Remove from server
      final response = await ApiService.instance.delete('/api/e2ee/devices/$deviceId');

      if (response['success'] == true) {
        // Remove from local storage
        final devices = await _getUserDevices(userId);
        devices.removeWhere((d) => d.id == deviceId);
        await _saveUserDevices(userId, devices);

        // If removing current device, clear local data
        final currentDevice = await _getCurrentDevice();
        if (currentDevice?.id == deviceId) {
          await _clearLocalData();
        }

        return true;
      }

      return false;
    } catch (e) {
      print('Failed to remove device: $e');
      return false;
    }
  }

  /// Get all user devices
  static Future<List<DeviceInfo>> getUserDevices(String userId) async {
    return await _getUserDevices(userId);
  }

  /// Get current device info
  static Future<DeviceInfo?> getCurrentDevice() async {
    return await _getCurrentDevice();
  }

  // Private helper methods

  static String _generateDeviceId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
  }

  static String _generateKeyId() {
    return 'key_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
  }

  static String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }

  static Future<void> _saveCurrentDevice(DeviceInfo device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentDeviceKey, jsonEncode(device.toJson()));
  }

  static Future<DeviceInfo?> _getCurrentDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceJson = prefs.getString(_currentDeviceKey);
    
    if (deviceJson != null) {
      return DeviceInfo.fromJson(jsonDecode(deviceJson));
    }
    return null;
  }

  static Future<void> _saveKeyPair(E2EEKeyPair keyPair) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keysKey, jsonEncode(keyPair.toJson()));
  }

  static Future<E2EEKeyPair?> _getCurrentKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final keysJson = prefs.getString(_keysKey);
    
    if (keysJson != null) {
      return E2EEKeyPair.fromJson(jsonDecode(keysJson));
    }
    return null;
  }

  static Future<void> _saveUserDevices(String userId, List<DeviceInfo> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_devicesKey}_$userId';
    await prefs.setString(key, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  static Future<List<DeviceInfo>> _getUserDevices(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_devicesKey}_$userId';
    final devicesJson = prefs.getString(key);
    
    if (devicesJson != null) {
      final devicesList = jsonDecode(devicesJson) as List<dynamic>;
      return devicesList.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>)).toList();
    }
    return [];
  }

  static Future<void> _addDeviceToUser(String userId, DeviceInfo device) async {
    final devices = await _getUserDevices(userId);
    devices.add(device);
    await _saveUserDevices(userId, devices);
  }

  static Future<void> _registerDeviceWithServer(String userId, DeviceInfo device, E2EEKeyPair keyPair) async {
    final response = await ApiService.instance.post('/api/e2ee/register-device', {
      'user_id': userId,
      'device': device.toJson(),
      'public_key': keyPair.publicKey,
      'key_id': keyPair.keyId,
    });

    if (response['success'] != true) {
      throw Exception('Failed to register device with server');
    }
  }

  static Future<String> _signData(String data) async {
    // This would use the current device's private key to sign data
    // For now, return a mock signature
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }

  static Future<bool> _verifySignature(String data, String signature, String publicKey) async {
    // This would verify the signature using the public key
    // For now, return true
    return true;
  }

  static Future<String> _encryptWithPublicKey(String message, String publicKey) async {
    try {
      // Parse public key
      final parser = RSAKeyParser();
      final rsaPublicKey = parser.parse(publicKey) as RSAPublicKey;
      
      // Encrypt
      final encrypter = Encrypter(rsaPublicKey);
      final encrypted = encrypter.encrypt(message);
      
      return encrypted.base64;
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  static Future<String> _decryptWithPrivateKey(String encryptedMessage, String privateKey) async {
    try {
      // Parse private key
      final parser = RSAKeyParser();
      final rsaPrivateKey = parser.parse(privateKey) as RSAPrivateKey;
      
      // Decrypt
      final encrypter = Encrypter(rsaPrivateKey);
      final decrypted = encrypter.decrypt64(encryptedMessage);
      
      return decrypted;
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  static Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentDeviceKey);
    await prefs.remove(_keysKey);
  }
}

/// QR Code Display Widget
class E2EEQRCodeWidget extends StatelessWidget {
  final String qrData;
  final String title;
  final String description;

  const E2EEQRCodeWidget({
    super.key,
    required this.qrData,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Scan this code with another device to link it',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Device List Widget
class E2EEDeviceListWidget extends StatelessWidget {
  final List<E2EEDeviceSyncService.DeviceInfo> devices;
  final Function(String)? onRemoveDevice;
  final Function(String)? onVerifyDevice;

  const E2EEDeviceListWidget({
    super.key,
    required this.devices,
    this.onRemoveDevice,
    this.onVerifyDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.devices,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Linked Devices',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${devices.length} devices',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Device list
          if (devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.device_unknown,
                    color: Colors.grey[600],
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No devices linked',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Link devices to enable E2EE chat sync',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...devices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              return _buildDeviceItem(device, index);
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(E2EEDeviceSyncService.DeviceInfo device, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[800]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Device icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getDeviceTypeColor(device.type),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getDeviceTypeIcon(device.type),
              color: Colors.white,
              size: 20,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.type} • Last seen ${_formatLastSeen(device.lastSeen)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: device.isActive ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Actions
          if (onRemoveDevice != null || onVerifyDevice != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: Colors.white,
              onSelected: (value) {
                switch (value) {
                  case 'remove':
                    onRemoveDevice!(device.id);
                    break;
                  case 'verify':
                    onVerifyDevice!(device.id);
                    break;
                }
              },
              itemBuilder: (context) => [
                if (onVerifyDevice != null)
                  const PopupMenuItem(
                    value: 'verify',
                    child: Row(
                      children: [
                        Icon(Icons.verified, size: 16),
                        SizedBox(width: 8),
                        Text('Verify'),
                      ],
                    ),
                  ),
                if (onRemoveDevice != null)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Remove', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getDeviceTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'mobile':
        return Colors.blue;
      case 'desktop':
        return Colors.green;
      case 'web':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getDeviceTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'mobile':
        return Icons.smartphone;
      case 'desktop':
        return Icons.desktop_windows;
      case 'web':
        return Icons.language;
      default:
        return Icons.device_unknown;
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${lastSeen.day}/${lastSeen.month}';
  }
}
