// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class BlockingService {
  static const String _blockedUsersKey = 'blocked_users';
  static const String _blockedUsersJsonKey = 'blocked_users_json';
  static const String _blockedUsersCsvKey = 'blocked_users_csv';

  /// Export blocked users to JSON file
  static Future<bool> exportBlockedUsersToJson(List<String> blockedUserIds) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/blocked_users_${DateTime.now().millisecondsSinceEpoch}.json');
      
      final exportData = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '2.0',
        'platform': 'sojorn',
        'total_blocked': blockedUserIds.length,
        'blocked_users': blockedUserIds.map((id) => {
          'user_id': id,
          'blocked_at': DateTime.now().toIso8601String(),
        }).toList(),
      };

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(exportData));
      
      // Share the file
      final result = await Share.shareXFiles([XFile(file.path)]);
      return result.status == ShareResultStatus.success;
    } catch (e) {
      print('Error exporting blocked users to JSON: $e');
      return false;
    }
  }

  /// Export blocked users to CSV file
  static Future<bool> exportBlockedUsersToCsv(List<String> blockedUserIds) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/blocked_users_${DateTime.now().millisecondsSinceEpoch}.csv');
      
      final csvContent = StringBuffer();
      csvContent.writeln('user_id,blocked_at');
      
      for (final userId in blockedUserIds) {
        csvContent.writeln('$userId,${DateTime.now().toIso8601String()}');
      }
      
      await file.writeAsString(csvContent.toString());
      
      // Share the file
      final result = await Share.shareXFiles([XFile(file.path)]);
      return result.status == ShareResultStatus.success;
    } catch (e) {
      print('Error exporting blocked users to CSV: $e');
      return false;
    }
  }

  /// Import blocked users from JSON file
  static Future<List<String>> importBlockedUsersFromJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        if (data['blocked_users'] != null) {
          final blockedUsers = (data['blocked_users'] as List<dynamic>)
              .map((user) => user['user_id'] as String)
              .toList();
          
          return blockedUsers;
        }
      }
    } catch (e) {
      print('Error importing blocked users from JSON: $e');
    }
    return [];
  }

  /// Import blocked users from CSV file
  static Future<List<String>> importBlockedUsersFromCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final lines = await file.readAsLines();
        
        if (lines.isNotEmpty) {
          // Skip header line
          final blockedUsers = lines.skip(1)
              .where((line) => line.isNotEmpty)
              .map((line) => line.split(',')[0].trim())
              .toList();
          
          return blockedUsers;
        }
      }
    } catch (e) {
      print('Error importing blocked users from CSV: $e');
    }
    return [];
  }

  /// Import from Twitter/X format
  static Future<List<String>> importFromTwitterX() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final lines = await file.readAsLines();
        
        if (lines.isNotEmpty) {
          // Twitter/X CSV format: screen_name, name, description, following, followers, tweets, account_created_at
          final blockedUsers = lines.skip(1)
              .where((line) => line.isNotEmpty)
              .map((line) => line.split(',')[0].trim()) // screen_name
              .toList();
          
          return blockedUsers;
        }
      }
    } catch (e) {
      print('Error importing from Twitter/X: $e');
    }
    return [];
  }

  /// Import from Mastodon format
  static Future<List<String>> importFromMastodon() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final lines = await file.readAsLines();
        
        if (lines.isNotEmpty) {
          // Mastodon CSV format: account_id, username, display_name, domain, note, created_at
          final blockedUsers = lines.skip(1)
              .where((line) => line.isNotEmpty)
              .map((line) => line.split(',')[1].trim()) // username
              .toList();
          
          return blockedUsers;
        }
      }
    } catch (e) {
      print('Error importing from Mastodon: $e');
    }
    return [];
  }

  /// Get supported platform formats
  static List<PlatformFormat> getSupportedFormats() {
    return [
      PlatformFormat(
        name: 'Sojorn JSON',
        description: 'Native Sojorn format with full metadata',
        extension: 'json',
        importFunction: importBlockedUsersFromJson,
        exportFunction: exportBlockedUsersToJson,
      ),
      PlatformFormat(
        name: 'CSV',
        description: 'Universal CSV format',
        extension: 'csv',
        importFunction: importBlockedUsersFromCsv,
        exportFunction: exportBlockedUsersToCsv,
      ),
      PlatformFormat(
        name: 'Twitter/X',
        description: 'Twitter/X export format',
        extension: 'csv',
        importFunction: importFromTwitterX,
        exportFunction: null, // Export not supported for Twitter/X
      ),
      PlatformFormat(
        name: 'Mastodon',
        description: 'Mastodon export format',
        extension: 'csv',
        importFunction: importFromMastodon,
        exportFunction: null, // Export not supported for Mastodon
      ),
    ];
  }

  /// Validate blocked users list
  static Future<List<String>> validateBlockedUsers(List<String> blockedUserIds) async {
    final validUsers = <String>[];
    
    for (final userId in blockedUserIds) {
      if (userId.isNotEmpty && userId.length <= 50) { // Basic validation
        validUsers.add(userId);
      }
    }
    
    return validUsers;
  }

  /// Get import/export statistics
  static Map<String, dynamic> getStatistics(List<String> blockedUserIds) {
    return {
      'total_blocked': blockedUserIds.length,
      'export_formats_available': getSupportedFormats().length,
      'last_updated': DateTime.now().toIso8601String(),
      'platforms_supported': ['Twitter/X', 'Mendation', 'CSV', 'JSON'],
    };
  }
}

class PlatformFormat {
  final String name;
  final String description;
  final String extension;
  final Future<List<String>> Function()? importFunction;
  final Future<bool>? Function(List<String>)? exportFunction;

  PlatformFormat({
    required this.name,
    required this.description,
    required this.extension,
    this.importFunction,
    this.exportFunction,
  });
}

class BlockManagementScreen extends StatefulWidget {
  const BlockManagementScreen({super.key});

  @override
  State<BlockManagementScreen> createState() => _BlockManagementScreenState();
}

class _BlockManagementScreenState extends State<BlockManagementScreen> {
  List<String> _blockedUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // This would typically come from your API service
      // For now, we'll use a placeholder
      final prefs = await SharedPreferences.getInstance();
      final blockedUsersJson = prefs.getString(BlockingService._blockedUsersJsonKey);
      
      if (blockedUsersJson != null) {
        final blockedUsersList = jsonDecode(blockedUsersJson) as List<dynamic>;
        _blockedUsers = blockedUsersList.cast<String>();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load blocked users';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveBlockedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BlockingService._blockedUsersJsonKey, jsonEncode(_blockedUsers));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save blocked users')),
      );
    }
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Block List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose the format of your block list:'),
            const SizedBox(height: 16),
            ...BlockingService.getSupportedFormats().map((format) => ListTile(
              leading: Icon(
                format.importFunction != null ? Icons.file_download : Icons.file_upload,
                color: format.importFunction != null ? Colors.green : AppTheme.textDisabled,
              ),
              title: Text(format.name),
              subtitle: Text(format.description),
              trailing: format.importFunction != null
                  ? Icon(Icons.arrow_forward_ios, color: AppTheme.textDisabled)
                  : null,
              onTap: format.importFunction != null
                  ? () => _importFromFormat(format)
                  : null,
            )).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromFormat(PlatformFormat format) async {
    Navigator.pop(context);
    
    setState(() => _isLoading = true);
    
    try {
      final importedUsers = await format.importFunction!();
      final validatedUsers = await BlockingService.validateBlockedUsers(importedUsers);
      
      setState(() {
        _blockedUsers = {..._blockedUsers, ...validatedUsers}.toList();
      });
      
      await _saveBlockedUsers();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully imported ${validatedUsers.length} users'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Block List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose export format:'),
            const SizedBox(height: 16),
            ...BlockingService.getSupportedFormats().where((format) => format.exportFunction != null).map((format) => ListTile(
              leading: Icon(Icons.file_upload, color: Colors.blue),
              title: Text(format.name),
              subtitle: Text(format.description),
              onTap: () => _exportToFormat(format),
            )).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToFormat(PlatformFormat format) async {
    Navigator.pop(context);
    
    setState(() => _isLoading = true);
    
    try {
      final success = await format.exportFunction!(_blockedUsers);
      
      if (success == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported ${_blockedUsers.length} users'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Export cancelled or failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showBulkBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Block'),
        content: const Text('Enter usernames to block (one per line):'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showBulkBlockInput();
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  void _showBulkBlockInput() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Block'),
        content: TextField(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'user1\nuser2\nuser3',
          ),
          maxLines: 10,
          onChanged: (value) {
            // This would typically validate usernames
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Process bulk block here
            },
            child: const Text('Block Users'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Block Management',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _showImportDialog,
            icon: const Icon(Icons.file_download, color: Colors.white),
            tooltip: 'Import',
          ),
          IconButton(
            onPressed: _showExportDialog,
            icon: const Icon(Icons.file_upload, color: Colors.white),
            tooltip: 'Export',
          ),
          IconButton(
            onPressed: _showBulkBlockDialog,
            icon: const Icon(Icons.group_add, color: Colors.white),
            tooltip: 'Bulk Block',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _errorMessage != null
              ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _blockedUsers.isEmpty
              ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.block,
                    color: AppTheme.textDisabled,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No blocked users',
                    style: TextStyle(
                      color: AppTheme.textDisabled,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import an existing block list or start blocking users',
                    style: TextStyle(
                      color: AppTheme.textDisabled,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Statistics
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistics',
                        style: TextStyle(
                          color: AppTheme.postContent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Blocked: ${_blockedUsers.length}',
                        style: TextStyle(
                          color: AppTheme.postContent,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last Updated: ${DateTime.now().toIso8601String()}',
                        style: TextStyle(
                          color: AppTheme.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Blocked users list
                Expanded(
                  child: ListView.builder(
                    itemCount: _blockedUsers.length,
                    itemBuilder: (context, index) {
                      final userId = _blockedUsers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.surfaceElevated,
                          child: Icon(
                            Icons.person,
                            color: AppTheme.postContent,
                          ),
                        ),
                        title: Text(
                          userId,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _blockedUsers.removeAt(index);
                            });
                            _saveBlockedUsers();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
