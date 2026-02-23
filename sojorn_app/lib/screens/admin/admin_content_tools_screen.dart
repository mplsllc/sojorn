// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';

class AdminContentToolsScreen extends StatefulWidget {
  const AdminContentToolsScreen({super.key});

  @override
  State<AdminContentToolsScreen> createState() => _AdminContentToolsScreenState();
}

class _AdminContentToolsScreenState extends State<AdminContentToolsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content Tools'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_add), text: 'Create User'),
            Tab(icon: Icon(Icons.upload_file), text: 'Import Content'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CreateUserTab(),
          _ImportContentTab(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Tab 1: Create User
// ──────────────────────────────────────────────

class _CreateUserTab extends StatefulWidget {
  const _CreateUserTab();

  @override
  State<_CreateUserTab> createState() => _CreateUserTabState();
}

class _CreateUserTabState extends State<_CreateUserTab> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String _role = 'user';
  bool _verified = false;
  bool _official = false;
  bool _loading = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _handleCtrl.dispose();
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final resp = await ApiService.instance.callGoApi(
        '/admin/users/create',
        method: 'POST',
        body: {
          'email': _emailCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'handle': _handleCtrl.text.trim().toLowerCase(),
          'display_name': _displayNameCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          'role': _role,
          'verified': _verified,
          'official': _official,
          'skip_email': true,
        },
      );
      setState(() {
        _result = 'User created: ${resp['handle']} (${resp['user_id']})';
        _resultIsError = false;
      });
      _emailCtrl.clear();
      _passwordCtrl.clear();
      _handleCtrl.clear();
      _displayNameCtrl.clear();
      _bioCtrl.clear();
    } catch (e) {
      setState(() {
        _result = e.toString();
        _resultIsError = true;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create New User', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Admin-created accounts are immediately active (no email verification required).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),

            // Email + Password row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Password *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.length < 8) return 'Min 8 chars';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Handle + Display Name row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _handleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Handle *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Bio
            TextFormField(
              controller: _bioCtrl,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.info_outline),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Role + flags
            Row(
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(
                          value: 'moderator', child: Text('Moderator')),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? 'user'),
                  ),
                ),
                const SizedBox(width: 24),
                FilterChip(
                  label: const Text('Verified'),
                  selected: _verified,
                  onSelected: (v) => setState(() => _verified = v),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Official'),
                  selected: _official,
                  onSelected: (v) => setState(() => _official = v),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _createUser,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add),
                label: Text(_loading ? 'Creating...' : 'Create User'),
              ),
            ),

            // Result
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _resultIsError
                      ? SojornColors.destructive.withValues(alpha: 0.15)
                      : const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _resultIsError ? SojornColors.destructive : const Color(0xFF4CAF50),
                    width: 0.5,
                  ),
                ),
                child: SelectableText(
                  _result!,
                  style: TextStyle(
                    color: _resultIsError ? const Color(0xFFE57373) : const Color(0xFF81C784),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Tab 2: Import Content
// ──────────────────────────────────────────────

class _ImportContentTab extends StatefulWidget {
  const _ImportContentTab();

  @override
  State<_ImportContentTab> createState() => _ImportContentTabState();
}

class _ImportContentTabState extends State<_ImportContentTab> {
  final _authorIdCtrl = TextEditingController();
  final _inputCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _contentType = 'post';
  String _inputMode = 'links'; // links or csv
  bool _isNsfw = false;
  String _visibility = 'public';
  bool _loading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _authorIdCtrl.dispose();
    _inputCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _parseItems() {
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty) return [];

    if (_inputMode == 'links') {
      // Plain text: one URL per line
      return raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((url) => <String, dynamic>{
                'body': _bodyCtrl.text.trim(),
                'media_url': url,
                'is_nsfw': _isNsfw,
                'visibility': _visibility,
                'tags': <String>[],
              })
          .toList();
    } else {
      // CSV format: body,media_url,thumbnail_url,tags(semicolon-sep),is_nsfw,visibility
      final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      // Skip header if present
      final startIdx =
          lines.isNotEmpty && lines[0].toLowerCase().contains('body') ? 1 : 0;

      return lines.skip(startIdx).map((line) {
        final cols = _parseCsvLine(line);
        return <String, dynamic>{
          'body': cols.isNotEmpty ? cols[0] : '',
          'media_url': cols.length > 1 ? cols[1] : '',
          'thumbnail_url': cols.length > 2 ? cols[2] : '',
          'tags': cols.length > 3
              ? cols[3].split(';').where((t) => t.isNotEmpty).toList()
              : <String>[],
          'is_nsfw':
              cols.length > 4 ? (cols[4].toLowerCase() == 'true') : _isNsfw,
          'visibility': cols.length > 5 ? cols[5] : _visibility,
        };
      }).toList();
    }
  }

  List<String> _parseCsvLine(String line) {
    // Simple CSV parser respecting quoted fields
    final result = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  Future<void> _importContent() async {
    final authorId = _authorIdCtrl.text.trim();
    if (authorId.isEmpty) {
      setState(() => _result = {'error': 'Author ID is required'});
      return;
    }

    final items = _parseItems();
    if (items.isEmpty) {
      setState(() => _result = {'error': 'No items to import'});
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final resp = await ApiService.instance.callGoApi(
        '/admin/content/import',
        method: 'POST',
        body: {
          'author_id': authorId,
          'content_type': _contentType,
          'items': items,
        },
      );
      setState(() => _result = resp);
    } catch (e) {
      setState(() => _result = {'error': e.toString()});
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import Content', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Import posts, quips, or beacons from direct R2 links or CSV data.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // Author ID + Content Type
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _authorIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Author User ID *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    hintText: 'UUID of the user who owns these posts',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _contentType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'post', child: Text('Post')),
                    DropdownMenuItem(value: 'quip', child: Text('Quip')),
                    DropdownMenuItem(value: 'beacon', child: Text('Beacon')),
                  ],
                  onChanged: (v) =>
                      setState(() => _contentType = v ?? 'post'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Input mode toggle
          Row(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'links',
                    icon: Icon(Icons.link),
                    label: Text('Plain Links'),
                  ),
                  ButtonSegment(
                    value: 'csv',
                    icon: Icon(Icons.table_chart),
                    label: Text('CSV'),
                  ),
                ],
                selected: {_inputMode},
                onSelectionChanged: (v) =>
                    setState(() => _inputMode = v.first),
              ),
              const Spacer(),
              FilterChip(
                label: const Text('NSFW'),
                selected: _isNsfw,
                onSelected: (v) => setState(() => _isNsfw = v),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  value: _visibility,
                  decoration: const InputDecoration(
                    labelText: 'Visibility',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'public', child: Text('Public')),
                    DropdownMenuItem(
                        value: 'followers', child: Text('Followers')),
                    DropdownMenuItem(
                        value: 'private', child: Text('Private')),
                  ],
                  onChanged: (v) =>
                      setState(() => _visibility = v ?? 'public'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Body (for links mode - shared body for all items)
          if (_inputMode == 'links') ...[
            TextFormField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(
                labelText: 'Post Body (shared for all items)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields),
                hintText: 'Optional caption for all imported items',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
          ],

          // Main input
          TextFormField(
            controller: _inputCtrl,
            decoration: InputDecoration(
              labelText: _inputMode == 'links'
                  ? 'Media URLs (one per line)'
                  : 'CSV Data',
              border: const OutlineInputBorder(),
              hintText: _inputMode == 'links'
                  ? 'https://media.sojorn.net/uploads/image1.jpg\nhttps://media.sojorn.net/uploads/video1.mp4'
                  : 'body,media_url,thumbnail_url,tags,is_nsfw,visibility\nHello world,https://...,,,false,public',
              hintMaxLines: 3,
              alignLabelWithHint: true,
            ),
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 8),

          // Preview count
          Builder(builder: (context) {
            final items = _parseItems();
            return Text(
              '${items.length} item(s) detected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: items.isEmpty ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
              ),
            );
          }),
          const SizedBox(height: 16),

          // Import button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _loading ? null : _importContent,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(_loading ? 'Importing...' : 'Import Content'),
            ),
          ),

          // Result
          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final isError = _result!.containsKey('error') && _result!['success'] == null;
    final bgColor = isError
        ? SojornColors.destructive.withValues(alpha: 0.15)
        : const Color(0xFF4CAF50).withValues(alpha: 0.15);
    final borderColor = isError ? SojornColors.destructive : const Color(0xFF4CAF50);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isError)
            SelectableText(
              _result!['error'].toString(),
              style: TextStyle(color: const Color(0xFFE57373), fontSize: 13),
            )
          else ...[
            Text(
              _result!['message'] ?? 'Done',
              style: TextStyle(
                color: const Color(0xFF81C784),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Success: ${_result!['success']}  |  Failures: ${_result!['failures']}',
              style: const TextStyle(fontSize: 13),
            ),
            if (_result!['errors'] != null &&
                (_result!['errors'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Errors:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              ...(_result!['errors'] as List).map((e) => Text(
                    '• $e',
                    style: TextStyle(
                        fontSize: 11, color: const Color(0xFFE57373)),
                  )),
            ],
            if (_result!['created'] != null &&
                (_result!['created'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Post IDs: ',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy all IDs',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: (_result!['created'] as List).join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('IDs copied')),
                      );
                    },
                  ),
                ],
              ),
              ...(_result!['created'] as List).take(10).map((id) =>
                  SelectableText(id.toString(),
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'))),
              if ((_result!['created'] as List).length > 10)
                Text(
                  '... and ${(_result!['created'] as List).length - 10} more',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
