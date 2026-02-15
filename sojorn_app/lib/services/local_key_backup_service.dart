import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/js.dart' as js;
import 'package:device_info_plus/device_info_plus.dart';
import '../../services/simple_e2ee_service.dart';
import '../../services/local_message_store.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Local key backup service for device-based key storage
/// Saves encrypted keys to device storage with password protection
class LocalKeyBackupService {
  static const String _backupVersion = '1.0';
  static const int _argon2Iterations = 3;
  static const int _argon2MemorySizeKB = 64 * 1024; // 64MB
  static const int _argon2Parallelism = 4;
  static const int _saltLength = 32;
  static const int _keyLength = 32;

  static const _secureStorage = FlutterSecureStorage();

  /// Export all keys to encrypted backup file
  static Future<Map<String, dynamic>> createEncryptedBackup({
    required String password,
    required SimpleE2EEService e2eeService,
    bool includeKeys = true,
    bool includeMessages = true,
  }) async {
    try {
      
      // 1. Export chat E2EE keys (if requested)
      Map<String, dynamic>? keyData;
      if (includeKeys) {
        keyData = await _exportAllKeys(e2eeService);
      }

      // 1a. Export capsule/beacon private keys
      Map<String, dynamic>? capsuleKeyData;
      if (includeKeys) {
        final capsulePriv = await _secureStorage.read(key: 'capsule_private_key');
        final capsulePub = await _secureStorage.read(key: 'capsule_public_key');
        if (capsulePriv != null) {
          capsuleKeyData = {
            'capsule_private_key': capsulePriv,
            'capsule_public_key': capsulePub,
          };
        }
      }

      // 1b. Export messages if requested
      List<Map<String, dynamic>>? messageData;
      if (includeMessages) {
        final messages = await LocalMessageStore.instance.getAllMessageRecords();
        messageData = messages.map((m) => {
          'conversationId': m.conversationId,
          'messageId': m.messageId,
          'plaintext': m.plaintext,
          'senderId': m.senderId,
          'createdAt': m.createdAt.toIso8601String(),
          'messageType': m.messageType,
          'deliveredAt': m.deliveredAt?.toIso8601String(),
          'readAt': m.readAt?.toIso8601String(),
          'expiresAt': m.expiresAt?.toIso8601String(),
        }).toList();
      }

      final payloadData = {
        if (keyData != null) 'keys': keyData,
        if (capsuleKeyData != null) 'capsule_keys': capsuleKeyData,
        if (messageData != null) 'messages': messageData,
      };

      if (payloadData.isEmpty) {
        throw ArgumentError('Backup must include either keys or messages');
      }
      
      // 2. Generate salt for key derivation
      final salt = _generateSalt();
      
      // 3. Derive encryption key from password using Argon2id
      final encryptionKey = await _deriveKeyFromPassword(password, salt);
      
      // 4. Encrypt the key data with AES-256-GCM
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(encryptionKey);
      final nonce = _generateNonce();
      
      final plaintext = utf8.encode(jsonEncode(payloadData));
      final secretBox = await algorithm.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
      );
      
      // 5. Create backup bundle
      final backup = {
        'version': _backupVersion,
        'created_at': DateTime.now().toIso8601String(),
        'salt': base64.encode(salt),
        'nonce': base64.encode(nonce),
        'ciphertext': base64.encode(secretBox.cipherText),
        'mac': base64.encode(secretBox.mac.bytes),
        'metadata': {
          'app_name': 'Sojorn',
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.toString(),
          'key_count': keyData?['keys']?.length ?? 0,
          'message_count': messageData?.length ?? 0,
        },
      };
      
      return backup;
      
    } catch (e) {
      rethrow;
    }
  }

  /// Restore keys from encrypted backup file
  static Future<Map<String, dynamic>> restoreFromBackup({
    required Map<String, dynamic> backup,
    required String password,
    required SimpleE2EEService e2eeService,
  }) async {
    try {
      
      // 1. Validate backup format
      _validateBackupFormat(backup);
      
      // 2. Extract encryption parameters
      final salt = base64.decode(backup['salt']);
      final nonce = base64.decode(backup['nonce']);
      final ciphertext = base64.decode(backup['ciphertext']);
      final mac = Mac(base64.decode(backup['mac']));
      
      // 3. Derive decryption key from password
      final encryptionKey = await _deriveKeyFromPassword(password, salt);
      
      // 4. Decrypt the backup data
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(encryptionKey);
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
      
      final plaintext = await algorithm.decrypt(secretBox, secretKey: secretKey);
      final payloadData = jsonDecode(utf8.decode(plaintext));
      
      // Handle legacy format (where root is keyData) or new format (where root has 'keys')
      final keyData = payloadData.containsKey('keys') ? payloadData['keys'] : payloadData;
      
      // 5. Import chat E2EE keys (if present)
      if (keyData != null) {
        await _importAllKeys(keyData, e2eeService);
      }

      // 5b. Import capsule/beacon private keys (if present)
      bool capsuleRestored = false;
      if (payloadData is Map && payloadData.containsKey('capsule_keys')) {
        final capsuleKeys = payloadData['capsule_keys'] as Map<String, dynamic>;
        if (capsuleKeys['capsule_private_key'] != null) {
          await _secureStorage.write(
            key: 'capsule_private_key',
            value: capsuleKeys['capsule_private_key'],
          );
          await _secureStorage.write(
            key: 'capsule_public_key',
            value: capsuleKeys['capsule_public_key'],
          );
          capsuleRestored = true;
        }
      }

      // 6. Import messages if present
      int restoredMessages = 0;
      if (payloadData is Map && payloadData.containsKey('messages')) {
        final messages = (payloadData['messages'] as List).cast<Map<String, dynamic>>();
        
        for (final m in messages) {
          await LocalMessageStore.instance.saveMessageRecord(LocalMessageRecord(
            conversationId: m['conversationId'],
            messageId: m['messageId'],
            plaintext: m['plaintext'],
            senderId: m['senderId'],
            createdAt: DateTime.parse(m['createdAt']),
            messageType: m['messageType'],
            deliveredAt: m['deliveredAt'] != null ? DateTime.parse(m['deliveredAt']) : null,
            readAt: m['readAt'] != null ? DateTime.parse(m['readAt']) : null,
            expiresAt: m['expiresAt'] != null ? DateTime.parse(m['expiresAt']) : null,
          ));
        }
        restoredMessages = messages.length;
      }
      
      return {
        'success': true,
        'restored_keys': keyData != null ? (keyData['keys']?.length ?? 0) : 0,
        'restored_capsule_keys': capsuleRestored,
        'restored_messages': restoredMessages,
        'backup_date': backup['created_at'],
      };
      
    } catch (e) {
      if (e is ArgumentError && e.message.contains('MAC')) {
        throw Exception('Invalid password or corrupted backup file');
      }
      rethrow;
    }
  }

  /// Save backup to device file
  static Future<String> saveBackupToDevice(Map<String, dynamic> backup) async {
    try {
      
      // Web implementation - download file
      if (kIsWeb) {
        final backupJson = const JsonEncoder.withIndent('  ').convert(backup);
        final bytes = utf8.encode(backupJson);
        final blob = html.Blob([bytes]);
        
        final fileName = 'sojorn_keys_backup_${DateTime.now().millisecondsSinceEpoch}.json';
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        // Create download link and trigger download
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..setAttribute('style', 'display:none');
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        
        return fileName;
      }
      
      // Desktop/Mobile implementation
      // Request storage permission (Android only)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Storage permission required');
        }
      }
      
      // Let user choose save location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Key Backup',
        fileName: 'sojorn_keys_backup_${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (result == null) {
        throw Exception('Save cancelled by user');
      }
      
      // Write backup to file
      final file = File(result);
      final backupJson = const JsonEncoder.withIndent('  ').convert(backup);
      await file.writeAsString(backupJson);
      
      return file.path;
      
    } catch (e) {
      rethrow;
    }
  }

  /// Load backup from device file
  static Future<Map<String, dynamic>> loadBackupFromDevice() async {
    try {
      
      // Web implementation - file upload
      if (kIsWeb) {
        final input = html.FileUploadInputElement();
        input.accept = '.json,application/json';
        input.style.display = 'none';
        html.document.body?.children.add(input);
        
        // Create a completer to handle the file selection
        final completer = Completer<Map<String, dynamic>>();
        
        input.onChange.listen((_) {
          // Use the input element directly; the event target is only EventTarget?
          final files = input.files;
          if (files != null && files.isNotEmpty) {
            final file = files.first;
            final reader = html.FileReader();

            reader.onLoad.listen((_) {
              final content = reader.result;
              if (content is String) {
                try {
                  final backup = jsonDecode(content) as Map<String, dynamic>;
                  completer.complete(backup);
                } catch (e) {
                  completer.completeError('Invalid backup file format');
                }
              } else {
                completer.completeError('Failed to read file');
              }
            });

            reader.onError.listen((_) {
              completer.completeError('Failed to read file');
            });

            reader.readAsText(file);
          } else {
            completer.completeError('No file selected');
          }
        });
        
        // Trigger file picker
        input.click();
        
        // Remove input from DOM after selection
        html.document.body?.children.remove(input);
        
        // Wait for file to be processed
        final backup = await completer.future;
        return backup;
      }
      
      // Desktop/Mobile implementation
      // Request storage permission (Android only)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Storage permission required');
        }
      }
      
      // Let user choose backup file
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Key Backup File',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (result == null || result.files.isEmpty) {
        throw Exception('No file selected');
      }
      
      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;
      
      return backup;
      
    } catch (e) {
      rethrow;
    }
  }

  /// Export all keys from E2EE service
  static Future<Map<String, dynamic>> _exportAllKeys(SimpleE2EEService e2eeService) async {
    return await e2eeService.exportAllKeys();
  }

  /// Import all keys to E2EE service
  static Future<void> _importAllKeys(Map<String, dynamic> keyData, SimpleE2EEService e2eeService) async {
    await e2eeService.importAllKeys(keyData);
  }

  /// Generate random salt
  static Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(_saltLength, (_) => random.nextInt(256)));
  }

  /// Generate random nonce
  static Uint8List _generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => random.nextInt(256))); // 96 bits for GCM
  }

  /// Derive key from password using PBKDF2
  static Future<Uint8List> _deriveKeyFromPassword(String password, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    
    // The password serves as the input SecretKey
    final secretKeyInput = SecretKey(utf8.encode(password));
    
    // Derive new key using password as secretKey and salt as nonce
    final derivedKey = await pbkdf2.deriveKey(
      secretKey: secretKeyInput,
      nonce: salt,
    );
    
    return Uint8List.fromList(await derivedKey.extractBytes());
  }

  /// Validate backup format
  static void _validateBackupFormat(Map<String, dynamic> backup) {
    final required = ['version', 'created_at', 'salt', 'nonce', 'ciphertext', 'mac'];
    for (final field in required) {
      if (!backup.containsKey(field)) {
        throw ArgumentError('Invalid backup format: missing $field');
      }
    }
    
    if (backup['version'] != _backupVersion) {
      // Allow 1 if our current is 1.0 (lazy float check)
      if (backup['version'].toString().startsWith('1')) return;
      throw ArgumentError('Unsupported backup version: ${backup['version']}');
    }
  }

  /// Upload encrypted backup to cloud
  static Future<void> uploadToCloud({
    required Map<String, dynamic> backup,
  }) async {
    
    // Get device name
    String deviceName = 'Unknown Device';
    if (!kIsWeb) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
      }
    } else {
      deviceName = 'Web Browser';
    }

    await ApiService.instance.uploadBackup(
      encryptedBlob: backup['ciphertext'],
      salt: backup['salt'],
      nonce: backup['nonce'],
      mac: backup['mac'],
      deviceName: deviceName,
      version: 1, // Currently hardcoded version
    );
  }

  /// Restore from cloud backup
  static Future<Map<String, dynamic>> restoreFromCloud({
    required String password,
    required SimpleE2EEService e2eeService,
    String? backupId,
  }) async {
    final backupData = await ApiService.instance.downloadBackup(backupId);
    
    if (backupData == null) {
      throw Exception('No backup found');
    }

    // Reconstruct the backup map format expected by restoreFromBackup
    final backup = {
      'version': backupData['version'].toString(), // Go sends int, we might need string
      'created_at': backupData['created_at'],
      'salt': backupData['salt'],
      'nonce': backupData['nonce'],
      'ciphertext': backupData['encrypted_blob'], // Go sends encrypted_blob
      'mac': backupData['mac'],
      'metadata': {
        'device_name': backupData['device_name'],
      }
    };
    
    // Fix version type mismatch if needed (our constant is '1.0', Go might send 1)
    if (backup['version'] == '1') backup['version'] = '1.0';

    return await restoreFromBackup(
      backup: backup,
      password: password,
      e2eeService: e2eeService,
    );
  }
}

/// Screen for managing local key backups
class LocalBackupScreen extends StatefulWidget {
  const LocalBackupScreen({super.key});

  @override
  State<LocalBackupScreen> createState() => _LocalBackupScreenState();
}

class _LocalBackupScreenState extends State<LocalBackupScreen> {
  final SimpleE2EEService _e2eeService = SimpleE2EEService();
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  bool _includeMessages = true;
  bool _includeKeys = true;
  bool _useCloud = false; // Toggle for Cloud vs Local
  String? _lastBackupPath;
  DateTime? _lastBackupDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBg,
        elevation: 0,
        surfaceTintColor: SojornColors.transparent,
        title: Text(
          'Full Backup & Recovery',
          style: GoogleFonts.literata(
            fontWeight: FontWeight.w600,
            color: AppTheme.navyBlue,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildModeToggle(),
            const SizedBox(height: 24),
            _buildCreateBackupSection(),
            const SizedBox(height: 24),
            _buildRestoreBackupSection(),
            const SizedBox(height: 24),
            if (_lastBackupPath != null) _buildLastBackupInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _buildModeButton(title: 'Local File', isCloud: false),
          _buildModeButton(title: 'Cloud Backup', isCloud: true),
        ],
      ),
    );
  }

  Widget _buildModeButton({required String title, required bool isCloud}) {
    final isSelected = _useCloud == isCloud;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _useCloud = isCloud;
          // Security Default: Don't send keys to cloud, do save keys locally
          _includeKeys = !isCloud;
          // UX Default: Always include messages for cloud (that's the point)
          if (isCloud) _includeMessages = true;
        }),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.brightNavy : SojornColors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: isSelected ? SojornColors.basicWhite : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.brightNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.brightNavy.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.brightNavy),
              const SizedBox(width: 8),
              Text(
                _useCloud ? 'Encrypted Cloud Backup' : 'Local Key Backup',
                style: GoogleFonts.literata(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brightNavy,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _useCloud 
            ? 'Your messages are encrypted with your password and stored safely on our secure servers. '
              'We never store your encryption keys on the server. You MUST have a local backup of your keys to restore these messages.'
            : 'Your encryption keys and message history are saved locally on this device. '
              'Keep this file safe! It is the only way to restore your identity.',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateBackupSection() {
    return Card(
      color: AppTheme.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.backup, color: AppTheme.brightNavy),
                const SizedBox(width: 8),
                Text(
                  _useCloud ? 'Upload to Cloud' : 'Create Backup',
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _useCloud 
                ? 'Encrypt and upload your message history to the cloud.' 
                : 'Export your keys and messages to a password-protected backup file.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Include Message History',
                style: GoogleFonts.inter(
                  color: AppTheme.navyBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Backup all your secure conversations',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textDisabled),
              ),
              value: _includeMessages, 
              onChanged: (v) => setState(() => _includeMessages = v),
              activeColor: AppTheme.brightNavy,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Include Encryption Keys',
                style: GoogleFonts.inter(
                  color: _useCloud ? AppTheme.error : AppTheme.navyBlue, // Warn if cloud
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _useCloud 
                  ? 'NOT RECOMMENDED for cloud backups. Keep keys local.' 
                  : 'Required to restore your identity on a new device',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textDisabled),
              ),
              value: _includeKeys, 
              onChanged: (v) => setState(() => _includeKeys = v),
              activeColor: _useCloud ? SojornColors.destructive : AppTheme.brightNavy,
            ),
            if (_useCloud && !_includeKeys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.security, size: 16, color: const Color(0xFF4CAF50)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Secure Mode: Zero Knowledge. Server cannot decrypt.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4CAF50)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreatingBackup ? null : (_useCloud ? _createCloudBackup : _createBackup),
                icon: _isCreatingBackup
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(SojornColors.basicWhite),
                        ),
                      )
                    : Icon(_useCloud ? Icons.cloud_upload : Icons.file_download),
                label: Text(_isCreatingBackup ? 'Processing...' : (_useCloud ? 'Upload Backup' : 'Export Backup')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreBackupSection() {
    return Card(
      color: AppTheme.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restore, color: AppTheme.brightNavy),
                const SizedBox(width: 8),
                Text(
                  _useCloud ? 'Download & Restore' : 'Restore Backup',
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _useCloud 
                ? 'Download and decrypt the latest backup from the cloud.'
                : 'Import your encryption keys from a backup file.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRestoringBackup ? null : (_useCloud ? _restoreCloudBackup : _restoreBackup),
                icon: _isRestoringBackup
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(SojornColors.basicWhite),
                        ),
                      )
                    : Icon(_useCloud ? Icons.cloud_download : Icons.file_upload),
                label: Text(_isRestoringBackup ? 'Restoring...' : (_useCloud ? 'Download & Restore' : 'Import Backup')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalPurple,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastBackupInfo() {
    return Card(
      color: AppTheme.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: AppTheme.brightNavy),
                const SizedBox(width: 8),
                Text(
                  'Last Backup',
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${_lastBackupDate != null ? _formatDate(_lastBackupDate!) : 'Unknown'}',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            Text(
              'Location: $_lastBackupPath',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCloudBackup() async {
     try {
      setState(() => _isCreatingBackup = true);
      
      final password = await _showPasswordDialog('Encrypt Cloud Backup');
      if (password == null) return;
      
      final backup = await LocalKeyBackupService.createEncryptedBackup(
        password: password,
        e2eeService: _e2eeService,
        includeMessages: _includeMessages,
        includeKeys: _includeKeys, // Default false for cloud
      );
      
      await LocalKeyBackupService.uploadToCloud(backup: backup);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup uploaded securely!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: SojornColors.destructive,
          ),
        );
      }
    } finally {
      setState(() => _isCreatingBackup = false);
    }
  }

  Future<void> _restoreCloudBackup() async {
    try {
      setState(() => _isRestoringBackup = true);
      
      final password = await _showPasswordDialog('Decrypt Cloud Backup');
      if (password == null) return;
      
      final result = await LocalKeyBackupService.restoreFromCloud(
        password: password,
        e2eeService: _e2eeService,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup restored! ${result['restored_keys']} keys, ${result['restored_messages']} messages.'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: SojornColors.destructive,
          ),
        );
      }
    } finally {
      setState(() => _isRestoringBackup = false);
    }
  }

  Future<void> _createBackup() async {
    try {
      setState(() => _isCreatingBackup = true);
      
      // Show password dialog
      final password = await _showPasswordDialog('Create Backup Password');
      if (password == null) return;
      
      // Create backup
      final backup = await LocalKeyBackupService.createEncryptedBackup(
        password: password,
        e2eeService: _e2eeService,
        includeMessages: _includeMessages,
        includeKeys: _includeKeys, // Should be true for local
      );
      
      // Save to device
      final path = await LocalKeyBackupService.saveBackupToDevice(backup);
      
      setState(() {
        _lastBackupPath = path;
        _lastBackupDate = DateTime.now();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved successfully!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create backup: $e'),
            backgroundColor: SojornColors.destructive,
          ),
        );
      }
    } finally {
      setState(() => _isCreatingBackup = false);
    }
  }

  Future<void> _restoreBackup() async {
    try {
      setState(() => _isRestoringBackup = true);
      
      // Load backup from device
      final backup = await LocalKeyBackupService.loadBackupFromDevice();
      
      // Show password dialog
      final password = await _showPasswordDialog('Enter Backup Password');
      if (password == null) return;
      
      // Restore backup
      final result = await LocalKeyBackupService.restoreFromBackup(
        backup: backup,
        password: password,
        e2eeService: _e2eeService,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup restored successfully! ${result['restored_keys']} keys and ${result['restored_messages']} messages recovered.'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore backup: $e'),
            backgroundColor: SojornColors.destructive,
          ),
        );
      }
    } finally {
      setState(() => _isRestoringBackup = false);
    }
  }

  Future<String?> _showPasswordDialog(String title) async {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Please enter a strong password to protect your backup.',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                hintText: 'Enter a strong password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
