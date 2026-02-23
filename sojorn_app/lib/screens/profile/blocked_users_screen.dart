// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/profile.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media/sojorn_avatar.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  bool _isLoading = true;
  List<Profile> _blockedUsers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.callGoApi('/users/blocked', method: 'GET');
      final List<dynamic> usersJson = response['users'] ?? [];
      
      if (mounted) {
        setState(() {
          _blockedUsers = usersJson.map((j) => Profile.fromJson(j)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unblockUser(Profile user) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.callGoApi('/users/${user.id}/block', method: 'DELETE');
      
      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere((u) => u.id == user.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.handle} unblocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unblock: $e')),
        );
      }
    }
  }

  Future<void> _exportBlockList() async {
    try {
      final List<String> handles = _blockedUsers.map((u) => u.handle ?? '').where((h) => h.isNotEmpty).toList();
      final String jsonStr = jsonEncode({
        'version': 1,
        'type': 'sojorn_block_list',
        'exported_at': DateTime.now().toIso8601String(),
        'handles': handles,
      });

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/sojorn_blocklist.json');
      await file.writeAsString(jsonStr);

      await Share.shareXFiles([XFile(file.path)], text: 'My Sojorn Blocklist');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importBlockList() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final String content = await file.readAsString();
      final data = jsonDecode(content);

      if (data['type'] != 'sojorn_block_list') {
        throw 'Invalid file type';
      }

      final List<dynamic> handles = data['handles'] ?? [];
      int count = 0;
      
      setState(() => _isLoading = true);

      final apiService = ref.read(apiServiceProvider);
      for (final handle in handles) {
        try {
          // Note: In a production app, we'd want a bulk block endpoint.
          // For now, we block individually to reuse existing logic.
          await apiService.callGoApi('/users/block_by_handle', method: 'POST', body: {'handle': handle});
          count++;
        } catch (e) {
        }
      }

      await _loadBlockedUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import complete: Blocked $count users')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Blocked Users',
      actions: [
        IconButton(
          icon: const Icon(Icons.upload_file),
          onPressed: _importBlockList,
          tooltip: 'Import Blocklist',
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: _exportBlockList,
          tooltip: 'Export Blocklist',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.block, size: 64, color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No blocked users',
                            style: AppTheme.textTheme.titleMedium?.copyWith(
                              color: AppTheme.navyText.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      itemCount: _blockedUsers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = _blockedUsers[index];
                        return ListTile(
                          leading: SojornAvatar(
                            displayName: user.displayName ?? user.handle ?? '',
                            avatarUrl: user.avatarUrl,
                            size: 40,
                          ),
                          title: Text(user.displayName ?? user.handle ?? 'User'),
                          subtitle: Text('@${user.handle}'),
                          trailing: OutlinedButton(
                            onPressed: () => _unblockUser(user),
                            child: const Text('Unblock'),
                          ),
                        );
                      },
                    ),
    );
  }
}
