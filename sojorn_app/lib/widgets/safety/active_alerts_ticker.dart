// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/beacon.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// Horizontal scrolling live-tile strip for critical/high geo-alerts.
/// Apple Maps–style: bold type, color-filled cards, minimal metadata.
class ActiveAlertsTicker extends StatelessWidget {
  final List<Beacon> alerts;
  final void Function(Beacon)? onAlertTap;

  const ActiveAlertsTicker({
    super.key,
    required this.alerts,
    this.onAlertTap,
  });

  @override
  Widget build(BuildContext context) {
    // Only critical + high severity active geo-alerts in the strip
    final highPriority = alerts
        .where((a) =>
            a.beaconType.isGeoAlert &&
            a.incidentStatus == BeaconIncidentStatus.active &&
            (a.severity == BeaconSeverity.critical || a.severity == BeaconSeverity.high))
        .toList()
      ..sort((a, b) {
        final sevCmp = b.severity.index.compareTo(a.severity.index);
        if (sevCmp != 0) return sevCmp;
        return b.createdAt.compareTo(a.createdAt);
      });

    final totalActive = alerts
        .where((a) => a.beaconType.isGeoAlert && a.incidentStatus == BeaconIncidentStatus.active)
        .length;

    if (highPriority.isEmpty) {
      // Nothing high-priority — ticker is silent; lower alerts appear in the list below
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SojornColors.destructive.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_rounded, size: 11, color: SojornColors.destructive),
                  const SizedBox(width: 4),
                  Text('PRIORITY',
                    style: TextStyle(
                        color: SojornColors.destructive,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                ]),
              ),
              if (totalActive > highPriority.length) ...[
                const SizedBox(width: 8),
                Text('· +${totalActive - highPriority.length} more below',
                  style: TextStyle(color: AppTheme.textDisabled, fontSize: 11)),
              ],
            ],
          ),
        ),
        // Live-tile carousel
        SizedBox(
          height: 98,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: highPriority.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final alert = highPriority[index];
              return _LiveTile(
                alert: alert,
                onTap: () => onAlertTap?.call(alert),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _LiveTile extends StatefulWidget {
  final Beacon alert;
  final VoidCallback? onTap;
  const _LiveTile({required this.alert, this.onTap});

  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    if (widget.alert.isRecent) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.alert.pinColor;
    final isRecent = widget.alert.isRecent;
    final isCritical = widget.alert.severity == BeaconSeverity.critical;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, child) {
          final glowRadius = isRecent ? 8.0 + _glowAnim.value * 10.0 : 6.0;
          final glowAlpha = isRecent ? 0.20 + _glowAnim.value * 0.18 : 0.10;

          return Container(
            width: 148,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // Color-filled background tinted by severity
              color: color.withValues(alpha: isCritical ? 0.14 : 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: isRecent ? 0.5 + _glowAnim.value * 0.25 : 0.30),
                width: isCritical ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glowAlpha),
                  blurRadius: glowRadius,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + LIVE badge
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: widget.alert.pinColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.alert.beaconType.icon, size: 16, color: widget.alert.pinColor),
                ),
                const Spacer(),
                if (isRecent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: SojornColors.destructive,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Bold type label
            Text(
              widget.alert.beaconType.displayName,
              style: TextStyle(
                color: widget.alert.pinColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // Distance only — ditch the time metadata
            Row(
              children: [
                Icon(Icons.near_me, size: 10, color: AppTheme.navyBlue.withValues(alpha: 0.45)),
                const SizedBox(width: 3),
                Text(widget.alert.getFormattedDistance(),
                  style: TextStyle(
                      color: AppTheme.navyBlue.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
