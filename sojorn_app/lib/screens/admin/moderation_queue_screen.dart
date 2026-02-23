// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../widgets/media/signed_media_image.dart';
import '../../providers/api_provider.dart';
import '../../theme/tokens.dart';

class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  ConsumerState<ModerationQueueScreen> createState() =>
      _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<ModerationQueueItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(apiServiceProvider).callGoApi(
            '/admin/moderation',
            method: 'GET',
          );
      if (mounted) {
        setState(() {
          _items = [];
          _errorMessage =
              'Moderation queue is unavailable (Go API migration pending).';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Moderation queue is unavailable (Go API migration pending).';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateStatus(
    ModerationQueueItem item,
    String moderationStatus, {
    bool banUser = false,
  }) async {
    setState(() => _errorMessage =
        'Moderation actions are unavailable (Go API migration pending).');
  }

  Future<void> _confirmBan(ModerationQueueItem item) async {
    final shouldBan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ban user?'),
        content: Text(
          'This will reject the post and ban ${item.authorLabel} from sojorn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ban User'),
          ),
        ],
      ),
    );

    if (shouldBan == true) {
      await _updateStatus(item, 'rejected', banUser: true);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'flagged_bigotry':
        return 'Bigotry / Hate';
      case 'flagged_nsfw':
        return 'NSFW';
      case 'flagged':
        return 'Flagged';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation Queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadQueue,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Dashboard',
            onPressed: () => context.go('/admin'),
            icon: const Icon(Icons.insights),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        'Flagged Posts',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_items.length} in queue',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(
                            child: Text(
                              'Queue is clear.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : Card(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Post')),
                                    DataColumn(label: Text('Author')),
                                    DataColumn(label: Text('AI Reason')),
                                    DataColumn(label: Text('Confidence')),
                                    DataColumn(label: Text('Time')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: _items
                                      .map(
                                        (item) => DataRow(
                                          cells: [
                                            DataCell(_PostPreview(item: item)),
                                            DataCell(Text(item.authorLabel)),
                                            DataCell(Text(
                                              _statusLabel(
                                                item.moderationStatus,
                                              ),
                                            )),
                                            DataCell(Text(
                                              item.confidenceLabel,
                                            )),
                                            DataCell(Text(
                                              timeago.format(item.createdAt),
                                            )),
                                            DataCell(
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  OutlinedButton(
                                                    onPressed: () =>
                                                        _updateStatus(
                                                      item,
                                                      'approved',
                                                    ),
                                                    child:
                                                        const Text('Approve'),
                                                  ),
                                                  OutlinedButton(
                                                    onPressed: () =>
                                                        _updateStatus(
                                                      item,
                                                      'rejected',
                                                    ),
                                                    child: const Text('Reject'),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .error,
                                                      foregroundColor:
                                                          SojornColors.basicWhite,
                                                    ),
                                                    onPressed: () =>
                                                        _confirmBan(item),
                                                    child:
                                                        const Text('Ban User'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  final ModerationQueueItem item;

  const _PostPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SignedMediaImage(
                url: item.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: const Color(0x42000000),
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              item.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class ModerationQueueItem {
  final String id;
  final String body;
  final String? imageUrl;
  final String moderationStatus;
  final DateTime createdAt;
  final String authorId;
  final String authorLabel;
  final String? toneLabel;
  final double? cisScore;

  ModerationQueueItem({
    required this.id,
    required this.body,
    required this.imageUrl,
    required this.moderationStatus,
    required this.createdAt,
    required this.authorId,
    required this.authorLabel,
    required this.toneLabel,
    required this.cisScore,
  });

  factory ModerationQueueItem.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final handle = author?['handle'] as String?;
    final displayName = author?['display_name'] as String?;
    final authorLabel = displayName != null && displayName.isNotEmpty
        ? '$displayName (@${handle ?? 'user'})'
        : '@${handle ?? 'user'}';

    return ModerationQueueItem(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      moderationStatus: json['moderation_status'] as String? ?? 'flagged',
      createdAt: DateTime.parse(json['created_at'] as String),
      authorId: author?['id'] as String? ?? '',
      authorLabel: authorLabel,
      toneLabel: json['tone_label'] as String?,
      cisScore: _parseDouble(json['cis_score']),
    );
  }

  String get confidenceLabel {
    final score = cisScore;
    if (score == null) return 'n/a';
    return '${(score * 100).toStringAsFixed(0)}%';
  }

  static double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }
}
