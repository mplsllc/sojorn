// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../../models/local_intel.dart';
import '../../../theme/app_theme.dart';

/// Base card widget for intel display
class IntelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final bool isLoading;
  final VoidCallback? onTap;

  const IntelCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.egyptianBlue.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.navyBlue,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card 1: Weather Conditions
class ConditionsCard extends StatelessWidget {
  final WeatherConditions? weather;
  final bool isLoading;

  const ConditionsCard({
    super.key,
    this.weather,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntelCard(
      title: 'Conditions',
      icon: Icons.thermostat,
      iconColor: AppTheme.brightNavy,
      isLoading: isLoading,
      child: weather == null
          ? _buildNoData(context)
          : _buildContent(context, weather!),
    );
  }

  Widget _buildNoData(BuildContext context) {
    return Center(
      child: Text(
        'No data',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textDisabled,
            ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WeatherConditions weather) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${weather.temperature.round()}°F',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
            ),
            const Spacer(),
            Icon(
              _getWeatherIcon(weather.weatherCode),
              size: 28,
              color: AppTheme.egyptianBlue,
            ),
          ],
        ),
        Text(
          weather.weatherDescription,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textDisabled,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Spacer(),
        _buildUvIndicator(context, weather.uvIndex),
      ],
    );
  }

  Widget _buildUvIndicator(BuildContext context, double uvIndex) {
    final color = _getUvColor(uvIndex);
    return Row(
      children: [
        Icon(Icons.wb_sunny_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          'UV ${uvIndex.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getUvLevel(uvIndex),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
          ),
        ),
      ],
    );
  }

  IconData _getWeatherIcon(int code) {
    switch (code) {
      case 0:
        return Icons.wb_sunny;
      case 1:
      case 2:
        return Icons.cloud_queue;
      case 3:
        return Icons.cloud;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
      case 61:
      case 63:
      case 65:
      case 80:
      case 81:
      case 82:
        return Icons.water_drop;
      case 71:
      case 73:
      case 75:
      case 85:
      case 86:
        return Icons.ac_unit;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm;
      default:
        return Icons.cloud;
    }
  }

  Color _getUvColor(double uv) {
    if (uv < 3) return const Color(0xFF4CAF50);
    if (uv < 6) return const Color(0xFFFF9800);
    if (uv < 8) return const Color(0xFFFF5722);
    if (uv < 11) return const Color(0xFFF44336);
    return const Color(0xFF9C27B0);
  }

  String _getUvLevel(double uv) {
    if (uv < 3) return 'LOW';
    if (uv < 6) return 'MOD';
    if (uv < 8) return 'HIGH';
    if (uv < 11) return 'V.HIGH';
    return 'EXTREME';
  }
}

/// Card 2: Environmental Hazards (AQI, Pollen)
class HazardsCard extends StatelessWidget {
  final EnvironmentalHazards? hazards;
  final bool isLoading;

  const HazardsCard({
    super.key,
    this.hazards,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntelCard(
      title: 'Hazards',
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFFF9800),
      isLoading: isLoading,
      child: hazards == null
          ? _buildNoData(context)
          : _buildContent(context, hazards!),
    );
  }

  Widget _buildNoData(BuildContext context) {
    return Center(
      child: Text(
        'No data',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textDisabled,
            ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, EnvironmentalHazards hazards) {
    final aqiColor = _getAqiColor(hazards.aqi);
    final pollenColor = _getPollenColor(hazards.maxPollenLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AQI Row
        Row(
          children: [
            Icon(Icons.air, size: 16, color: aqiColor),
            const SizedBox(width: 6),
            Text(
              'AQI',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: aqiColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${hazards.aqi}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: aqiColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hazards.aqiCategory,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: aqiColor,
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        // Pollen Row
        Row(
          children: [
            Icon(Icons.grass, size: 16, color: pollenColor),
            const SizedBox(width: 6),
            Text(
              'Pollen',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            ),
            const Spacer(),
            Text(
              hazards.pollenCategory,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: pollenColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getAqiColor(int aqi) {
    if (aqi <= 50) return const Color(0xFF4CAF50);
    if (aqi <= 100) return const Color(0xFFF9A825);
    if (aqi <= 150) return const Color(0xFFFF9800);
    if (aqi <= 200) return const Color(0xFFF44336);
    if (aqi <= 300) return const Color(0xFF9C27B0);
    return const Color(0xFF795548);
  }

  Color _getPollenColor(int level) {
    if (level < 10) return const Color(0xFF4CAF50);
    if (level < 50) return const Color(0xFFF9A825);
    if (level < 100) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}

/// Card 3: Visibility (Sun/Moon)
class VisibilityCard extends StatelessWidget {
  final VisibilityData? visibility;
  final bool isLoading;

  const VisibilityCard({
    super.key,
    this.visibility,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntelCard(
      title: 'Visibility',
      icon: Icons.nights_stay_outlined,
      iconColor: AppTheme.ksuPurple,
      isLoading: isLoading,
      child: visibility == null
          ? _buildNoData(context)
          : _buildContent(context, visibility!),
    );
  }

  Widget _buildNoData(BuildContext context) {
    return Center(
      child: Text(
        'No data',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textDisabled,
            ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, VisibilityData visibility) {
    final isDaytime = visibility.isDaytime;
    final transition = visibility.timeUntilTransition;
    final transitionText = _formatDuration(transition);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sun times
        Row(
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 14,
              color: const Color(0xFFFF9800),
            ),
            const SizedBox(width: 4),
            Text(
              _formatTime(visibility.sunrise),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            ),
            const Spacer(),
            Icon(
              Icons.nightlight_outlined,
              size: 14,
              color: AppTheme.ksuPurple,
            ),
            const SizedBox(width: 4),
            Text(
              _formatTime(visibility.sunset),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Transition countdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (isDaytime ? const Color(0xFFFF9800) : AppTheme.ksuPurple)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDaytime ? Icons.wb_twilight : Icons.sunny,
                size: 14,
                color: isDaytime ? const Color(0xFFFF9800) : AppTheme.ksuPurple,
              ),
              const SizedBox(width: 4),
              Text(
                '${isDaytime ? 'Sunset' : 'Sunrise'} in $transitionText',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDaytime ? const Color(0xFFFF9800) : AppTheme.ksuPurple,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Moon phase
        Row(
          children: [
            Icon(
              _moonPhaseIcon(visibility.moonPhase),
              size: 18,
              color: AppTheme.navyBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                visibility.moonPhaseName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textDisabled,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _moonPhaseIcon(int phase) {
    switch (phase) {
      case 0:
        return Icons.brightness_3; // new moon
      case 1:
      case 2:
        return Icons.brightness_3; // waxing crescent/first quarter
      case 3:
        return Icons.brightness_2; // waxing gibbous
      case 4:
        return Icons.brightness_1; // full moon
      case 5:
        return Icons.brightness_2; // waning gibbous
      case 6:
      case 7:
        return Icons.brightness_3; // last quarter/waning crescent
      default:
        return Icons.nightlight_round;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// Card 4: Public Resources
class ResourcesCard extends StatelessWidget {
  final int resourceCount;
  final bool isLoading;
  final VoidCallback? onTap;

  const ResourcesCard({
    super.key,
    required this.resourceCount,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IntelCard(
      title: 'Resources',
      icon: Icons.place_outlined,
      iconColor: const Color(0xFF009688),
      isLoading: isLoading,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resourceCount > 0 ? '$resourceCount' : '—',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navyBlue,
                ),
          ),
          Text(
            'Public services nearby',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textDisabled,
                ),
          ),
          const Spacer(),
          Row(
            children: [
              _buildResourceIcon(Icons.local_library, const Color(0xFF2196F3)),
              const SizedBox(width: 6),
              _buildResourceIcon(Icons.park, const Color(0xFF4CAF50)),
              const SizedBox(width: 6),
              _buildResourceIcon(Icons.local_hospital, const Color(0xFFF44336)),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppTheme.egyptianBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResourceIcon(IconData icon, Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
