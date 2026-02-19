import 'package:flutter/material.dart';
import '../../models/beacon.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// Horizontal scrolling list of high-priority geo-alert beacons.
/// Compact, high-contrast cards with pulse animation for recent alerts.
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
    // High priority ticker: critical + high severity geo-alerts only
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

    // All active geo-alerts count for badge
    final totalActive = alerts
        .where((a) => a.beaconType.isGeoAlert && a.incidentStatus == BeaconIncidentStatus.active)
        .length;

    if (highPriority.isEmpty) {
      // No high-priority alerts — show compact all-clear or just total count
      if (totalActive == 0) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield, size: 16, color: const Color(0xFF4CAF50)),
              ),
              const SizedBox(width: 10),
              Text('All clear — no active alerts nearby',
                style: TextStyle(color: const Color(0xFF4CAF50), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }
      // Only medium/low alerts — don't show ticker, let the list handle it
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SojornColors.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_rounded, size: 12, color: SojornColors.destructive),
                  const SizedBox(width: 4),
                  Text('HIGH PRIORITY',
                    style: TextStyle(color: SojornColors.destructive, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ]),
              ),
              const SizedBox(width: 8),
              if (totalActive > highPriority.length)
                Text('+${totalActive - highPriority.length} more',
                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
            ],
          ),
        ),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: highPriority.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final alert = highPriority[index];
              return _AlertCard(
                alert: alert,
                onTap: () => onAlertTap?.call(alert),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _AlertCard extends StatefulWidget {
  final Beacon alert;
  final VoidCallback? onTap;
  const _AlertCard({required this.alert, this.onTap});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.alert.isRecent) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.alert.pinColor;
    final isRecent = widget.alert.isRecent;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final glowAlpha = isRecent ? 0.15 + (_pulseAnim.value * 0.15) : 0.0;
          return Container(
            width: 160,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRecent
                    ? color.withValues(alpha: 0.4 + (_pulseAnim.value * 0.3))
                    : AppTheme.navyBlue.withValues(alpha: 0.08),
                width: isRecent ? 1.5 : 1,
              ),
              boxShadow: isRecent
                  ? [BoxShadow(color: color.withValues(alpha: glowAlpha), blurRadius: 12)]
                  : null,
            ),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top row: icon + type + live badge
            Row(
              children: [
                Icon(widget.alert.beaconType.icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.alert.beaconType.displayName,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRecent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: SojornColors.destructive.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('LIVE', style: TextStyle(color: SojornColors.destructive, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            // Body preview
            Text(
              widget.alert.body,
              style: TextStyle(color: SojornColors.postContentLight, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Bottom: time + distance
            Row(
              children: [
                Icon(Icons.schedule, size: 10, color: SojornColors.textDisabled),
                const SizedBox(width: 3),
                Text(widget.alert.getTimeAgo(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                const Spacer(),
                Icon(Icons.location_on, size: 10, color: SojornColors.textDisabled),
                const SizedBox(width: 2),
                Text(widget.alert.getFormattedDistance(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
