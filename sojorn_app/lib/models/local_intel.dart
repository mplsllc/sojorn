// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

// Models for the Local Intel Service (OpenMeteo + Overpass API data)

/// Weather conditions from OpenMeteo API
class WeatherConditions {
  final double temperature;
  final int weatherCode;
  final double uvIndex;
  final double windSpeed;
  final int humidity;
  final double feelsLike;
  final DateTime timestamp;

  WeatherConditions({
    required this.temperature,
    required this.weatherCode,
    required this.uvIndex,
    required this.windSpeed,
    required this.humidity,
    required this.feelsLike,
    required this.timestamp,
  });

  factory WeatherConditions.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    return WeatherConditions(
      temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
      uvIndex: (current['uv_index'] as num?)?.toDouble() ?? 0.0,
      windSpeed: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
      humidity: (current['relative_humidity_2m'] as num?)?.toInt() ?? 0,
      feelsLike: (current['apparent_temperature'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(current['time'] ?? '') ?? DateTime.now(),
    );
  }

  /// Weather code to human-readable description
  String get weatherDescription {
    switch (weatherCode) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 56:
      case 57:
        return 'Freezing drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
      case 73:
      case 75:
        return 'Snowfall';
      case 77:
        return 'Snow grains';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Unknown';
    }
  }

  /// Weather code to icon name
  String get weatherIcon {
    switch (weatherCode) {
      case 0:
        return 'wb_sunny';
      case 1:
      case 2:
        return 'partly_cloudy_day';
      case 3:
        return 'cloud';
      case 45:
      case 48:
        return 'foggy';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return 'rainy';
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return 'ac_unit';
      case 95:
      case 96:
      case 99:
        return 'thunderstorm';
      default:
        return 'cloud';
    }
  }

  /// UV Index risk level
  String get uvRiskLevel {
    if (uvIndex < 3) return 'Low';
    if (uvIndex < 6) return 'Moderate';
    if (uvIndex < 8) return 'High';
    if (uvIndex < 11) return 'Very High';
    return 'Extreme';
  }
}

/// Air quality and environmental hazards from OpenMeteo Air Quality API
class EnvironmentalHazards {
  final int aqi; // US EPA AQI
  final double pm25;
  final double pm10;
  final int grassPollen;
  final int birchPollen;
  final int olivePollen;
  final int ragweedPollen;
  final double uvIndex;
  final DateTime timestamp;

  EnvironmentalHazards({
    required this.aqi,
    required this.pm25,
    required this.pm10,
    required this.grassPollen,
    required this.birchPollen,
    required this.olivePollen,
    required this.ragweedPollen,
    required this.uvIndex,
    required this.timestamp,
  });

  factory EnvironmentalHazards.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    return EnvironmentalHazards(
      aqi: (current['us_aqi'] as num?)?.toInt() ?? 0,
      pm25: (current['pm2_5'] as num?)?.toDouble() ?? 0.0,
      pm10: (current['pm10'] as num?)?.toDouble() ?? 0.0,
      grassPollen: (current['grass_pollen'] as num?)?.toInt() ?? 0,
      birchPollen: (current['birch_pollen'] as num?)?.toInt() ?? 0,
      olivePollen: (current['olive_pollen'] as num?)?.toInt() ?? 0,
      ragweedPollen: (current['ragweed_pollen'] as num?)?.toInt() ?? 0,
      uvIndex: (current['uv_index'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(current['time'] ?? '') ?? DateTime.now(),
    );
  }

  /// AQI to category description
  String get aqiCategory {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  /// Combined pollen level (max of all types)
  int get maxPollenLevel {
    return [grassPollen, birchPollen, olivePollen, ragweedPollen]
        .reduce((a, b) => a > b ? a : b);
  }

  /// Pollen category based on max level
  String get pollenCategory {
    final level = maxPollenLevel;
    if (level < 10) return 'Low';
    if (level < 50) return 'Moderate';
    if (level < 100) return 'High';
    return 'Very High';
  }
}

/// Sun and moon data for visibility planning
class VisibilityData {
  final DateTime sunrise;
  final DateTime sunset;
  final double daylightDuration; // in hours
  final int moonPhase; // 0-7 (new moon to waning crescent)
  final DateTime timestamp;

  VisibilityData({
    required this.sunrise,
    required this.sunset,
    required this.daylightDuration,
    required this.moonPhase,
    required this.timestamp,
  });

  factory VisibilityData.fromJson(Map<String, dynamic> json) {
    final daily = json['daily'] as Map<String, dynamic>? ?? {};
    final sunriseList = daily['sunrise'] as List<dynamic>? ?? [];
    final sunsetList = daily['sunset'] as List<dynamic>? ?? [];
    final daylightList = daily['daylight_duration'] as List<dynamic>? ?? [];

    return VisibilityData(
      sunrise: sunriseList.isNotEmpty
          ? DateTime.tryParse(sunriseList[0] ?? '') ?? DateTime.now()
          : DateTime.now(),
      sunset: sunsetList.isNotEmpty
          ? DateTime.tryParse(sunsetList[0] ?? '') ?? DateTime.now()
          : DateTime.now(),
      daylightDuration: daylightList.isNotEmpty
          ? ((daylightList[0] as num?)?.toDouble() ?? 0.0) / 3600
          : 12.0,
      moonPhase: _calculateMoonPhase(),
      timestamp: DateTime.now(),
    );
  }

  /// Calculate approximate moon phase (0-7)
  static int _calculateMoonPhase() {
    final now = DateTime.now();
    // Known new moon: January 6, 2000
    final knownNewMoon = DateTime(2000, 1, 6);
    final daysSinceNewMoon = now.difference(knownNewMoon).inDays;
    final lunarCycle = 29.53; // days
    final phase = (daysSinceNewMoon % lunarCycle) / lunarCycle;
    return (phase * 8).floor() % 8;
  }

  /// Moon phase name
  String get moonPhaseName {
    switch (moonPhase) {
      case 0:
        return 'New Moon';
      case 1:
        return 'Waxing Crescent';
      case 2:
        return 'First Quarter';
      case 3:
        return 'Waxing Gibbous';
      case 4:
        return 'Full Moon';
      case 5:
        return 'Waning Gibbous';
      case 6:
        return 'Last Quarter';
      case 7:
        return 'Waning Crescent';
      default:
        return 'Unknown';
    }
  }

  /// Moon phase icon (using unicode)
  String get moonPhaseEmoji {
    switch (moonPhase) {
      case 0:
        return '🌑';
      case 1:
        return '🌒';
      case 2:
        return '🌓';
      case 3:
        return '🌔';
      case 4:
        return '🌕';
      case 5:
        return '🌖';
      case 6:
        return '🌗';
      case 7:
        return '🌘';
      default:
        return '🌑';
    }
  }

  /// Whether it's currently daytime
  bool get isDaytime {
    final now = DateTime.now();
    return now.isAfter(sunrise) && now.isBefore(sunset);
  }

  /// Time until sunrise/sunset
  Duration get timeUntilTransition {
    final now = DateTime.now();
    if (isDaytime) {
      return sunset.difference(now);
    } else {
      if (now.isBefore(sunrise)) {
        return sunrise.difference(now);
      } else {
        // After sunset, calculate time to next sunrise (tomorrow)
        return sunrise.add(const Duration(days: 1)).difference(now);
      }
    }
  }
}

/// Public resource from OpenStreetMap Overpass API
class PublicResource {
  final String id;
  final String name;
  final ResourceType type;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;

  PublicResource({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
  });

  factory PublicResource.fromOverpassElement(
    Map<String, dynamic> element,
    double userLat,
    double userLng,
  ) {
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    final lat = (element['lat'] as num?)?.toDouble() ??
        (element['center']?['lat'] as num?)?.toDouble() ??
        0.0;
    final lng = (element['lon'] as num?)?.toDouble() ??
        (element['center']?['lon'] as num?)?.toDouble() ??
        0.0;

    // Calculate distance
    final distance = _calculateDistance(userLat, userLng, lat, lng);

    // Determine type
    ResourceType type = ResourceType.other;
    final amenity = tags['amenity'] as String?;
    final leisure = tags['leisure'] as String?;

    if (amenity == 'library') {
      type = ResourceType.library;
    } else if (amenity == 'hospital') {
      type = ResourceType.hospital;
    } else if (amenity == 'police') {
      type = ResourceType.police;
    } else if (amenity == 'pharmacy') {
      type = ResourceType.pharmacy;
    } else if (amenity == 'fire_station') {
      type = ResourceType.fireStation;
    } else if (leisure == 'park') {
      type = ResourceType.park;
    }

    return PublicResource(
      id: element['id']?.toString() ?? '',
      name: tags['name'] as String? ?? type.displayName,
      type: type,
      latitude: lat,
      longitude: lng,
      distanceMeters: distance,
      address: _buildAddress(tags),
      phone: tags['phone'] as String?,
      website: tags['website'] as String?,
      openingHours: tags['opening_hours'] as String?,
    );
  }

  static String? _buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    if (tags['addr:housenumber'] != null) {
      parts.add(tags['addr:housenumber'].toString());
    }
    if (tags['addr:street'] != null) {
      parts.add(tags['addr:street'].toString());
    }
    if (tags['addr:city'] != null) {
      parts.add(tags['addr:city'].toString());
    }
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  /// Haversine formula for distance calculation
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0; // Earth's radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLon / 2) *
            _sin(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double deg) => deg * 3.141592653589793 / 180;
  static double _sin(double x) => _taylorSin(x);
  static double _cos(double x) => _taylorSin(x + 1.5707963267948966);
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  static double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 1.5707963267948966;
    if (x == 0 && y < 0) return -1.5707963267948966;
    return 0;
  }

  static double _atan(double x) {
    if (x.abs() > 1) {
      return x > 0
          ? 1.5707963267948966 - _atan(1 / x)
          : -1.5707963267948966 - _atan(1 / x);
    }
    double result = 0;
    double term = x;
    for (int i = 1; i <= 15; i += 2) {
      result += term / i;
      term *= -x * x;
    }
    return result;
  }

  static double _taylorSin(double x) {
    // Normalize to [-pi, pi]
    while (x > 3.141592653589793) {
      x -= 6.283185307179586;
    }
    while (x < -3.141592653589793) {
      x += 6.283185307179586;
    }
    double result = 0;
    double term = x;
    for (int i = 1; i <= 15; i += 2) {
      result += term;
      term *= -x * x / ((i + 1) * (i + 2));
    }
    return result;
  }

  /// Formatted distance string in US units
  String get formattedDistance {
    if (distanceMeters == null) return '';
    final miles = distanceMeters! / 1609.344;
    if (miles < 0.1) {
      return '${(distanceMeters! * 3.28084).round()}ft';
    } else if (miles < 10) {
      return '${miles.toStringAsFixed(1)}mi';
    }
    return '${miles.round()}mi';
  }
}

enum ResourceType {
  library,
  park,
  hospital,
  police,
  pharmacy,
  fireStation,
  other,
}

extension ResourceTypeExtension on ResourceType {
  String get displayName {
    switch (this) {
      case ResourceType.library:
        return 'Library';
      case ResourceType.park:
        return 'Park';
      case ResourceType.hospital:
        return 'Hospital';
      case ResourceType.police:
        return 'Police Station';
      case ResourceType.pharmacy:
        return 'Pharmacy';
      case ResourceType.fireStation:
        return 'Fire Station';
      case ResourceType.other:
        return 'Public Resource';
    }
  }

  String get iconName {
    switch (this) {
      case ResourceType.library:
        return 'local_library';
      case ResourceType.park:
        return 'park';
      case ResourceType.hospital:
        return 'local_hospital';
      case ResourceType.police:
        return 'local_police';
      case ResourceType.pharmacy:
        return 'local_pharmacy';
      case ResourceType.fireStation:
        return 'local_fire_department';
      case ResourceType.other:
        return 'place';
    }
  }
}

/// Combined local intel data
class LocalIntelData {
  final WeatherConditions? weather;
  final EnvironmentalHazards? hazards;
  final VisibilityData? visibility;
  final List<PublicResource> resources;
  final DateTime fetchedAt;
  final bool isLoading;
  final String? error;

  LocalIntelData({
    this.weather,
    this.hazards,
    this.visibility,
    this.resources = const [],
    DateTime? fetchedAt,
    this.isLoading = false,
    this.error,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  LocalIntelData copyWith({
    WeatherConditions? weather,
    EnvironmentalHazards? hazards,
    VisibilityData? visibility,
    List<PublicResource>? resources,
    DateTime? fetchedAt,
    bool? isLoading,
    String? error,
  }) {
    return LocalIntelData(
      weather: weather ?? this.weather,
      hazards: hazards ?? this.hazards,
      visibility: visibility ?? this.visibility,
      resources: resources ?? this.resources,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  static LocalIntelData loading() {
    return LocalIntelData(isLoading: true);
  }

  static LocalIntelData withError(String error) {
    return LocalIntelData(error: error);
  }
}
