// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../models/feed_filter.dart';
import '../theme/app_theme.dart';

/// Filter button for feed screens with popup menu
class FeedFilterButton extends StatelessWidget {
  final FeedFilter currentFilter;
  final ValueChanged<FeedFilter> onFilterChanged;

  const FeedFilterButton({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FeedFilter>(
      icon: Icon(
        Icons.filter_list,
        color: currentFilter != FeedFilter.all ? AppTheme.navyBlue : null,
      ),
      initialValue: currentFilter,
      onSelected: onFilterChanged,
      tooltip: 'Filter posts',
      itemBuilder: (context) => [
        _buildMenuItem(FeedFilter.all, Icons.apps),
        _buildMenuItem(FeedFilter.posts, Icons.article_outlined),
        _buildMenuItem(FeedFilter.quips, Icons.play_circle_outline),
        _buildMenuItem(FeedFilter.chains, Icons.forum_outlined),
        _buildMenuItem(FeedFilter.beacons, Icons.sensors),
      ],
    );
  }

  PopupMenuItem<FeedFilter> _buildMenuItem(FeedFilter filter, IconData icon) {
    return PopupMenuItem(
      value: filter,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(filter.label),
          if (filter == currentFilter) ...[
            const Spacer(),
            Icon(Icons.check, size: 18, color: AppTheme.navyBlue),
          ],
        ],
      ),
    );
  }
}
