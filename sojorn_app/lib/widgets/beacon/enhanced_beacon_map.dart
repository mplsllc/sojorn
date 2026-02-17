import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enhanced_beacon.dart';
import '../../theme/app_theme.dart';

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
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
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

  List<dynamic> get _mapMarkers {
    final filteredBeacons = _filteredBeacons;
    
    if (!widget.enableClustering || _currentZoom >= 15.0) {
      // Show individual beacons
      return filteredBeacons.map((beacon) => _buildBeaconMarker(beacon)).toList();
    } else {
      // Show clusters
      return _buildClusters(filteredBeacons).map((cluster) => _buildClusterMarker(cluster)).toList();
    }
  }

  List<BeaconCluster> _buildClusters(List<EnhancedBeacon> beacons) {
    final clusters = <BeaconCluster>[];
    final processedBeacons = <String>{};
    
    // Simple clustering algorithm based on zoom level
    final clusterRadius = 0.01 * (16.0 - _currentZoom); // Adjust cluster size based on zoom
    
    for (final beacon in beacons) {
      if (processedBeacons.contains(beacon.id)) continue;
      
      final nearbyBeacons = <EnhancedBeacon>[];
      
      for (final otherBeacon in beacons) {
        if (processedBeacons.contains(otherBeacon.id)) continue;
        
        final distance = math.sqrt(
          math.pow(beacon.lat - otherBeacon.lat, 2) +
          math.pow(beacon.lng - otherBeacon.lng, 2)
        );
        
        if (distance <= clusterRadius) {
          nearbyBeacons.add(otherBeacon);
          processedBeacons.add(otherBeacon.id);
        }
      }
      
      if (nearbyBeacons.isNotEmpty) {
        // Calculate cluster center (average of all beacon positions)
        final avgLat = nearbyBeacons.map((b) => b.lat).reduce((a, b) => a + b) / nearbyBeacons.length;
        final avgLng = nearbyBeacons.map((b) => b.lng).reduce((a, b) => a + b) / nearbyBeacons.length;
        
        clusters.add(BeaconCluster(
          beacons: nearbyBeacons,
          lat: avgLat,
          lng: avgLng,
        ));
      }
    }
    
    return clusters;
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

  Marker _buildClusterMarker(BeaconCluster cluster) {
    final dominantCategory = cluster.dominantCategory;
    final priorityBeacon = cluster.priorityBeacon;
    
    return Marker(
      point: LatLng(cluster.lat, cluster.lng),
      width: 50,
      height: 50,
      child: GestureDetector(
        onTap: () => _showClusterDialog(cluster),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Cluster marker
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dominantCategory.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: dominantCategory.color.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    cluster.count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    dominantCategory.icon,
                    color: Colors.white,
                    size: 12,
                  ),
                ],
              ),
            ),
            
            // Official indicator
            if (cluster.hasOfficialSource)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: Colors.white,
                    size: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showClusterDialog(BeaconCluster cluster) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${cluster.count} Beacons Nearby'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView(
            children: cluster.beacons.map((beacon) => ListTile(
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: beacon.category.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  beacon.category.icon,
                  color: Colors.white,
                  size: 16,
                ),
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
              markers: _mapMarkers.cast<Marker>(),
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
        
        // Legend
        Positioned(
          bottom: 16,
          right: 16,
          child: _buildLegend(),
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
