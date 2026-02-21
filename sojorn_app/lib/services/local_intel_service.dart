// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/local_intel.dart';

/// Service for fetching local environmental intelligence data.
/// Uses OpenMeteo (free, no API key) and Overpass API (OpenStreetMap).
class LocalIntelService {
  static const String _weatherBaseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _airQualityBaseUrl = 'https://air-quality-api.open-meteo.com/v1/air-quality';
  static const String _overpassBaseUrl = 'https://overpass-api.de/api/interpreter';

  /// Fetch current weather conditions
  Future<WeatherConditions?> fetchWeather(double lat, double lng) async {
    try {
      final uri = Uri.parse(_weatherBaseUrl).replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'current': [
          'temperature_2m',
          'weather_code',
          'uv_index',
          'wind_speed_10m',
          'relative_humidity_2m',
          'apparent_temperature',
        ].join(','),
        'temperature_unit': 'fahrenheit',
        'wind_speed_unit': 'mph',
        'timezone': 'auto',
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return WeatherConditions.fromJson(json);
      }
    } catch (e) {
      // Log error but don't crash - return null
    }
    return null;
  }

  /// Fetch air quality and environmental hazards
  Future<EnvironmentalHazards?> fetchAirQuality(double lat, double lng) async {
    try {
      final uri = Uri.parse(_airQualityBaseUrl).replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'current': [
          'us_aqi',
          'pm2_5',
          'pm10',
          'grass_pollen',
          'birch_pollen',
          'olive_pollen',
          'ragweed_pollen',
          'uv_index',
        ].join(','),
        'timezone': 'auto',
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return EnvironmentalHazards.fromJson(json);
      }
    } catch (e) {
      // Log error but don't crash - return null
    }
    return null;
  }

  /// Fetch sunrise/sunset and visibility data
  Future<VisibilityData?> fetchVisibilityData(double lat, double lng) async {
    try {
      final uri = Uri.parse(_weatherBaseUrl).replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'daily': [
          'sunrise',
          'sunset',
          'daylight_duration',
        ].join(','),
        'timezone': 'auto',
        'forecast_days': '1',
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return VisibilityData.fromJson(json);
      }
    } catch (e) {
      // Log error but don't crash - return null
    }
    return null;
  }

  /// Fetch nearby public resources using Overpass API
  /// Searches for libraries, parks, hospitals, police stations, pharmacies, fire stations
  Future<List<PublicResource>> findNearbyResources(
    double lat,
    double lng, {
    double radiusMeters = 2000,
    List<ResourceType>? types,
  }) async {
    try {
      // Build Overpass QL query
      final query = _buildOverpassQuery(lat, lng, radiusMeters, types);

      final response = await http.post(
        Uri.parse(_overpassBaseUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=${Uri.encodeComponent(query)}',
      ).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = json['elements'] as List<dynamic>? ?? [];

        final resources = elements
            .map((e) => PublicResource.fromOverpassElement(
                  e as Map<String, dynamic>,
                  lat,
                  lng,
                ))
            .toList();

        // Sort by distance
        resources.sort((a, b) =>
            (a.distanceMeters ?? double.infinity)
                .compareTo(b.distanceMeters ?? double.infinity));

        return resources;
      }
    } catch (e) {
      // Log error but don't crash - return empty list
    }
    return [];
  }

  /// Build Overpass QL query for nearby amenities
  String _buildOverpassQuery(
    double lat,
    double lng,
    double radius,
    List<ResourceType>? types,
  ) {
    final amenities = <String>[];
    final leisure = <String>[];

    final targetTypes = types ??
        [
          ResourceType.library,
          ResourceType.park,
          ResourceType.hospital,
          ResourceType.police,
          ResourceType.pharmacy,
          ResourceType.fireStation,
        ];

    for (final type in targetTypes) {
      switch (type) {
        case ResourceType.library:
          amenities.add('library');
          break;
        case ResourceType.hospital:
          amenities.add('hospital');
          break;
        case ResourceType.police:
          amenities.add('police');
          break;
        case ResourceType.pharmacy:
          amenities.add('pharmacy');
          break;
        case ResourceType.fireStation:
          amenities.add('fire_station');
          break;
        case ResourceType.park:
          leisure.add('park');
          break;
        case ResourceType.other:
          break;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('[out:json][timeout:15];');
    buffer.writeln('(');

    // Add amenity queries
    for (final amenity in amenities) {
      buffer.writeln('  node["amenity"="$amenity"](around:$radius,$lat,$lng);');
      buffer.writeln('  way["amenity"="$amenity"](around:$radius,$lat,$lng);');
    }

    // Add leisure queries
    for (final l in leisure) {
      buffer.writeln('  node["leisure"="$l"](around:$radius,$lat,$lng);');
      buffer.writeln('  way["leisure"="$l"](around:$radius,$lat,$lng);');
    }

    buffer.writeln(');');
    buffer.writeln('out center tags;');

    return buffer.toString();
  }

  /// Fetch all local intel data at once
  Future<LocalIntelData> fetchAllIntel(double lat, double lng) async {
    // Fetch all data in parallel
    final results = await Future.wait([
      fetchWeather(lat, lng),
      fetchAirQuality(lat, lng),
      fetchVisibilityData(lat, lng),
      findNearbyResources(lat, lng),
    ]);

    return LocalIntelData(
      weather: results[0] as WeatherConditions?,
      hazards: results[1] as EnvironmentalHazards?,
      visibility: results[2] as VisibilityData?,
      resources: results[3] as List<PublicResource>,
      fetchedAt: DateTime.now(),
    );
  }

  /// Fetch only weather-related intel (faster, fewer API calls)
  Future<LocalIntelData> fetchWeatherIntel(double lat, double lng) async {
    final results = await Future.wait([
      fetchWeather(lat, lng),
      fetchVisibilityData(lat, lng),
    ]);

    return LocalIntelData(
      weather: results[0] as WeatherConditions?,
      visibility: results[1] as VisibilityData?,
      fetchedAt: DateTime.now(),
    );
  }

  /// Fetch only hazard-related intel
  Future<LocalIntelData> fetchHazardIntel(double lat, double lng) async {
    final hazards = await fetchAirQuality(lat, lng);
    return LocalIntelData(
      hazards: hazards,
      fetchedAt: DateTime.now(),
    );
  }
}
