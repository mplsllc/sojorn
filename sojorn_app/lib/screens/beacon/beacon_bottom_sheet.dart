// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/tokens.dart';

class BeaconBottomSheet extends ConsumerStatefulWidget {
  final Post post;

  const BeaconBottomSheet({super.key, required this.post});

  @override
  ConsumerState<BeaconBottomSheet> createState() => _BeaconBottomSheetState();
}

class _BeaconBottomSheetState extends ConsumerState<BeaconBottomSheet> {
  bool _isVouching = false;
  bool _isReporting = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final beacon = post.toBeacon();
    final severityColor = beacon.pinColor;
    final isRecent = beacon.isRecent;
    final verCount = beacon.verificationCount;
    final isVerified = verCount >= 3;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: SojornColors.basicWhite.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Severity + LIVE badges row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(beacon.severity.icon, size: 14, color: severityColor),
                    const SizedBox(width: 4),
                    Text(beacon.severity.label,
                      style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isRecent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: SojornColors.destructive, borderRadius: BorderRadius.circular(4)),
                  child: const Text('LIVE', style: TextStyle(color: SojornColors.basicWhite, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              const Spacer(),
              // Verification status
              Icon(isVerified ? Icons.verified : Icons.pending,
                color: isVerified ? const Color(0xFF4CAF50) : SojornColors.nsfwWarningIcon, size: 18),
              const SizedBox(width: 4),
              Text('$verCount/3',
                style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.5), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),

          // Beacon type + icon
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(beacon.beaconType.icon, color: severityColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(beacon.beaconType.displayName,
                  style: const TextStyle(color: SojornColors.basicWhite, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Body
          Text(post.body, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.7), fontSize: 14, height: 1.4)),
          const SizedBox(height: 10),

          // Meta
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: SojornColors.basicWhite.withValues(alpha: 0.4)),
              const SizedBox(width: 3),
              Text(beacon.getTimeAgo(), style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.4), fontSize: 11)),
              const SizedBox(width: 12),
              Icon(Icons.location_on, size: 12, color: SojornColors.basicWhite.withValues(alpha: 0.4)),
              const SizedBox(width: 3),
              Text(beacon.getFormattedDistance(), style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.4), fontSize: 11)),
              const SizedBox(width: 12),
              Icon(Icons.radar, size: 12, color: SojornColors.basicWhite.withValues(alpha: 0.4)),
              const SizedBox(width: 3),
              Text('${beacon.radius}m', style: TextStyle(color: SojornColors.basicWhite.withValues(alpha: 0.4), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 18),

          // Action buttons
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isVouching ? null : () => _vouch(post.id),
                    icon: _isVouching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                        : const Icon(Icons.visibility, size: 16),
                    label: Text(_isVouching ? '...' : 'I see this too', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF388E3C),
                      foregroundColor: SojornColors.basicWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _isReporting ? null : () => _report(post.id),
                    icon: _isReporting
                        ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.destructive))
                        : Icon(Icons.flag, size: 16, color: SojornColors.destructive.withValues(alpha: 0.7)),
                    label: Text(_isReporting ? '...' : 'False alarm',
                      style: TextStyle(color: SojornColors.destructive.withValues(alpha: 0.7), fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: SojornColors.destructive.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _vouch(String beaconId) async {
    final apiService = ref.read(apiServiceProvider);
    setState(() => _isVouching = true);
    try {
      await apiService.vouchBeacon(beaconId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for confirming this report.'), backgroundColor: Color(0xFF4CAF50)),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isVouching = false);
    }
  }

  Future<void> _report(String beaconId) async {
    final apiService = ref.read(apiServiceProvider);
    setState(() => _isReporting = true);
    try {
      await apiService.reportBeacon(beaconId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report received. Thanks for keeping the community safe.'), backgroundColor: SojornColors.nsfwWarningIcon),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }
}
