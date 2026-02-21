// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board_entry.dart';
import '../../providers/api_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/composer/composer_bar.dart';

/// Compose sheet for the standalone neighborhood board.
/// Creates board_entries — completely separate from posts/beacons.
class CreateBoardPostSheet extends ConsumerStatefulWidget {
  final double centerLat;
  final double centerLong;
  final Function(BoardEntry entry) onEntryCreated;

  const CreateBoardPostSheet({
    super.key,
    required this.centerLat,
    required this.centerLong,
    required this.onEntryCreated,
  });

  @override
  ConsumerState<CreateBoardPostSheet> createState() => _CreateBoardPostSheetState();
}

class _CreateBoardPostSheetState extends ConsumerState<CreateBoardPostSheet> {
  BoardTopic _selectedTopic = BoardTopic.community;

  static const _topics = BoardTopic.values;

  Future<void> _onComposerSend(String text, String? imageUrl) async {
    final apiService = ref.read(apiServiceProvider);
    final data = await apiService.createBoardEntry(
      body: text,
      imageUrl: imageUrl,
      topic: _selectedTopic.value,
      lat: widget.centerLat,
      long: widget.centerLong,
    );
    if (mounted) {
      final entry = BoardEntry.fromJson(data['entry'] as Map<String, dynamic>);
      widget.onEntryCreated(entry);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20, right: 20, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Icon(Icons.forum, color: AppTheme.brightNavy, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Post to Board', style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: SojornColors.textDisabled),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Topic grid — 4 columns × 2 rows
            Text('Topic', style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: _topics.map((topic) {
                final isSelected = topic == _selectedTopic;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTopic = topic),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected ? topic.color.withValues(alpha: 0.12) : AppTheme.scaffoldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? topic.color : AppTheme.navyBlue.withValues(alpha: 0.1),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(topic.icon, size: 22, color: isSelected ? topic.color : SojornColors.postContentLight),
                        const SizedBox(height: 4),
                        Text(
                          topic.displayName,
                          style: TextStyle(
                            color: isSelected ? topic.color : SojornColors.postContentLight,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Composer (text + photo + send)
            ComposerBar(
              config: const ComposerConfig(
                allowImages: true,
                hintText: 'Share with your neighborhood…',
              ),
              onSend: _onComposerSend,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
