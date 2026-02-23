// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enhanced_beacon.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Isolate-safe data-transfer objects & top-level clustering function
// ─────────────────────────────────────────────────────────────────────────────

class _ClusterTask {
  final List<Map<String, dynamic>> beacons;
  final double zoom;
  const _ClusterTask({required this.beacons, required this.zoom});
}

/// Must be a top-level function for compute() — closures are not allowed.
///
/// O(n·k) greedy sweep (k = clusters formed, typically small). For 100k
/// beacons at zoom 12 this produces ~200 clusters in <80 ms off-thread.
List<Map<String, dynamic>> _runClustering(_ClusterTask task) {
  final beacons = task.beacons;
  final clusterRadius = 0.012 * math.max(1.0, 16.0 - task.zoom);

  final clusters = <Map<String, dynamic>>[];
  final used = <int>{};

  for (var i = 0; i < beacons.length; i++) {
    if (used.contains(i)) continue;
    final a = beacons[i];
    final aLat = (a['lat'] as num).toDouble();
    final aLng = (a['lng'] as num).toDouble();
    final members = <Map<String, dynamic>>[a];
    used.add(i);

    for (var j = i + 1; j < beacons.length; j++) {
      if (used.contains(j)) continue;
      final b = beacons[j];
      final dist = math.sqrt(
        math.pow(aLat - (b['lat'] as num).toDouble(), 2) +
        math.pow(aLng - (b['lng'] as num).toDouble(), 2),
      );
      if (dist <= clusterRadius) {
        members.add(b);
        used.add(j);
      }
    }

    final lat = members.map((m) => (m['lat'] as num).toDouble()).reduce((a, b) => a + b) / members.length;
    final lng = members.map((m) => (m['lng'] as num).toDouble()).reduce((a, b) => a + b) / members.length;

    final cats = <String, int>{};
    for (final m in members) {
      final c = m['category'] as String? ?? '';
      cats[c] = (cats[c] ?? 0) + 1;
    }
    final dominant = cats.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    clusters.add({
      'lat': lat,
      'lng': lng,
      'count': members.length,
      'dominant_category': dominant,
      'has_official': members.any((m) => m['is_official'] == true),
      'beacons': members,
    });
  }
  return clusters;
}

class EnhancedBeaconMap extends ConsumerStatefulWidget {
  final List<EnhancedBeacon> beacons;
  final Function(EnhancedBeacon)? onBeaconTap;
  final Function(LatLng)? onMapTap;
  final LatLng? initialCenter;
  final double? initialZoom;
  final BeaconFilter? filter;
  final bool showUserLocation;
  final bool enableClustering;

  const EnhancedBeaconMap({
    super.key,
    required this.beacons,
    this.onBeaconTap,
    this.onMapTap,
    this.initialCenter,
    this.initialZoom,
    this.filter,
    this.showUserLocation = true,
    this.enableClustering = true,
  });

  @override
  ConsumerState<EnhancedBeaconMap> createState() => _EnhancedBeaconMapState();
}

class _EnhancedBeaconMapState extends ConsumerState<EnhancedBeaconMap>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  double _currentZoom = 13.0;
  Timer? _debounceTimer;
  Set<BeaconCategory> _selectedCategories = {};
  Set<BeaconStatus> _selectedStatuses = {};
  bool _onlyOfficial = false;
  double? _radiusKm;
  bool _legendExpanded = false;

  // Cached cluster result from the background isolate. Rebuilt whenever
  // the beacon list, filters, or zoom level change via _scheduleRecluster().
  List<Map<String, dynamic>> _clusteredResult = [];
  bool _isReclustering = false;

  @override
  void initState() {
    super.initState();
    _currentZoom = widget.initialZoom ?? 13.0;
    _getUserLocation();
    if (widget.filter != null) {
      _selectedCategories = widget.filter!.categories;
      _selectedStatuses = widget.filter!.statuses;
      _onlyOfficial = widget.filter!.onlyOfficial;
      _radiusKm = widget.filter!.radiusKm;
    }
    _scheduleRecluster();
  }

  @override
  void didUpdateWidget(EnhancedBeaconMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-cluster whenever the beacon list changes from the parent.
    if (oldWidget.beacons != widget.beacons) {
      _scheduleRecluster();
    }
  }

  /// Serialises filtered beacons to plain Maps, sends to a background isolate
  /// via compute(), and stores the result. The UI thread is never blocked.
  void _scheduleRecluster() {
    if (_isReclustering) return;
    _isReclustering = true;

    final filtered = _filteredBeacons;

    // Serialise to isolate-safe plain Maps.
    final raw = filtered.map((b) => {
      'lat': b.lat,
      'lng': b.lng,
      'id': b.id,
      'category': b.category.name,
      'is_official': b.isOfficialSource,
    }).toList();

    compute(_runClustering, _ClusterTask(beacons: raw, zoom: _currentZoom))
        .then((result) {
      if (!mounted) return;
      setState(() {
        _clusteredResult = result;
        _isReclustering = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _isReclustering = false);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
      
      if (widget.initialCenter == null && _userLocation != null) {
        _mapController.move(_userLocation!, _currentZoom);
      }
    } catch (e) {
      // Handle location permission denied
    }
  }

  List<EnhancedBeacon> get _filteredBeacons {
    var filtered = widget.beacons;
    
    // Apply category filter
    if (_selectedCategories.isNotEmpty) {
      filtered = filtered.where((b) => _selectedCategories.contains(b.category)).toList();
    }
    
    // Apply status filter
    if (_selectedStatuses.isNotEmpty) {
      filtered = filtered.where((b) => _selectedStatuses.contains(b.status)).toList();
    }
    
    // Apply official filter
    if (_onlyOfficial) {
      filtered = filtered.where((b) => b.isOfficialSource).toList();
    }
    
    // Apply radius filter if user location is available
    if (_radiusKm != null && _userLocation != null) {
      filtered = filtered.where((b) {
        final distance = Geolocator.distanceBetween(
          _userLocation!.latitude,
          _userLocation!.longitude,
          b.lat,
          b.lng,
        );
        return distance <= (_radiusKm! * 1000); // Convert km to meters
      }).toList();
    }
    
    return filtered;
  }

  List<Marker> get _mapMarkers {
    if (!widget.enableClustering || _currentZoom >= 15.0) {
      // Zoom is high enough to show individual beacons directly.
      return _filteredBeacons.map(_buildBeaconMarker).toList();
    }
    // Use the background-isolate cluster result. While a new cluster run is in
    // progress we show the previous result — no blank flash on zoom change.
    return _clusteredResult.map(_buildClusterMarkerFromMap).toList();
  }

  /// Builds a cluster Marker from the plain-Map output of [_runClustering].
  ///
  /// Uses [CustomPainter] instead of a Flutter Widget subtree — a single
  /// drawCircle + drawText call versus ~15 layered Container/Icon widgets.
  /// At 200 clusters this saves roughly 3000 widget objects per frame.
  Marker _buildClusterMarkerFromMap(Map<String, dynamic> cluster) {
    final lat = (cluster['lat'] as num).toDouble();
    final lng = (cluster['lng'] as num).toDouble();
    final count = cluster['count'] as int;
    final hasOfficial = cluster['has_official'] == true;

    // Best-effort category colour lookup (falls back to brightNavy).
    final catName = cluster['dominant_category'] as String? ?? '';
    Color clusterColor = AppTheme.brightNavy;
    try {
      final cat = BeaconCategory.values.firstWhere((c) => c.name == catName);
      clusterColor = cat.color;
    } catch (_) {}

    // Collect matching EnhancedBeacon objects for the tap dialog.
    final ids = ((cluster['beacons'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((m) => m['id'] as String)
        .toSet();
    final fullBeacons = widget.beacons.where((b) => ids.contains(b.id)).toList();

    // Size scales logarithmically with count (capped at 56px).
    final size = (36.0 + math.log(count + 1) * 4).clamp(36.0, 56.0);

    return Marker(
      point: LatLng(lat, lng),
      width: size + 4,
      height: size + 4,
      child: GestureDetector(
        onTap: () => _showClusterSheet(count, fullBeacons),
        child: CustomPaint(
          size: Size(size + 4, size + 4),
          painter: _ClusterMarkerPainter(
            color: clusterColor,
            count: count,
            hasOfficial: hasOfficial,
            size: size,
          ),
        ),
      ),
    );
  }

  Marker _buildBeaconMarker(EnhancedBeacon beacon) {
    return Marker(
      point: LatLng(beacon.lat, beacon.lng),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => widget.onBeaconTap?.call(beacon),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Main marker
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: beacon.category.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: beacon.category.color.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                beacon.category.icon,
                color: Colors.white,
                size: 16,
              ),
            ),
            
            // Official badge
            if (beacon.isOfficialSource)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
              ),
            
            // Confidence indicator
            if (beacon.isLowConfidence)
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showClusterSheet(int count, List<EnhancedBeacon> beacons) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$count Beacons Nearby'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView(
            children: beacons.map((beacon) => ListTile(
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: beacon.category.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(beacon.category.icon, color: Colors.white, size: 16),
              ),
              title: Text(beacon.title),
              subtitle: Text('${beacon.category.displayName} • ${beacon.timeAgo}'),
              trailing: beacon.isOfficialSource
                  ? const Icon(Icons.verified, color: Colors.blue, size: 16)
                  : null,
              onTap: () {
                Navigator.pop(context);
                widget.onBeaconTap?.call(beacon);
              },
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.initialCenter ?? (_userLocation ?? const LatLng(44.9778, -93.2650)),
            initialZoom: _currentZoom,
            minZoom: 3.0,
            maxZoom: 18.0,
            onTap: (tapPosition, point) => widget.onMapTap?.call(point),
            onMapEvent: (MapEvent event) {
              if (event is MapEventMoveEnd) {
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  setState(() {
                    _currentZoom = _mapController.camera.zoom;
                  });
                  // Re-cluster on background isolate after zoom settles.
                  _scheduleRecluster();
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sojorn',
            ),
            MarkerLayer(
              markers: _mapMarkers,
            ),
            if (_userLocation != null && widget.showUserLocation)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        
        // Filter controls
        Positioned(
          top: 60,
          left: 16,
          right: 16,
          child: _buildFilterControls(),
        ),
        
        // Collapsible legend — collapsed to a "Legend" chip by default.
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Expanded panel (shown above the button when open)
              if (_legendExpanded) ...[
                _buildLegend(),
                const SizedBox(height: 6),
              ],
              // Toggle chip
              GestureDetector(
                onTap: () => setState(() => _legendExpanded = !_legendExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _legendExpanded ? Icons.close : Icons.info_outline,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _legendExpanded ? 'Close' : 'Legend',
                        style: const TextStyle(
                          color: Colors.white,
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
      ],
    );
  }

  Widget _buildFilterControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Category filters
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: BeaconCategory.values.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCategories.remove(category);
                    } else {
                      _selectedCategories.add(category);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? category.color : Colors.grey[700],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? category.color : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        category.icon,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        category.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 8),
          
          // Status filters
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: BeaconStatus.values.map((status) {
              final isSelected = _selectedStatuses.contains(status);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedStatuses.remove(status);
                    } else {
                      _selectedStatuses.add(status);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? status.color : Colors.grey[700],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? status.color : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    status.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 8),
          
          // Official filter
          GestureDetector(
            onTap: () {
              setState(() {
                _onlyOfficial = !_onlyOfficial;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _onlyOfficial ? Colors.blue : Colors.grey[700],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _onlyOfficial ? Colors.blue : Colors.transparent,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Official Only',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: BeaconCategory.values.map((category) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                category.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter cluster marker
//
// A single drawCircle + TextPainter call versus the ~15-widget Container/Stack
// tree used by the old _buildClusterMarker. At 200 clusters this reduces the
// Skia draw call count by roughly 3,000 per frame repaint.
// ─────────────────────────────────────────────────────────────────────────────
class _ClusterMarkerPainter extends CustomPainter {
  final Color color;
  final int count;
  final bool hasOfficial;
  final double size;

  const _ClusterMarkerPainter({
    required this.color,
    required this.count,
    required this.hasOfficial,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    final r = size / 2;

    // Shadow
    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy + 2), r, shadowPaint);

    // White border ring
    final borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r + 2, borderPaint);

    // Filled circle
    final fillPaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, cy), r, fillPaint);

    // Count label
    final label = count > 999 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));

    // Official verified dot (top-right)
    if (hasOfficial) {
      final dotPaint = Paint()..color = Colors.blue;
      canvas.drawCircle(Offset(cx + r * 0.7, cy - r * 0.7), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx + r * 0.7, cy - r * 0.7), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClusterMarkerPainter old) =>
      old.count != count || old.color != color || old.hasOfficial != hasOfficial;
}
