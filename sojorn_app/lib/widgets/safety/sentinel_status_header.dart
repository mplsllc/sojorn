// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/beacon.dart';
import '../../models/local_intel.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// Glassmorphic top bar displaying weather, safety level, and location name.
/// Designed to overlay the map in the Sentinel dashboard.
class SentinelStatusHeader extends StatelessWidget {
  final WeatherConditions? weather;
  final List<Beacon> activeAlerts;
  final String locationName;
  final bool isLoading;
  final VoidCallback? onMyLocationTap;
  final VoidCallback? onRefreshTap;
  final bool embedded;

  const SentinelStatusHeader({
    super.key,
    this.weather,
    this.activeAlerts = const [],
    this.locationName = 'Locating…',
    this.isLoading = false,
    this.onMyLocationTap,
    this.onRefreshTap,
    this.embedded = false,
  });

  // ── Safety level logic ──────────────────────────────────────────────
  _SafetyLevel get _safetyLevel {
    final critical = activeAlerts.where((a) => a.severity == BeaconSeverity.critical).length;
    final high = activeAlerts.where((a) => a.severity == BeaconSeverity.high).length;
    if (critical > 0 || high >= 3) return _SafetyLevel.red;
    if (high > 0 || activeAlerts.length >= 5) return _SafetyLevel.yellow;
    return _SafetyLevel.green;
  }

  @override
  Widget build(BuildContext context) {
    final level = _safetyLevel;
    final topPadding = MediaQuery.of(context).padding.top;

    final content = ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.fromLTRB(12, embedded ? 4 : topPadding + 6, 8, 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.cardSurface.withValues(alpha: 0.95),
                  AppTheme.cardSurface.withValues(alpha: 0.85),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.navyBlue.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Row(
              children: [
                // ── Weather chip ──────────────────────────────────────
                if (weather != null) ...[
                  _WeatherChip(weather: weather!),
                  const SizedBox(width: 10),
                ],

                // ── Safety pill ──────────────────────────────────────
                _SafetyPill(level: level, alertCount: activeAlerts.length),
                const SizedBox(width: 10),

                // ── Location name ────────────────────────────────────────
                Expanded(
                  child: Text(
                    locationName,
                    style: TextStyle(
                      color: AppTheme.navyBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // ── Loading indicator ────────────────────────────────────
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.brightNavy.withValues(alpha: 0.5),
                      ),
                    ),
                  ),

                // ── Action buttons ───────────────────────────────────
                _HeaderButton(
                  icon: Icons.my_location,
                  onTap: onMyLocationTap,
                ),
                _HeaderButton(
                  icon: Icons.refresh,
                  onTap: onRefreshTap,
                ),
              ],
            ),
          ),
        ),
      );

    if (embedded) return content;
    return Positioned(top: 0, left: 0, right: 0, child: content);
  }
}

// ── Weather chip ──────────────────────────────────────────────────────────
class _WeatherChip extends StatelessWidget {
  final WeatherConditions weather;
  const _WeatherChip({required this.weather});

  IconData get _icon {
    final code = weather.weatherCode;
    if (code <= 1) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud;
    if (code <= 49) return Icons.foggy;
    if (code <= 69) return Icons.water_drop;
    if (code <= 79) return Icons.ac_unit;
    if (code <= 99) return Icons.thunderstorm;
    return Icons.cloud;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.navyBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: AppTheme.navyBlue.withValues(alpha: 0.7), size: 16),
          const SizedBox(width: 4),
          Text(
            '${weather.temperature.round()}°',
            style: TextStyle(
              color: AppTheme.navyBlue,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Safety level pill ─────────────────────────────────────────────────────
enum _SafetyLevel {
  green(Color(0xFF4CAF50), 'ALL CLEAR'),
  yellow(Color(0xFFFFC107), 'CAUTION'),
  red(Color(0xFFFF5252), 'ALERT');

  final Color color;
  final String label;
  const _SafetyLevel(this.color, this.label);
}

class _SafetyPill extends StatelessWidget {
  final _SafetyLevel level;
  final int alertCount;
  const _SafetyPill({required this.level, required this.alertCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: level.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: level.color,
              boxShadow: [BoxShadow(color: level.color.withValues(alpha: 0.6), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            alertCount > 0 ? '${level.label} ($alertCount)' : level.label,
            style: TextStyle(
              color: level.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small icon button ─────────────────────────────────────────────────────
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _HeaderButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppTheme.navyBlue.withValues(alpha: 0.7), size: 20),
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.06),
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(36, 36),
      ),
      constraints: const BoxConstraints(),
    );
  }
}
