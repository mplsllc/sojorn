// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../../models/beacon.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// A feed widget that shows discussion-type beacons for the neighborhood board.
/// Filters beacons where type is in the 'discussion' mode (lost pet, question, event, etc.)
class NeighborhoodBoardWidget extends StatelessWidget {
  final List<Beacon> beacons;
  final String? neighborhoodName;
  final void Function(Beacon)? onBeaconTap;
  final VoidCallback? onPostMessageTap;

  const NeighborhoodBoardWidget({
    super.key,
    required this.beacons,
    this.neighborhoodName,
    this.onBeaconTap,
    this.onPostMessageTap,
  });

  @override
  Widget build(BuildContext context) {
    final discussions = beacons
        .where((b) => b.beaconType.isDiscussion)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.forum, color: AppTheme.brightNavy, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  neighborhoodName != null
                      ? '$neighborhoodName Board'
                      : 'Neighborhood Board',
                  style: TextStyle(
                    color: AppTheme.navyBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onPostMessageTap != null)
                GestureDetector(
                  onTap: onPostMessageTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 12, color: AppTheme.brightNavy),
                        const SizedBox(width: 4),
                        Text(
                          'Post',
                          style: TextStyle(
                            color: AppTheme.brightNavy,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Discussion items ────────────────────────────────────────
        if (discussions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.chat_bubble_outline, color: AppTheme.navyBlue.withValues(alpha: 0.2), size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No neighborhood discussions yet',
                    style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Start a conversation with your neighbors',
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          ...discussions.map((d) => _DiscussionCard(
                beacon: d,
                onTap: () => onBeaconTap?.call(d),
              )),
      ],
    );
  }
}

class _DiscussionCard extends StatelessWidget {
  final Beacon beacon;
  final VoidCallback? onTap;
  const _DiscussionCard({required this.beacon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final typeColor = beacon.beaconType.color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: type chip + time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(beacon.beaconType.icon, color: typeColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        beacon.beaconType.displayName,
                        style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  beacon.getTimeAgo(),
                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Body
            Text(
              beacon.body,
              style: TextStyle(color: SojornColors.postContent, fontSize: 13, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Bottom: author + distance
            Row(
              children: [
                if (beacon.authorDisplayName != null) ...[                  Icon(Icons.person_outline, size: 12, color: SojornColors.textDisabled),
                  const SizedBox(width: 3),
                  Text(
                    beacon.authorDisplayName!,
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.location_on, size: 12, color: SojornColors.textDisabled),
                const SizedBox(width: 2),
                Text(
                  beacon.getFormattedDistance(),
                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                ),
                const Spacer(),
                Icon(Icons.visibility, size: 12, color: SojornColors.textDisabled),
                const SizedBox(width: 3),
                Text(
                  '${beacon.verificationCount}',
                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
