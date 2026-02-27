// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/board_entry.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';

/// Resources screen for a neighborhood — shows board entries
/// filtered to the "resource" and "recommendation" topics.
class NeighborhoodResourcesScreen extends StatefulWidget {
  final String neighborhoodName;
  final double lat;
  final double lng;

  const NeighborhoodResourcesScreen({
    super.key,
    required this.neighborhoodName,
    required this.lat,
    required this.lng,
  });

  @override
  State<NeighborhoodResourcesScreen> createState() =>
      _NeighborhoodResourcesScreenState();
}

class _NeighborhoodResourcesScreenState
    extends State<NeighborhoodResourcesScreen> {
  List<BoardEntry> _entries = [];
  bool _loading = true;
  BoardTopic _selectedTopic = BoardTopic.resource;

  static const _resourceTopics = [
    BoardTopic.resource,
    BoardTopic.recommendation,
  ];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      final raw = await ApiService.instance.fetchBoardEntries(
        lat: widget.lat,
        long: widget.lng,
        topic: _selectedTopic.value,
        sort: 'new',
      );
      _entries = (raw['entries'] as List?)
              ?.map((e) => BoardEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      debugPrint('[NeighborhoodResources] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.neighborhoodName} Resources'),
        backgroundColor: AppTheme.cardSurface,
        foregroundColor: AppTheme.navyText,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Topic filter chips
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SojornSpacing.md, vertical: SojornSpacing.sm),
            child: Row(
              children: _resourceTopics.map((topic) {
                final isSelected = _selectedTopic == topic;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(topic.icon,
                            size: 14,
                            color:
                                isSelected ? Colors.white : topic.color),
                        const SizedBox(width: 6),
                        Text(topic.displayName),
                      ],
                    ),
                    selectedColor: topic.color,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : topic.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    backgroundColor: topic.color.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SojornRadii.full),
                    ),
                    onSelected: (_) {
                      setState(() => _selectedTopic = topic);
                      _loadEntries();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Entries list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadEntries,
                    child: _entries.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(_selectedTopic.icon,
                                        size: 48,
                                        color:
                                            AppTheme.textDisabled),
                                    const SizedBox(height: 12),
                                    Text(
                                        'No ${_selectedTopic.displayName.toLowerCase()}s yet',
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                          color:
                                              AppTheme.textDisabled,
                                        )),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Share helpful ${_selectedTopic.displayName.toLowerCase()}s with your neighborhood',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              AppTheme.textDisabled,
                                        )),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.all(SojornSpacing.md),
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              return _ResourceCard(entry: _entries[i]);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Resource Card ───────────────────────────────────────────────────────────

class _ResourceCard extends StatelessWidget {
  final BoardEntry entry;

  const _ResourceCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SojornRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(SojornSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Row(
              children: [
                SojornAvatar(
                  displayName: entry.authorDisplayName.isNotEmpty
                      ? entry.authorDisplayName
                      : entry.authorHandle,
                  avatarUrl: entry.authorAvatarUrl.isNotEmpty
                      ? entry.authorAvatarUrl
                      : null,
                  size: 36,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.authorDisplayName.isNotEmpty
                            ? entry.authorDisplayName
                            : entry.authorHandle,
                        style: TextStyle(
                            color: AppTheme.navyBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      Text('@${entry.authorHandle}',
                          style: TextStyle(
                              color: AppTheme.textDisabled,
                              fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: entry.topic.color.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(SojornRadii.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(entry.topic.icon,
                          size: 12, color: entry.topic.color),
                      const SizedBox(width: 4),
                      Text(entry.topic.displayName,
                          style: TextStyle(
                              color: entry.topic.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Body
            Text(
              entry.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.postContent,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),

            // Upvotes + replies
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.arrow_upward,
                    size: 14, color: AppTheme.textDisabled),
                const SizedBox(width: 2),
                Text('${entry.upvotes}',
                    style: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 12)),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: AppTheme.textDisabled),
                const SizedBox(width: 2),
                Text('${entry.replyCount}',
                    style: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 12)),
                const Spacer(),
                Text(entry.getTimeAgo(),
                    style: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
