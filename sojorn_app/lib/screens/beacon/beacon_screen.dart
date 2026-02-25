// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../models/post.dart';
import '../../models/beacon.dart';
import '../../models/cluster.dart';
import '../../models/board_entry.dart';
import '../../models/local_intel.dart';
import '../../models/group.dart' as group_models;
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/local_intel_service.dart';
import '../../services/capsule_security_service.dart';
import '../../widgets/safety/active_alerts_ticker.dart';
import 'beacon_detail_screen.dart';
import 'camera_viewer_sheet.dart';
import 'create_beacon_sheet.dart';
import 'create_board_post_sheet.dart';
import 'board_entry_detail_screen.dart';
import '../clusters/group_screen.dart';
import '../clusters/group_chat_tab.dart';
import '../clusters/group_forum_tab.dart';
import '../clusters/group_members_tab.dart';
import '../events/event_detail_screen.dart';
import '../../models/event.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../../config/api_config.dart';

enum BeaconTab { map, board, search, groups }
enum NeighborhoodHubTab { feed, chat, forum, members }

class BeaconScreen extends ConsumerStatefulWidget {
  static final GlobalKey<BeaconScreenState> globalKey = GlobalKey<BeaconScreenState>();

  final LatLng? initialMapCenter;

  BeaconScreen({this.initialMapCenter}) : super(key: globalKey);

  @override
  ConsumerState<BeaconScreen> createState() => BeaconScreenState();
}

class BeaconScreenState extends ConsumerState<BeaconScreen> with TickerProviderStateMixin {
  static const List<BeaconTab> _tabOrder = [
    BeaconTab.map,
    BeaconTab.board,
    BeaconTab.groups,
    BeaconTab.search,
  ];

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final LocalIntelService _intelService = LocalIntelService();
  Timer? _beaconLoadDebounce;
  late final TabController _tabController;

  // Reload throttling — only re-fetch when moved > 2.5 km or data is > 5 min old.
  LatLng? _lastLoadCenter;
  DateTime? _lastLoadTime;
  static const double _reloadThresholdMeters = 2500;
  static const Duration _reloadMaxAge = Duration(minutes: 5);

  List<Post> _allBeaconPosts = []; // unified: all sources combined
  List<Post> _beacons = [];       // user-created beacons (non-official)
  List<Post> _officialPosts = []; // official alerts (MN511, IcedCoffee)
  List<GroupEvent> _mapEvents = []; // public events with coordinates
  List<Beacon> _cameraPosts = []; // cameras (filtered from unified)
  List<Beacon> _signPosts = [];   // signs (filtered from unified)
  List<Beacon> _weatherPosts = []; // weather stations (filtered from unified)
  List<Beacon> _beaconModels = [];
  bool _isLoading = false;
  bool _isLoadingLocation = false;

  late LatLng _mapCenter;
  LatLng? _userLocation;
  String _locationName = 'Locating…';

  bool _locationPermissionGranted = false;
  double _currentZoom = 14.0;
  bool _suppressAutoCenterOnUser = false;

  WeatherConditions? _weather;

  // Sub-menu tab state
  BeaconTab _activeTab = BeaconTab.map;

  // Board entries (standalone — NOT posts)
  List<BoardEntry> _boardEntries = [];
  bool _isLoadingBoard = false;
  bool _isNeighborhoodAdmin = false;
  BoardTopic? _selectedBoardTopic;
  String _boardSort = 'new';
  NeighborhoodHubTab _activeNeighborhoodHubTab = NeighborhoodHubTab.feed;
  int _activeNeighborhoodMemberCount = 0;
  int _chatActivityCount = 0;
  int _forumActivityCount = 0;
  int _activeNowCount = 0;
  bool _isLoadingNeighborhoodHubMeta = false;
  String? _lastNeighborhoodMetaGroupId;

  // Groups / clusters data
  List<Cluster> _clusters = [];
  List<Cluster> _discoverClusters = [];
  bool _isLoadingClusters = false;
  Map<String, String> _encryptedKeys = {};
  GroupCategory? _selectedGroupCategory;

  // Neighborhood detection state
  Map<String, dynamic>? _neighborhood;
  bool _isDetectingNeighborhood = false;
  bool _neighborhoodDetected = false;
  bool _homeNeighborhoodChecked = false;
  bool _canChangeNeighborhood = true;
  String? _nextChangeDate;

  // Sheet size tracking (for toggle button and tap-outside-to-close overlay)
  double _sheetSize = 0.15;

  // Beacon map type filter (hidden = not shown on map/list)
  Set<BeaconType> _hiddenTypes = {};

  // Beacon search state
  final _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchBeacons = [];
  List<Map<String, dynamic>> _searchBoard = [];
  List<Map<String, dynamic>> _searchGroups = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    debugPrint('[BEACON] initState — loading map, beacons, clusters, neighborhood');
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabNames = ['Map', 'Commons', 'Hub', 'Clusters'];
        debugPrint('[BEACON] Tab switched to: ${_tabController.index < tabNames.length ? tabNames[_tabController.index] : _tabController.index}');
        setState(() => _activeTab = _tabOrder[_tabController.index]);
        if (_tabController.index == 1 && _boardEntries.isEmpty) _loadBoardEntries();
      }
    });
    _mapCenter = widget.initialMapCenter ?? const LatLng(44.9778, -93.2650); // Minneapolis default, overridden by neighborhood/GPS
    _suppressAutoCenterOnUser = widget.initialMapCenter != null;
    if (widget.initialMapCenter != null) {
      _loadBeacons(center: widget.initialMapCenter);
    }
    // Check home neighborhood FIRST — it provides map center + pre-loads data.
    // GPS location runs in parallel and refines the position once resolved.
    _checkHomeNeighborhood();
    _checkLocationPermission();
    _loadClusters();
    _loadMapEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetController.addListener(_onSheetSizeChanged);
    });
  }

  void _onSheetSizeChanged() {
    if (mounted && _sheetController.isAttached) {
      setState(() => _sheetSize = _sheetController.size);
    }
  }

  void _collapseSheet() {
    if (_sheetController.isAttached) {
      _sheetController.animateTo(0.15,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetSizeChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _beaconLoadDebounce?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;
    debugPrint('[BEACON] Location permission: $status');
    if (mounted) {
      setState(() => _locationPermissionGranted = status.isGranted);
      if (status.isGranted) {
        await _getCurrentLocation(forceCenter: !_suppressAutoCenterOnUser);
        // Only reload beacons if neighborhood didn't already pre-load them
        // AND no load is currently in-flight (_isLoading covers the race where
        // _checkHomeNeighborhood called _loadBeacons but it hasn't finished yet).
        if (_beacons.isEmpty && _officialPosts.isEmpty && !_isLoading) {
          await _loadBeacons();
        }
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _isLoadingLocation = true);
    try {
      final status = await Permission.location.request();
      setState(() => _locationPermissionGranted = status.isGranted);
      if (status.isGranted) {
        await _getCurrentLocation(forceCenter: !_suppressAutoCenterOnUser);
        await _loadBeacons();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location access is required to show nearby incidents.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _getCurrentLocation({bool forceCenter = false}) async {
    if (!_locationPermissionGranted) return;
    debugPrint('[BEACON] Getting current location...');
    setState(() => _isLoadingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      debugPrint('[BEACON] Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
          if (forceCenter || !_suppressAutoCenterOnUser) {
            _mapController.move(_userLocation!, _currentZoom);
            _suppressAutoCenterOnUser = false;
          }
        });
        // Update map center so board uses real location
        final oldCenter = _mapCenter;
        _mapCenter = _userLocation!;
        // Only refresh board if GPS position is significantly different from
        // the previous center (>500m) to avoid redundant reloads when
        // neighborhood coords already loaded correct data.
        final distMoved = const Distance().as(LengthUnit.Meter, oldCenter, _mapCenter);
        if (distMoved > 500 && (_boardEntries.isNotEmpty || _activeTab == BeaconTab.board)) {
          debugPrint('[BEACON] GPS moved ${distMoved.toInt()}m from previous center — refreshing board');
          _loadBoardEntries();
        }
        // Fetch weather for current location
        _fetchWeather(position.latitude, position.longitude);
        // Only detect neighborhood for first-time users (not yet onboarded)
        if (!_neighborhoodDetected && _homeNeighborhoodChecked) {
          _detectNeighborhood(position.latitude, position.longitude);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _fetchWeather(double lat, double lng) async {
    try {
      final weather = await _intelService.fetchWeather(lat, lng);
      if (mounted) setState(() => _weather = weather);
    } catch (_) {}
  }

  Future<void> _detectNeighborhood(double lat, double lng) async {
    if (_neighborhoodDetected || _isDetectingNeighborhood) return;
    debugPrint('[Beacon] detectNeighborhood lat=${lat.toStringAsFixed(4)} lng=${lng.toStringAsFixed(4)}');
    setState(() => _isDetectingNeighborhood = true);
    try {
      final data = await ApiService.instance.detectNeighborhood(lat: lat, long: lng);
      if (mounted) {
        setState(() {
          _neighborhood = data;
          _neighborhoodDetected = true;
          _isDetectingNeighborhood = false;
        });
        // Update location name with neighborhood
        final hood = data['neighborhood'] as Map<String, dynamic>?;
        if (hood != null) {
          final name = hood['name'] as String? ?? '';
          final city = hood['city'] as String? ?? '';
          debugPrint('[Beacon] neighborhood detected: $name, $city');
          if (name.isNotEmpty) {
            setState(() => _locationName = city.isNotEmpty ? '$name, $city' : name);
          }
        } else {
          debugPrint('[Beacon] neighborhood: none returned for lat=$lat lng=$lng');
        }
        // If user has no home neighborhood yet, show the picker
        if (!_homeNeighborhoodChecked) {
          _homeNeighborhoodChecked = true;
          _maybeShowNeighborhoodPicker();
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Neighborhood] Detect error: $e');
      if (mounted) setState(() => _isDetectingNeighborhood = false);
    }
  }

  /// Check if the user already completed the neighborhood onboarding.
  /// If onboarded: load saved neighborhood, skip GPS detection entirely.
  /// If not onboarded: wait for GPS, then auto-show the picker.
  Future<void> _checkHomeNeighborhood() async {
    debugPrint('[BEACON] Checking home neighborhood...');
    try {
      final mine = await ApiService.instance.getMyNeighborhood();
      if (mine == null || !mounted) return;

      final onboarded = mine['onboarded'] == true;
      final hood = mine['neighborhood'] as Map<String, dynamic>?;
      final canChange = mine['can_change'] as bool? ?? true;
      final nextChange = mine['next_change_allowed_at'] as String?;
      debugPrint('[BEACON] Home neighborhood: onboarded=$onboarded, hood=${hood?['name']}, canChange=$canChange');

      if (onboarded && hood != null) {
        // User already chose a neighborhood — load it and skip GPS detect
        final name = hood['name'] as String? ?? '';
        final city = hood['city'] as String? ?? '';
        // Use neighborhood coords as map center immediately (avoids SF default)
        final hoodLat = (hood['lat'] as num?)?.toDouble();
        final hoodLng = (hood['lng'] as num?)?.toDouble();
        setState(() {
          _neighborhood = mine;
          _neighborhoodDetected = true;
          _homeNeighborhoodChecked = true;
          _canChangeNeighborhood = canChange;
          _nextChangeDate = nextChange;
          if (name.isNotEmpty) {
            _locationName = city.isNotEmpty ? '$name, $city' : name;
          }
          if (hoodLat != null && hoodLng != null) {
            _mapCenter = LatLng(hoodLat, hoodLng);
            debugPrint('[BEACON] Using neighborhood center: ${hoodLat.toStringAsFixed(4)}, ${hoodLng.toStringAsFixed(4)}');
          }
        });
        // Move map to neighborhood center and pre-load data with correct coords
        if (hoodLat != null && hoodLng != null && !_suppressAutoCenterOnUser) {
          try { _mapController.move(_mapCenter, _currentZoom); } catch (_) {}
          _loadBeacons(center: _mapCenter);
        }
        // Pre-load board entries with neighborhood coords so they're ready on tab switch
        _loadBoardEntries();
        return; // Done — no GPS detect needed for neighborhood
      }

      // Not onboarded: wait for GPS location, then show picker
      setState(() => _homeNeighborhoodChecked = true);
      // GPS detection will fire from _getCurrentLocation and trigger the picker
    } catch (_) {
      // Network error — don't block the screen
    }
  }

  /// Show the neighborhood picker if the user hasn't completed onboarding.
  void _maybeShowNeighborhoodPicker() {
    // Check the onboarded flag from the /mine response
    if (_neighborhood != null && _neighborhood!['onboarded'] == true) return;
    // Delay slightly so the screen is fully visible first
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _showNeighborhoodPicker();
    });
  }

  Future<void> _showNeighborhoodPicker({bool isChangeMode = false, String? nextChangeDate}) async {
    final result = await NeighborhoodPickerSheet.show(
      context,
      isChangeMode: isChangeMode,
      nextChangeDate: nextChangeDate,
    );
    if (result != null && mounted) {
      setState(() {
        _neighborhood = result;
        _neighborhoodDetected = true;
      });
      // Update location name
      final hood = result['neighborhood'] as Map<String, dynamic>?;
      if (hood != null) {
        final name = hood['name'] as String? ?? '';
        final city = hood['city'] as String? ?? '';
        if (name.isNotEmpty) {
          setState(() => _locationName = city.isNotEmpty ? '$name, $city' : name);
        }
      }
      // Refresh saved neighborhood state (cooldown, next change date)
      _checkHomeNeighborhood();
      // Reload board for new neighborhood
      _loadBoardEntries();
    }
  }

  Future<void> _loadBeacons({LatLng? center, bool force = false}) async {
    final target = center ?? _userLocation ?? _mapCenter;

    // Skip if we haven't moved far enough and data is still fresh.
    if (!force && _lastLoadCenter != null && _lastLoadTime != null) {
      final age = DateTime.now().difference(_lastLoadTime!);
      final dist = _haversineMeters(_lastLoadCenter!, target);
      if (dist < _reloadThresholdMeters && age < _reloadMaxAge) {
        debugPrint('[Beacon] skip reload — ${dist.round()}m from last load, ${age.inSeconds}s ago');
        return;
      }
    }
    _lastLoadCenter = target;
    _lastLoadTime = DateTime.now();

    debugPrint('[Beacon] loadBeacons lat=${target.latitude.toStringAsFixed(4)} lng=${target.longitude.toStringAsFixed(4)} radius=16000');
    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final allPosts = await apiService.fetchUnifiedBeacons(
        lat: target.latitude,
        long: target.longitude,
        radius: 16000,
      );
      debugPrint('[Beacon] fetched ${allPosts.length} unified beacons');

      // Skip the heavy setState if the beacon set hasn't changed.
      final newIds = allPosts.map((p) => p.id).toSet();
      final oldIds = _allBeaconPosts.map((p) => p.id).toSet();
      if (newIds == oldIds && _allBeaconPosts.isNotEmpty) {
        debugPrint('[Beacon] skip setState — same ${newIds.length} beacons');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (mounted) {
        setState(() {
          _allBeaconPosts = allPosts.where((p) => p.isBeaconPost).toList();

          // Split into sub-lists by beacon_type and official status
          const layerTypes = {BeaconType.camera, BeaconType.sign, BeaconType.weatherStation};
          _beacons = _allBeaconPosts
              .where((p) => p.isOfficial != true && !layerTypes.contains(p.beaconType))
              .toList()
            ..sort((a, b) {
              final aPriority = a.isPriority ?? false;
              final bPriority = b.isPriority ?? false;
              if (aPriority != bPriority) return aPriority ? -1 : 1;
              return (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0);
            });
          _officialPosts = _allBeaconPosts
              .where((p) => p.isOfficial == true && !layerTypes.contains(p.beaconType))
              .toList();
          _cameraPosts = _allBeaconPosts
              .where((p) => p.beaconType == BeaconType.camera)
              .map((p) => p.toBeacon()).toList();
          _signPosts = _allBeaconPosts
              .where((p) => p.beaconType == BeaconType.sign)
              .map((p) => p.toBeacon()).toList();
          _weatherPosts = _allBeaconPosts
              .where((p) => p.beaconType == BeaconType.weatherStation)
              .map((p) => p.toBeacon()).toList();
          _beaconModels = [..._beacons, ..._officialPosts].map((p) => p.toBeacon()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[Beacon] ✗ loadBeacons failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Haversine distance in meters between two LatLng points.
  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Future<void> _loadMapEvents() async {
    try {
      final raw = await ApiService.instance.fetchUpcomingEvents(limit: 50);
      final events = raw
          .map((e) => GroupEvent.fromJson(e))
          .where((e) => e.lat != null && e.long != null)
          .toList();
      if (mounted) setState(() => _mapEvents = events);
    } catch (e) {
      debugPrint('[Beacon] _loadMapEvents failed: $e');
    }
  }

  void _onEventMarkerTap(GroupEvent event) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventDetailScreen(
        groupId: event.groupId,
        eventId: event.id,
        initialEvent: event,
      ),
    ));
  }

  List<Marker> _buildEventMarkers() {
    return _mapEvents.map((event) {
      return Marker(
        key: ValueKey('event:${event.id}'),
        point: LatLng(event.lat!, event.long!),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _onEventMarkerTap(event),
          child: Tooltip(
            message: event.title,
            child: Container(
              decoration: BoxDecoration(
                color: SojornColors.basicRoyalPurple,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: const Icon(Icons.event, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _loadClusters() async {
    debugPrint('[BEACON] Loading clusters...');
    setState(() => _isLoadingClusters = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchMyGroups(),
        ApiService.instance.discoverGroups(),
      ]);
      final groups = results[0];
      final discover = results[1];
      final allClusters = groups.map((g) => Cluster.fromJson(g)).toList();
      final myIds = allClusters.map((c) => c.id).toSet();
      final discoverClusters = discover
          .map((g) => Cluster.fromJson(g))
          .where((c) => !myIds.contains(c.id))
          .toList();
      if (mounted) {
        setState(() {
          _clusters = allClusters;
          _discoverClusters = discoverClusters;
          _encryptedKeys = {
            for (final g in groups)
              if ((g['encrypted_group_key'] as String?)?.isNotEmpty == true)
                g['id'] as String: g['encrypted_group_key'] as String,
          };
          _isLoadingClusters = false;
        });
      }
      debugPrint('[BEACON] Loaded ${_clusters.length} clusters, ${_discoverClusters.length} discover');
    } catch (e) {
      debugPrint('[BEACON] Clusters load error: $e');
      if (mounted) setState(() => _isLoadingClusters = false);
    }
  }

  void _navigateToCluster(Cluster cluster) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupScreen(
        group: cluster,
        encryptedGroupKey: _encryptedKeys[cluster.id],
      ),
    ));
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _mapCenter = camera.center;
    _currentZoom = camera.zoom;
    if (hasGesture) {
      _beaconLoadDebounce?.cancel();
      _beaconLoadDebounce = Timer(const Duration(milliseconds: 600), () {
        _loadBeacons(center: _mapCenter);
      });
    }
  }

  void _onMarkerTap(Post post) {
    openDesktopDialog(
      context,
      width: 700,
      child: BeaconDetailScreen(beaconPost: post),
    );
  }

  void _onBeaconModelTap(Beacon beacon) {
    // Find matching post
    final post = _beacons.where((p) => p.id == beacon.id).firstOrNull;
    if (post != null) _onMarkerTap(post);
  }

  void _onCreateBeacon({BeaconType? preselectedType}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      isScrollControlled: true,
      builder: (context) => CreateBeaconSheet(
        centerLat: _mapCenter.latitude,
        centerLong: _mapCenter.longitude,
        onBeaconCreated: (post) {
          if (post.isBeaconPost) setState(() => _beacons.add(post));
          _loadBeacons();
        },
      ),
    );
  }

  Widget _buildBoardSortChip(String key, String label) {
    final selected = _boardSort == key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (selected) return;
          setState(() => _boardSort = key);
          _loadBoardEntries();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppTheme.brightNavy : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.brightNavy : AppTheme.navyBlue.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? SojornColors.basicWhite : AppTheme.brightNavy,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStat(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.brightNavy),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: AppTheme.navyBlue, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBoardEntries() async {
    if (_isLoadingBoard) return;
    debugPrint('[BEACON] Loading board entries for ${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)} topic=${_selectedBoardTopic?.value} sort=$_boardSort');
    setState(() => _isLoadingBoard = true);
    try {
      final data = await ApiService.instance.fetchBoardEntries(
        lat: _mapCenter.latitude,
        long: _mapCenter.longitude,
        topic: _selectedBoardTopic?.value,
        sort: _boardSort,
      );
      if (mounted) {
        setState(() {
          final rawEntries = (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _boardEntries = rawEntries.map((e) => BoardEntry.fromJson(e)).toList();
          _isNeighborhoodAdmin = data['is_neighborhood_admin'] == true;
          _isLoadingBoard = false;
        });
        debugPrint('[BEACON] Loaded ${_boardEntries.length} board entries, isAdmin=$_isNeighborhoodAdmin');
      }
    } catch (e) {
      debugPrint('[BEACON] Board load error: $e');
      if (mounted) setState(() => _isLoadingBoard = false);
    }

    final groupId = _neighborhoodGroupId;
    if (groupId != null && groupId.isNotEmpty) {
      _loadNeighborhoodHubMeta(groupId);
    }
  }

  String? get _neighborhoodGroupId {
    if (_neighborhood == null) return null;
    final direct = _neighborhood!['group_id'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = _neighborhood!['neighborhood'] as Map<String, dynamic>?;
    return nested?['group_id'] as String?;
  }

  String get _neighborhoodName {
    if (_neighborhood == null) return 'Commons';
    final direct = _neighborhood!['name'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = _neighborhood!['neighborhood'] as Map<String, dynamic>?;
    final nestedName = nested?['name'] as String?;
    return (nestedName != null && nestedName.isNotEmpty) ? nestedName : 'Commons';
  }

  Future<void> _loadNeighborhoodHubMeta(String groupId) async {
    if (_isLoadingNeighborhoodHubMeta) return;
    setState(() => _isLoadingNeighborhoodHubMeta = true);
    try {
      final members = await ApiService.instance.fetchGroupMembers(groupId);
      final messages = await ApiService.instance.fetchGroupMessages(groupId, limit: 40);
      final threads = await ApiService.instance.fetchGroupThreads(groupId, limit: 40);

      final nowUtc = DateTime.now().toUtc();
      final activeCutoff = nowUtc.subtract(const Duration(minutes: 30));
      final chatCutoff = nowUtc.subtract(const Duration(hours: 12));
      final forumCutoff = nowUtc.subtract(const Duration(hours: 18));
      final activeUserIds = <String>{};

      int chatActivity = 0;
      for (final m in messages) {
        final createdAtRaw = m['created_at']?.toString();
        final authorId = m['author_id']?.toString();
        if (createdAtRaw == null || authorId == null) continue;
        final createdAt = DateTime.tryParse(createdAtRaw)?.toUtc();
        if (createdAt == null) continue;
        if (createdAt.isAfter(chatCutoff)) chatActivity++;
        if (createdAt.isAfter(activeCutoff)) activeUserIds.add(authorId);
      }

      int forumActivity = 0;
      for (final t in threads) {
        final stampRaw = t['last_activity_at']?.toString() ?? t['created_at']?.toString();
        final authorId = t['author_id']?.toString();
        if (stampRaw == null || authorId == null) continue;
        final stamp = DateTime.tryParse(stampRaw)?.toUtc();
        if (stamp == null) continue;
        if (stamp.isAfter(forumCutoff)) forumActivity++;
        if (stamp.isAfter(activeCutoff)) activeUserIds.add(authorId);
      }

      if (mounted) {
        setState(() {
          _activeNeighborhoodMemberCount = members.length;
          _chatActivityCount = chatActivity;
          _forumActivityCount = forumActivity;
          _activeNowCount = activeUserIds.length;
          _isLoadingNeighborhoodHubMeta = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingNeighborhoodHubMeta = false);
      }
    }
  }

  Future<void> _removeBoardEntry(BoardEntry entry) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Content'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to remove this post? This action will be logged.'),
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason for removal', hintText: 'e.g. Hate speech, spam...'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: SojornColors.destructive)),
          ),
        ],
      ),
    );

    if (confirm == true && reasonController.text.isNotEmpty) {
      try {
        await ApiService.instance.removeBoardEntry(entry.id, reasonController.text);
        if (mounted) {
          setState(() {
            _boardEntries.removeWhere((e) => e.id == entry.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Content removed')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
      }
    }
  }

  Future<void> _flagBoardEntry(BoardEntry entry) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Content'),
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'Why is this inappropriate?'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );

    if (confirm == true && reasonController.text.isNotEmpty) {
      try {
        await ApiService.instance.flagBoardEntry(entry.id, reasonController.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to report: $e')));
      }
    }
  }

  void _onCreateBoardPost() {
    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      isScrollControlled: true,
      builder: (context) => CreateBoardPostSheet(
        centerLat: _mapCenter.latitude,
        centerLong: _mapCenter.longitude,
        onEntryCreated: (entry) {
          setState(() => _boardEntries.insert(0, entry));
        },
      ),
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchBeacons = [];
        _searchBoard = [];
        _searchGroups = [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _performBeaconSearch(query.trim()));
  }

  Future<void> _performBeaconSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final data = await ApiService.instance.beaconSearch(
        query: query,
        lat: _userLocation?.latitude ?? _mapCenter.latitude,
        lng: _userLocation?.longitude ?? _mapCenter.longitude,
        radius: 50000,
      );
      if (mounted) {
        setState(() {
          _searchBeacons = (data['beacons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _searchBoard = (data['board_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _searchGroups = (data['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _isSearching = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[BeaconSearch] Error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _toggleBoardVote(BoardEntry entry) async {
    try {
      final result = await ApiService.instance.toggleBoardVote(entryId: entry.id);
      final voted = result['voted'] as bool? ?? false;
      if (mounted) {
        setState(() {
          final idx = _boardEntries.indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            final old = _boardEntries[idx];
            _boardEntries[idx] = BoardEntry(
              id: old.id, body: old.body, imageUrl: old.imageUrl, topic: old.topic,
              lat: old.lat, long: old.long,
              upvotes: voted ? old.upvotes + 1 : old.upvotes - 1,
              replyCount: old.replyCount, isPinned: old.isPinned, createdAt: old.createdAt,
              authorHandle: old.authorHandle, authorDisplayName: old.authorDisplayName,
              authorAvatarUrl: old.authorAvatarUrl, hasVoted: voted,
            );
          }
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Board] Vote error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locationPermissionGranted) {
      return _buildLocationPermissionOverlay(context);
    }

    return LayoutBuilder(builder: (context, constraints) {
      // Desktop: map-only — Board and Groups live in their own nav sections.
      if (SojornBreakpoints.isDesktop(constraints.maxWidth)) {
        return _buildMapTab();
      }

      // Mobile: full 4-tab layout.
      return Column(
        children: [
          Material(
            color: AppTheme.scaffoldBg,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.brightNavy,
              unselectedLabelColor: SojornColors.textDisabled,
              indicatorColor: AppTheme.brightNavy,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Map', icon: Icon(Icons.map_outlined, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
                Tab(text: 'Commons', icon: Icon(Icons.location_city_outlined, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
                Tab(text: 'Groups', icon: Icon(Icons.groups_outlined, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
                Tab(text: 'Search', icon: Icon(Icons.search, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabController.index,
              children: [
                _buildMapTab(),
                _buildBoardView(),
                _buildGroupsView(),
                _buildSearchView(),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// Active geo-alerts only: no discussion types,
  /// and respecting the user's hidden-type filter selections.
  /// Expiration is handled server-side — expired beacons are not returned.
  List<Post> get _activeGeoAlerts {
    return [..._beacons, ..._officialPosts].where((p) {
      if (!(p.beaconType?.isGeoAlert ?? false)) return false;
      if (_hiddenTypes.contains(p.beaconType)) return false;
      return true;
    }).toList();
  }

  // ─── Map tab (map + overlay + draggable sheet) ────────────────────────
  Widget _buildMapTab() {
    return LayoutBuilder(builder: (context, constraints) {
      if (SojornBreakpoints.isDesktop(constraints.maxWidth)) {
        return _buildDesktopMapLayout();
      }
      // Use actual container height (excludes AppBar + NavBar) so FAB and pill
      // align correctly with the DraggableScrollableSheet fraction.
      final screenH = constraints.maxHeight;
      return _buildMapStack(screenH);
    });
  }

  Widget _buildDesktopMapLayout() {
    return Row(
      children: [
        // Map takes remaining space
        Expanded(
          child: Stack(
            children: [
              _buildMap(),
              _buildMapOverlayBar(),
              // FAB — create a new report
              Positioned(
                bottom: 24,
                right: 24,
                child: GestureDetector(
                  onTap: _onCreateBeacon,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppTheme.brightNavy.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Side panel replaces DraggableScrollableSheet
        Container(
          width: SojornBreakpoints.sidebarWidth,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(
              left: BorderSide(
                color: SojornColors.basicBlack.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              ActiveAlertsTicker(alerts: _beaconModels, onAlertTap: _onBeaconModelTap),
              if (_activeGeoAlerts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('Sorted by distance',
                        style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                    ],
                  ),
                ),
              Expanded(
                child: _activeGeoAlerts.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.brightNavy.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.12)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.lightbulb_outline, color: AppTheme.brightNavy, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('What are Beacons?',
                                          style: TextStyle(
                                            color: AppTheme.navyBlue,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          )),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Beacons are real-time local alerts from people in your area — road closures, safety incidents, community events, and more. Tap the + button to post your first beacon.',
                                          style: TextStyle(
                                            color: AppTheme.navyBlue.withValues(alpha: 0.65),
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Icon(Icons.shield, color: AppTheme.brightNavy.withValues(alpha: 0.25), size: 40),
                            const SizedBox(height: 10),
                            Text('All clear in your area',
                              style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.45), fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text('No active alerts nearby',
                              style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.3), fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _activeGeoAlerts.length,
                        itemBuilder: (context, index) => _buildIncidentCard(_activeGeoAlerts[index]),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapStack(double screenH) {
    return Stack(
      children: [
        _buildMap(),
        _buildMapOverlayBar(),
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.15,
          minChildSize: 0.15,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.15, 0.5, 0.85],
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: SojornColors.basicBlack.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Drag handle is pinned above the scroll view so it's always visible
                  _buildDragHandle(),
                  Expanded(
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: ActiveAlertsTicker(alerts: _beaconModels, onAlertTap: _onBeaconModelTap),
                        ),
                        if (_activeGeoAlerts.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on, size: 11, color: SojornColors.textDisabled),
                                  const SizedBox(width: 3),
                                  Text('Sorted by distance',
                                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        if (_activeGeoAlerts.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.brightNavy.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.12)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.lightbulb_outline, color: AppTheme.brightNavy, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('What are Beacons?',
                                                style: TextStyle(
                                                  color: AppTheme.navyBlue,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                )),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Beacons are real-time local alerts from people in your area — road closures, safety incidents, community events, and more. Tap the + button to post your first beacon.',
                                                style: TextStyle(
                                                  color: AppTheme.navyBlue.withValues(alpha: 0.65),
                                                  fontSize: 12,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Icon(Icons.shield, color: AppTheme.brightNavy.withValues(alpha: 0.25), size: 40),
                                  const SizedBox(height: 10),
                                  Text('All clear in your area',
                                    style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.45), fontSize: 14, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  Text('No active alerts nearby',
                                    style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.3), fontSize: 12)),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildIncidentCard(_activeGeoAlerts[index]),
                              childCount: _activeGeoAlerts.length,
                            ),
                          ),
                        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 16)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // Transparent overlay — tapping the map area above the sheet collapses it
        if (_sheetSize > 0.25)
          Positioned(
            top: 0, left: 0, right: 0,
            bottom: screenH * _sheetSize,
            child: GestureDetector(
              onTap: _collapseSheet,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // Floating status pill — glanceable summary above collapsed sheet
        _buildFloatingStatusPill(screenH),
        // FAB — create a new report
        if (_sheetSize < 0.6)
          Positioned(
            bottom: screenH * _sheetSize + 16,
            right: 16,
            child: GestureDetector(
              onTap: _onCreateBeacon,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppTheme.brightNavy.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Floating map overlay bar (weather + action buttons) ─────────────
  Widget _buildMapOverlayBar() {
    return Positioned(
      top: 8, left: 8, right: 8,
      child: Row(
        children: [
          // Weather chip — frosted glass, matches pill visual language
          if (_weather != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: SojornColors.basicWhite.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: SojornColors.basicWhite.withValues(alpha: 0.55),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(color: SojornColors.basicBlack.withValues(alpha: 0.10), blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_weatherIcon(_weather!.weatherCode), size: 17,
                        color: AppTheme.navyBlue.withValues(alpha: 0.85)),
                      const SizedBox(width: 6),
                      Text('${_weather!.temperature.round()}°F',
                        style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        )),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          // Filter button — badge shows how many types are hidden
          _buildMapLayerChips(),
          const SizedBox(width: 8),
          // My location button
          _mapIconButton(Icons.my_location,
            onTap: _isLoadingLocation ? null : () => _getCurrentLocation(forceCenter: true)),
          const SizedBox(width: 8),
          // Refresh button — bypasses distance/age cache
          _mapIconButton(Icons.refresh, onTap: () => _loadBeacons(force: true)),
        ],
      ),
    );
  }


  // ─── Map layer filter chips — inline toggle row on the map overlay ───────
  static const _mapLayerGroups = <({
    String label,
    IconData icon,
    Color color,
    List<BeaconType> types,
  })>[
    (
      label: 'Safety',
      icon: Icons.shield_outlined,
      color: Color(0xFFEF5350),
      types: [
        BeaconType.safety, BeaconType.suspiciousActivity,
        BeaconType.officialPresence, BeaconType.checkpoint, BeaconType.taskForce,
      ],
    ),
    (
      label: 'Hazards',
      icon: Icons.warning_amber_rounded,
      color: Color(0xFFFF7043),
      types: [BeaconType.hazard, BeaconType.fire, BeaconType.utilityAlert],
    ),
    (
      label: 'Traffic',
      icon: Icons.traffic_outlined,
      color: Color(0xFFFFAB00),
      types: [BeaconType.camera, BeaconType.sign, BeaconType.weatherStation],
    ),
    (
      label: 'Community',
      icon: Icons.people_outline,
      color: Color(0xFF78909C),
      types: [BeaconType.packageTheft, BeaconType.noiseReport, BeaconType.development],
    ),
  ];

  Widget _buildMapLayerChips() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.6), width: 0.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _mapLayerGroups.map((group) {
              final isVisible =
                  !group.types.every((t) => _hiddenTypes.contains(t));
              return GestureDetector(
                onTap: () => setState(() {
                  if (isVisible) {
                    _hiddenTypes.addAll(group.types);
                  } else {
                    _hiddenTypes.removeAll(group.types);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isVisible
                        ? group.color.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isVisible
                          ? group.color.withValues(alpha: 0.8)
                          : Colors.grey.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        group.icon,
                        size: 12,
                        color: isVisible
                            ? group.color
                            : Colors.grey.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isVisible
                              ? group.color
                              : Colors.grey.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ─── Floating status pill — glanceable summary between overlay bar and sheet ──
  Widget _buildFloatingStatusPill(double screenH) {
    // Count = total active alerts (same as the list below — pill IS the entry point)
    final total = _activeGeoAlerts.length;

    // Color driven by highest severity tier present
    final hasCritical = _beaconModels.any((b) =>
        b.beaconType.isGeoAlert &&
        b.severity == BeaconSeverity.critical &&
        b.incidentStatus == BeaconIncidentStatus.active);
    final hasHigh = _beaconModels.any((b) =>
        b.beaconType.isGeoAlert &&
        b.severity == BeaconSeverity.high &&
        b.incidentStatus == BeaconIncidentStatus.active);

    final Color pillColor;
    final IconData pillIcon;

    if (total == 0) {
      pillColor = const Color(0xFF4CAF50);
      pillIcon = Icons.shield;
    } else if (hasCritical) {
      pillColor = SojornColors.destructive;
      pillIcon = Icons.warning_rounded;
    } else if (hasHigh) {
      pillColor = const Color(0xFFFF5722);
      pillIcon = Icons.error_outline;
    } else {
      pillColor = const Color(0xFFFFC107);
      pillIcon = Icons.info_outline;
    }

    final pillText = total == 0
        ? 'All Clear'
        : '$total Alert${total == 1 ? '' : 's'} Nearby';

    // Float left (avoids FAB on the right); hides as sheet opens past halfway
    final pillBottom = (screenH * _sheetSize).clamp(screenH * 0.15, screenH * 0.5) + 14.0;
    final visible = _sheetSize < 0.55;

    return Positioned(
      bottom: pillBottom,
      left: 16,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: () {
            if (!_sheetController.isAttached) return;
            _sheetController.animateTo(0.5,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  // Translucent tint — blur does the heavy lifting
                  color: pillColor.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: pillColor.withValues(alpha: 0.5),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: pillColor.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(pillIcon, size: 14, color: pillColor),
                    const SizedBox(width: 6),
                    Text(pillText,
                      style: TextStyle(
                        color: pillColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      )),
                    const SizedBox(width: 5),
                    Icon(Icons.keyboard_arrow_up_rounded, size: 15,
                      color: pillColor.withValues(alpha: 0.65)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _weatherIcon(int code) {
    if (code <= 1) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud;
    if (code <= 49) return Icons.foggy;
    if (code <= 69) return Icons.water_drop;
    if (code <= 79) return Icons.ac_unit;
    if (code <= 99) return Icons.thunderstorm;
    return Icons.cloud;
  }

  BeaconTab get activeTab => _activeTab;

  String get createLabel {
    switch (_activeTab) {
      case BeaconTab.map: return 'Report';
      case BeaconTab.board: return 'Post';
      case BeaconTab.search: return 'Create';
      case BeaconTab.groups: return 'New';
    }
  }

  /// Called from HomeShell app bar when on Beacon tab
  void onCreateAction() {
    switch (_activeTab) {
      case BeaconTab.map:
        _onCreateBeacon();
        break;
      case BeaconTab.board:
        _onCreateBoardPost();
        break;
      case BeaconTab.search:
        _onCreateBeacon();
        break;
      case BeaconTab.groups:
        _showCreateGroupSheet();
        break;
    }
  }

  // ─── Board view (standalone neighborhood board) ─────────────────────
  Widget _buildBoardView() {
    if (_neighborhood == null) {
      return Center(
        child: _isDetectingNeighborhood
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  const Text('No neighborhood detected', style: TextStyle(color: SojornColors.textDisabled)),
                  TextButton(onPressed: () => _detectNeighborhood(_userLocation?.latitude ?? 0, _userLocation?.longitude ?? 0),
                    child: const Text('Retry')),
                ],
              ),
      );
    }

    final groupId = _neighborhoodGroupId;
    if (groupId == null || groupId.isEmpty) {
      return Center(
        child: Text('Neighborhood unavailable', style: TextStyle(color: SojornColors.textDisabled)),
      );
    }

    final groupName = _neighborhoodName;
    final isAdmin = _isNeighborhoodAdmin;
    if (_lastNeighborhoodMetaGroupId != groupId) {
      _lastNeighborhoodMetaGroupId = groupId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNeighborhoodHubMeta(groupId);
      });
    }

    final matchedCluster = _clusters.where((c) => c.id == groupId).firstOrNull;
    final hubCluster = matchedCluster ?? Cluster(
      id: groupId,
      name: groupName,
      type: 'geo',
      memberCount: _activeNeighborhoodMemberCount,
      createdAt: DateTime.now(),
    );

    final availableSwitchTargets = _clusters.where((c) => c.id != groupId).take(8).toList();

    return Column(
      children: [
        Container(
          color: AppTheme.cardSurface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.home_filled, size: 18, color: AppTheme.brightNavy),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  groupName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (availableSwitchTargets.isNotEmpty)
                                PopupMenuButton<String>(
                                  tooltip: 'Quick switch',
                                  icon: Icon(Icons.keyboard_arrow_down, size: 18, color: SojornColors.textDisabled),
                                  onSelected: (value) {
                                    final target = _clusters.where((c) => c.id == value).firstOrNull;
                                    if (target != null) {
                                      _navigateToCluster(target);
                                    }
                                  },
                                  itemBuilder: (_) => availableSwitchTargets
                                      .map(
                                        (c) => PopupMenuItem<String>(
                                          value: c.id,
                                          child: Row(
                                            children: [
                                              Icon(
                                                c.isCapsule ? Icons.lock : Icons.location_on,
                                                size: 14,
                                                color: c.isCapsule ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  c.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.bolt, size: 12, color: AppTheme.brightNavy.withValues(alpha: 0.8)),
                              const SizedBox(width: 4),
                              Text(
                                _isLoadingNeighborhoodHubMeta
                                    ? 'Checking activity...'
                                    : '$_activeNowCount active now',
                                style: TextStyle(color: SojornColors.textDisabled, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.people, size: 12, color: SojornColors.textDisabled),
                              const SizedBox(width: 4),
                              Text(
                                '${_activeNeighborhoodMemberCount > 0 ? _activeNeighborhoodMemberCount : hubCluster.memberCount} members',
                                style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.brightNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text('ADMIN', style: TextStyle(color: AppTheme.brightNavy, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    IconButton(
                      onPressed: () => _showNeighborhoodPicker(
                        isChangeMode: true,
                        nextChangeDate: _canChangeNeighborhood ? null : _nextChangeDate,
                      ),
                      icon: Icon(Icons.swap_horiz_rounded, size: 20, color: SojornColors.textDisabled),
                      tooltip: 'Change neighborhood',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.scaffoldBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Recent posts from members',
                          child: _buildHubSegment(
                            label: 'Feed',
                            icon: Icons.rss_feed,
                            selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.feed,
                            onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.feed),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: 'Live group chat',
                          child: _buildHubSegment(
                            label: 'Chat',
                            icon: Icons.chat_bubble_outline,
                            badgeCount: _chatActivityCount,
                            selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.chat,
                            onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.chat),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: 'Threaded discussions',
                          child: _buildHubSegment(
                            label: 'Forum',
                            icon: Icons.forum_outlined,
                            badgeCount: _forumActivityCount,
                            selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.forum,
                            onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.forum),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: 'Group members',
                          child: _buildHubSegment(
                            label: 'Members',
                            icon: Icons.groups_2_outlined,
                            selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.members,
                            onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.members),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_activeNeighborhoodHubTab) {
            NeighborhoodHubTab.feed => _buildNeighborhoodFeedPane(groupName),
            NeighborhoodHubTab.chat => GroupChatTab(
                groupId: groupId,
                currentUserId: AuthService.instance.currentUser?.id,
              ),
            NeighborhoodHubTab.forum => GroupForumTab(groupId: groupId),
            NeighborhoodHubTab.members => GroupMembersTab(
                groupId: groupId,
                group: hubCluster,
                isEncrypted: false,
              ),
          },
        ),
      ],
    );
  }

  Widget _buildHubSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.navyBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? SojornColors.basicWhite : SojornColors.textDisabled),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? SojornColors.basicWhite : SojornColors.textDisabled,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? SojornColors.basicWhite : AppTheme.brightNavy,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: TextStyle(
                    color: selected ? AppTheme.navyBlue : SojornColors.basicWhite,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNeighborhoodFeedPane(String groupName) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _onCreateBoardPost,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.brightNavy.withValues(alpha: 0.12),
                    child: Icon(Icons.edit, size: 14, color: AppTheme.brightNavy.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "What's happening in $groupName?",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: SojornColors.textDisabled, fontSize: 13),
                    ),
                  ),
                  FilledButton(
                    onPressed: _onCreateBoardPost,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.navyBlue,
                      foregroundColor: SojornColors.basicWhite,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Post', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          color: AppTheme.scaffoldBg,
          child: Row(
            children: [
              Icon(Icons.filter_list, size: 14, color: SojornColors.textDisabled),
              const SizedBox(width: 6),
              _buildBoardSortChip('new', 'New'),
              const SizedBox(width: 6),
              _buildBoardSortChip('hot', 'Hot'),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingBoard && _boardEntries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _boardEntries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 52, color: AppTheme.navyBlue.withValues(alpha: 0.18)),
                          const SizedBox(height: 14),
                          Text('No posts yet', style: TextStyle(color: SojornColors.textDisabled, fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Share something with $groupName', style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _onCreateBoardPost,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Post to Board'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.brightNavy,
                              side: BorderSide(color: AppTheme.brightNavy.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBoardEntries,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _boardEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _buildBoardEntryCard(_boardEntries[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildBoardFilterChip(BoardTopic? topic, String label, IconData icon, Color color) {
    final isSelected = _selectedBoardTopic == topic;
    return Material(
      color: Colors.transparent,
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? SojornColors.basicWhite : color),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? SojornColors.basicWhite : color,
        ),
        selectedColor: color,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          setState(() => _selectedBoardTopic = isSelected ? null : topic);
          _loadBoardEntries();
        },
      ),
    );
  }

  Widget _buildBoardEntryCard(BoardEntry entry) {
    final topicColor = entry.topic.color;
    final authorName = entry.authorDisplayName.isNotEmpty ? entry.authorDisplayName : entry.authorHandle;
    final avatarInitial = authorName.isNotEmpty ? authorName[0].toUpperCase() : 'N';
    return GestureDetector(
      onTap: () async {
        final isDesktop = MediaQuery.of(context).size.width >= 900;
        BoardEntry? updated;
        if (isDesktop) {
          openDesktopDialog(
            context,
            width: 600,
            child: BoardEntryDetailScreen(entry: entry),
          );
        } else {
          updated = await Navigator.of(context).push<BoardEntry>(
            MaterialPageRoute(builder: (_) => BoardEntryDetailScreen(entry: entry)),
          );
        }
        if (updated != null && mounted) {
          final u = updated;
          setState(() {
            final idx = _boardEntries.indexWhere((e) => e.id == u.id);
            if (idx >= 0) _boardEntries[idx] = u;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: entry.isPinned ? AppTheme.brightNavy.withValues(alpha: 0.03) : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: entry.isPinned ? AppTheme.brightNavy.withValues(alpha: 0.24) : AppTheme.navyBlue.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.isPinned) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brightNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin, size: 12, color: AppTheme.brightNavy),
                    const SizedBox(width: 4),
                    Text('Pinned by moderators', style: TextStyle(fontSize: 11, color: AppTheme.brightNavy, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
            // Header: topic badge + time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: topicColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.topic.icon, size: 12, color: topicColor),
                    const SizedBox(width: 4),
                    Text(entry.topic.displayName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: topicColor)),
                  ]),
                ),
                if (entry.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin, size: 12, color: AppTheme.brightNavy),
                ],
                const Spacer(),
                Text(entry.getTimeAgo(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            // User row: avatar + name + resident badge
            Row(
              children: [
                SojornAvatar(
                  displayName: entry.authorDisplayName.isNotEmpty ? entry.authorDisplayName : entry.authorHandle,
                  avatarUrl: entry.authorAvatarUrl.isNotEmpty ? entry.authorAvatarUrl : null,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: SojornColors.postContent, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Resident',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.brightNavy),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Body
            Text(entry.body, maxLines: 4, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: SojornColors.postContentLight, fontSize: 14, height: 1.4)),
            // Image
            if (entry.imageUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(entry.imageUrl!, height: 140, width: double.infinity, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 10),
            // Bottom action bar: upvote | comments | flag
            Row(
              children: [
                // Upvote button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleBoardVote(entry),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          entry.hasVoted ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                          size: 16,
                          color: entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled,
                        ),
                        const SizedBox(width: 4),
                        Text('${entry.upvotes}', style: TextStyle(
                          color: entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Reply count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline, size: 15, color: SojornColors.textDisabled),
                    const SizedBox(width: 4),
                    Text('${entry.replyCount}', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const Spacer(),
                // Flag/Report button
                if (_isNeighborhoodAdmin)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, size: 16, color: SojornColors.textDisabled),
                    onSelected: (val) {
                      if (val == 'remove') _removeBoardEntry(entry);
                      if (val == 'flag') _flagBoardEntry(entry);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'flag', child: Text('Flag Content')),
                      const PopupMenuItem(value: 'remove', child: Text('Remove (Admin)', style: TextStyle(color: SojornColors.destructive))),
                    ],
                  )
                else
                  IconButton(
                    icon: Icon(Icons.flag_outlined, size: 16, color: SojornColors.textDisabled.withValues(alpha: 0.5)),
                    onPressed: () => _flagBoardEntry(entry),
                    tooltip: 'Report Content',
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Search view ───────────────────────────────────────────────────
  Widget _buildSearchView() {
    final hasResults = _searchBeacons.isNotEmpty || _searchBoard.isNotEmpty || _searchGroups.isNotEmpty;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Container(
      color: AppTheme.scaffoldBg,
      child: Column(
        children: [
          // Search input
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: SojornColors.postContent, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search beacons, boards, groups…',
                  hintStyle: TextStyle(color: SojornColors.textDisabled),
                  prefixIcon: Icon(Icons.search, size: 20, color: SojornColors.textDisabled),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon: Icon(Icons.close, size: 18, color: SojornColors.textDisabled),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),
          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : !hasQuery
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sensors, color: AppTheme.navyBlue.withValues(alpha: 0.15), size: 56),
                            const SizedBox(height: 12),
                            Text('Search the beacon ecosystem',
                              style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Find incidents, board posts, and public groups',
                              style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                          ],
                        ),
                      )
                    : !hasResults
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, color: AppTheme.navyBlue.withValues(alpha: 0.2), size: 48),
                                const SizedBox(height: 12),
                                Text('No results found',
                                  style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              if (_searchBeacons.isNotEmpty) ...[
                                _searchSectionHeader('Beacons', Icons.sensors, _searchBeacons.length),
                                ..._searchBeacons.map(_buildBeaconResult),
                              ],
                              if (_searchBoard.isNotEmpty) ...[
                                _searchSectionHeader('Board Posts', Icons.forum, _searchBoard.length),
                                ..._searchBoard.map(_buildBoardResult),
                              ],
                              if (_searchGroups.isNotEmpty) ...[
                                _searchSectionHeader('Public Groups', Icons.groups, _searchGroups.length),
                                ..._searchGroups.map(_buildGroupResult),
                              ],
                              const SizedBox(height: 16),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _searchSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.brightNavy),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: AppTheme.navyBlue, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('($count)', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBeaconResult(Map<String, dynamic> b) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.warning_amber, color: Colors.orange, size: 22),
        title: Text(b['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: SojornColors.postContent, fontSize: 13)),
        subtitle: Text('${b['category'] ?? 'incident'} · ${b['author_handle'] ?? ''}',
          style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
        onTap: () {
          // Navigate to beacon detail if possible
        },
      ),
    );
  }

  Widget _buildBoardResult(Map<String, dynamic> b) {
    final topic = b['topic'] as String? ?? 'community';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.forum, color: AppTheme.brightNavy, size: 22),
        title: Text(b['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: SojornColors.postContent, fontSize: 13)),
        subtitle: Text('$topic · ${b['author_handle'] ?? ''}',
          style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_upward, size: 12, color: SojornColors.textDisabled),
            Text('${b['upvotes'] ?? 0}', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
          ],
        ),
        onTap: () {
          final entry = BoardEntry.fromJson(b);
          openDesktopDialog(
            context,
            width: 600,
            child: BoardEntryDetailScreen(entry: entry),
          );
        },
      ),
    );
  }

  Widget _buildGroupResult(Map<String, dynamic> g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: SojornAvatar(
          displayName: g['name'] as String? ?? '',
          avatarUrl: (g['avatar_url'] as String?)?.isNotEmpty == true ? g['avatar_url'] as String : null,
          size: 36,
        ),
        title: Text(g['name'] ?? '', style: TextStyle(color: SojornColors.postContent, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((g['description'] as String?)?.isNotEmpty == true) ...[
              Text(
                g['description'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: SojornColors.postContentLight, fontSize: 11),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              '${g['member_count'] ?? 0} member${(g['member_count'] ?? 0) == 1 ? '' : 's'} · ${g['type'] ?? ''}',
              style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
            ),
          ],
        ),
        onTap: () {
          final cluster = Cluster.fromJson(g);
          _navigateToCluster(cluster);
        },
      ),
    );
  }

  // ─── Groups view (clusters + capsules) ──────────────────────────────
  Widget _buildGroupsView() {
    var filtered = _selectedGroupCategory == null
        ? _clusters
        : _clusters.where((c) => c.category == _selectedGroupCategory).toList();
    
    // Filter out current neighborhood board group
    if (_neighborhood != null && _neighborhood!['group_id'] != null) {
      final hoodGroupId = _neighborhood!['group_id'];
      filtered = filtered.where((c) => c.id != hoodGroupId).toList();
    }

    final neighborhoods = filtered.where((c) => !c.isCapsule).toList();
    final capsules = filtered.where((c) => c.isCapsule).toList();

    var filteredDiscover = _selectedGroupCategory == null
        ? _discoverClusters
        : _discoverClusters.where((c) => c.category == _selectedGroupCategory).toList();
    // Also filter out neighborhood group from discover
    if (_neighborhood != null && _neighborhood!['group_id'] != null) {
      final hoodGroupId = _neighborhood!['group_id'];
      filteredDiscover = filteredDiscover.where((c) => c.id != hoodGroupId).toList();
    }

    return Container(
      color: AppTheme.scaffoldBg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              border: Border(bottom: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Icon(Icons.groups, color: AppTheme.brightNavy, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Groups',
                    style: TextStyle(color: AppTheme.navyBlue, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.add, color: AppTheme.brightNavy),
                  onSelected: (val) {
                    if (val == 'group') _showCreateGroupSheet();
                    if (val == 'capsule') _showCreateCapsuleSheet();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'group', child: Text('New Group')),
                    const PopupMenuItem(value: 'capsule', child: Text('New Capsule')),
                  ],
                ),
              ],
            ),
          ),
          // Category filters
          Container(
            color: AppTheme.cardSurface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Icon(Icons.swipe, size: 13, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('Swipe for more categories', style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _buildGroupCategoryChip(null, 'All', Icons.grid_view, AppTheme.brightNavy, _clusters.length),
                      const SizedBox(width: 6),
                      ...GroupCategory.values.map((cat) {
                        final count = _clusters.where((c) => c.category == cat).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _buildGroupCategoryChip(cat, cat.displayName, cat.icon, cat.color, count),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingClusters
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadClusters,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      children: [
                        if (neighborhoods.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                            child: Text('MY GROUPS', style: TextStyle(
                              color: AppTheme.navyBlue.withValues(alpha: 0.4),
                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                            )),
                          ),
                          ...neighborhoods.map((c) => _buildClusterCard(c, isCapsule: false)),
                        ],
                        if (capsules.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                            child: Row(
                              children: [
                                Icon(Icons.lock, size: 12, color: const Color(0xFF4CAF50)),
                                const SizedBox(width: 6),
                                Text('CAPSULES', style: TextStyle(
                                  color: const Color(0xFF2E7D32),
                                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                                )),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'E2E',
                                    style: TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...capsules.map((c) => _buildClusterCard(c, isCapsule: true)),
                        ],
                        if (filteredDiscover.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                            child: Text('DISCOVER', style: TextStyle(
                              color: AppTheme.navyBlue.withValues(alpha: 0.4),
                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                            )),
                          ),
                          ...filteredDiscover.map((c) => _buildClusterCard(c, isCapsule: false)),
                        ],
                        if (_clusters.isEmpty && filteredDiscover.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.group_add, color: AppTheme.navyBlue.withValues(alpha: 0.2), size: 48),
                                  const SizedBox(height: 12),
                                  Text('No groups yet', style: TextStyle(
                                    color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 15, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('Create a group to get started',
                                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCategoryChip(GroupCategory? category, String label, IconData icon, Color color, int count) {
    final isSelected = _selectedGroupCategory == category;
    final selectedColor = AppTheme.navyBlue;
    return Material(
      color: Colors.transparent,
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected ? SojornColors.basicWhite.withValues(alpha: 0.18) : color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 13, color: isSelected ? SojornColors.basicWhite : color),
            ),
            const SizedBox(width: 6),
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? SojornColors.basicWhite.withValues(alpha: 0.25)
                      : AppTheme.navyBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? SojornColors.basicWhite : AppTheme.navyBlue,
                  ),
                ),
              ),
            ],
          ],
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? SojornColors.basicWhite : AppTheme.navyBlue,
        ),
        selectedColor: selectedColor,
        backgroundColor: AppTheme.cardSurface,
        side: BorderSide(color: isSelected ? selectedColor : AppTheme.navyBlue.withValues(alpha: 0.14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: isSelected ? 1 : 0,
        shadowColor: selectedColor.withValues(alpha: 0.25),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          setState(() => _selectedGroupCategory = isSelected ? null : category);
        },
      ),
    );
  }

  Widget _buildClusterCard(Cluster cluster, {required bool isCapsule}) {
    final capsuleGreen = const Color(0xFF4CAF50);
    final capsuleDark = const Color(0xFF2E7D32);
    return GestureDetector(
      onTap: () => _navigateToCluster(cluster),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isCapsule
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF4FBF4),
                    const Color(0xFFE9F6EC),
                  ],
                )
              : null,
          color: isCapsule ? null : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCapsule ? capsuleGreen.withValues(alpha: 0.32) : AppTheme.navyBlue.withValues(alpha: 0.08),
          ),
          boxShadow: isCapsule
              ? [
                  BoxShadow(
                    color: capsuleGreen.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Avatar: real image if set, otherwise category icon on branded bg.
            if (cluster.avatarUrl != null && cluster.avatarUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SojornAvatar(
                  displayName: cluster.name,
                  avatarUrl: cluster.avatarUrl,
                  size: 42,
                ),
              )
            else
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isCapsule
                    ? capsuleGreen.withValues(alpha: 0.1)
                    : cluster.category.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCapsule ? Icons.lock : cluster.category.icon,
                color: isCapsule ? capsuleGreen : AppTheme.brightNavy,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cluster.name, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                  )),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (isCapsule) ...[
                      Icon(Icons.shield, size: 11, color: capsuleDark),
                      const SizedBox(width: 3),
                      Text('E2E Encrypted', style: TextStyle(fontSize: 10, color: capsuleDark, fontWeight: FontWeight.w600)),
                    ] else ...[
                      Icon(Icons.public, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('Public', style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                    ],
                    const SizedBox(width: 8),
                    Icon(Icons.people, size: 11,
                      color: SojornColors.textDisabled),
                    const SizedBox(width: 3),
                    Text('${cluster.memberCount}', style: TextStyle(fontSize: 10,
                      color: SojornColors.textDisabled)),
                    if (cluster.category != GroupCategory.general) ...[
                      const SizedBox(width: 8),
                      Icon(cluster.category.icon, size: 11, color: cluster.category.color.withValues(alpha: 0.7)),
                      const SizedBox(width: 3),
                      Text(cluster.category.displayName, style: TextStyle(fontSize: 10, color: cluster.category.color.withValues(alpha: 0.7))),
                    ],
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18,
              color: SojornColors.textDisabled),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _CreateGroupInline(onCreated: () {
        Navigator.pop(ctx);
        _loadClusters();
      }),
    );
  }

  void _showCreateCapsuleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _CreateCapsuleInline(onCreated: () {
        Navigator.pop(ctx);
        _loadClusters();
      }),
    );
  }

  Widget _buildDragHandle() {
    final alertCount = _activeGeoAlerts.length;
    return GestureDetector(
      onTap: () {
        if (!_sheetController.isAttached) return;
        if (_sheetSize < 0.3) {
          _sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        } else {
          _collapseSheet();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        child: Column(
          children: [
            // Drag pill
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            // Summary row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    alertCount == 0 ? 'All Clear' : '$alertCount Incident${alertCount == 1 ? '' : 's'} Nearby',
                    style: TextStyle(
                      color: alertCount == 0
                          ? const Color(0xFF4CAF50)
                          : AppTheme.navyBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _sheetSize >= 0.7 ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                    color: AppTheme.navyBlue.withValues(alpha: 0.35),
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(Post post) {
    final beacon = post.toBeacon();
    final severityColor = beacon.pinColor;
    final isRecent = beacon.isRecent;
    final isOfficialSource = beacon.isOfficial; // MN511 government alert
    final isOfficialType = beacon.beaconType == BeaconType.officialPresence ||
        beacon.beaconType == BeaconType.checkpoint ||
        beacon.beaconType == BeaconType.taskForce;
    final isOfficial = isOfficialSource || isOfficialType;
    const officialBlue = Color(0xFF1565C0);
    final iconColor = isOfficial ? officialBlue : severityColor;

    return GestureDetector(
      onTap: () => _onMarkerTap(post),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOfficial
                ? officialBlue.withValues(alpha: isRecent ? 0.5 : 0.25)
                : isRecent
                    ? severityColor.withValues(alpha: 0.5)
                    : AppTheme.navyBlue.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(beacon.beaconType.icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(beacon.beaconType.displayName,
                          style: TextStyle(color: AppTheme.navyBlue, fontSize: 14, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      ),
                      if (isOfficialSource)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: officialBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(beacon.officialSource ?? 'OFFICIAL',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                        )
                      else if (isOfficialType)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: officialBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: officialBlue.withValues(alpha: 0.35)),
                          ),
                          child: const Text('OFFICIAL',
                            style: TextStyle(color: officialBlue, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                        ),
                      if (isRecent)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SojornColors.destructive.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LIVE', style: TextStyle(color: SojornColors.destructive, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(beacon.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: SojornColors.postContentLight, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text(beacon.getTimeAgo(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                      const SizedBox(width: 10),
                      Icon(Icons.location_on, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text(beacon.getFormattedDistance(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                      const Spacer(),
                      if (beacon.verificationCount > 0) ...[
                        Icon(Icons.visibility, size: 11, color: SojornColors.textDisabled),
                        const SizedBox(width: 3),
                        Text('${beacon.verificationCount}', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                      ],
                    ],
                  ),
                  // ── Crowd-verification buttons ──────────────────────
                  // Inspired by Ushahidi's incident verification UI —
                  // turning Beacons from passive broadcasts into a
                  // crowdsourced ground-truth system.
                  if (!isOfficial) ...[
                    const SizedBox(height: 8),
                    _BeaconVoteRow(
                      post: post,
                      beacon: beacon,
                      apiService: ref.read(apiServiceProvider),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: _currentZoom,
        onPositionChanged: _onMapPositionChanged,
        minZoom: 3.0,
        maxZoom: 19.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.sojorn.app',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        // Clustered beacon markers — auto-groups nearby pins.
        // Key changes when filter state changes, forcing a full rebuild so the
        // cluster layer re-reads the filtered marker list immediately.
        MarkerClusterLayerWidget(
          key: ValueKey('clusters_${_hiddenTypes.hashCode}'),
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 55,
            disableClusteringAtZoom: 16,
            size: const Size(44, 44),
            alignment: Alignment.center,
            zoomToBoundsOnClick: true,
            spiderfyCluster: false,
            markers: _buildAllBeaconMarkers(),
            builder: _buildClusterWidget,
          ),
        ),
        // Public event markers — calendar pins for events with coordinates
        if (_mapEvents.isNotEmpty)
          MarkerLayer(markers: _buildEventMarkers()),
        // Camera markers — shown only when zoomed in enough (≥ 12)
        if (_currentZoom >= 12.0 && _cameraPosts.isNotEmpty)
          MarkerLayer(markers: _buildCameraMarkers()),
        // DMS sign markers — zoom ≥ 11
        if (_currentZoom >= 11.0 && _signPosts.isNotEmpty)
          MarkerLayer(markers: _buildSignMarkers()),
        // RWIS weather station markers — zoom ≥ 10
        if (_currentZoom >= 10.0 && _weatherPosts.isNotEmpty)
          MarkerLayer(markers: _buildWeatherMarkers()),
        // User location marker (not clustered)
        if (_locationPermissionGranted && _userLocation != null)
          MarkerLayer(markers: [_createUserLocationMarker()]),
      ],
    );
  }

  // Builds the flat list of all beacon Markers for the cluster layer
  List<Marker> _buildAllBeaconMarkers() {
    return [..._beacons, ..._officialPosts]
        .where((p) =>
            p.isBeaconPost &&
            (p.beaconType?.isGeoAlert ?? false) &&
            !_hiddenTypes.contains(p.beaconType))
        .map((p) => _createMarker(p))
        .toList();
  }

  // Renders a cluster bubble with count + severity-tinted color
  Widget _buildClusterWidget(BuildContext context, List<Marker> clusterMarkers) {
    // Determine the highest severity among clustered posts.
    // Encode severity in marker keys: "severity:critical:id", "severity:high:id", etc.
    Color clusterColor = AppTheme.navyBlue;
    for (final m in clusterMarkers) {
      final keyStr = m.key?.toString() ?? '';
      if (keyStr.contains('severity:critical')) { clusterColor = SojornColors.destructive; break; }
      if (keyStr.contains('severity:high')) { clusterColor = const Color(0xFFFF5722); }
      else if (keyStr.contains('severity:medium') && clusterColor == AppTheme.navyBlue) {
        clusterColor = const Color(0xFFFFC107);
      }
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: clusterColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: clusterColor.withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          clusterMarkers.length.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationPermissionOverlay(BuildContext context) {
    return Container(
      color: AppTheme.scaffoldBg,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, size: 64, color: AppTheme.brightNavy),
              const SizedBox(height: 24),
              Text('Beacon',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Community Safety Network',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SojornColors.textDisabled),
                textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Text('Location access is required to show safety alerts and connect you with your neighborhood.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SojornColors.postContentLight),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Material(
                color: Colors.transparent,
                child: ElevatedButton.icon(
                  onPressed: _isLoadingLocation ? null : _requestLocationPermission,
                  icon: _isLoadingLocation
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.location_on),
                  label: const Text('Enable Location'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brightNavy, foregroundColor: SojornColors.basicWhite),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Camera marker layer ──────────────────────────────────────────────
  List<Marker> _buildCameraMarkers() {
    return _cameraPosts.map((cam) {
      if (cam.beaconLat == null || cam.beaconLong == null) return null;
      return Marker(
        key: ValueKey('camera:${cam.id}'),
        point: LatLng(cam.beaconLat!, cam.beaconLong!),
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showCameraSheet(cam),
          child: Center(
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF0097A7),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.videocam, color: Colors.white, size: 16),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  void _showCameraSheet(Beacon cam) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => CameraViewerSheet(camera: cam),
    );
  }

  // ─── Sign marker layer ────────────────────────────────────────────────
  List<Marker> _buildSignMarkers() {
    return _signPosts.map((sign) {
      if (sign.beaconLat == null || sign.beaconLong == null) return null;
      return Marker(
        key: ValueKey('sign:${sign.id}'),
        point: LatLng(sign.beaconLat!, sign.beaconLong!),
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showSignSheet(sign),
          child: Center(
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFFFAB00),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.signpost, color: Colors.white, size: 16),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  void _showSignSheet(Beacon sign) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _SignDetailSheet(sign: sign),
    );
  }

  // ─── Weather station marker layer ─────────────────────────────────────
  List<Marker> _buildWeatherMarkers() {
    return _weatherPosts.map((wx) {
      if (wx.beaconLat == null || wx.beaconLong == null) return null;
      final color = wx.severity.color;
      return Marker(
        key: ValueKey('weather:${wx.id}'),
        point: LatLng(wx.beaconLat!, wx.beaconLong!),
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showWeatherSheet(wx),
          child: Center(
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.cloud, color: Colors.white, size: 16),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  void _showWeatherSheet(Beacon wx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _WeatherDetailSheet(wx: wx),
    );
  }

  Marker _createMarker(Post post) {
    final beacon = post.toBeacon();
    final severityColor = beacon.pinColor;
    final typeIcon = beacon.beaconType.icon;
    // Only animate if truly new (< 10 min) AND high/critical severity.
    // MN511 cameras refresh frequently so many markers get recent timestamps —
    // running 400 animation controllers for 200 beacons causes serious jank.
    final isRecent = beacon.isRecent &&
        DateTime.now().difference(beacon.createdAt).inMinutes < 10 &&
        (beacon.severity == BeaconSeverity.high ||
            beacon.severity == BeaconSeverity.critical);

    final fallbackBase = _userLocation ?? _mapCenter;
    final markerPosition = (post.latitude != null && post.longitude != null)
        ? LatLng(post.latitude!, post.longitude!)
        : LatLng(
            fallbackBase.latitude + ((post.distanceMeters ?? 0) / 111000),
            fallbackBase.longitude + ((post.distanceMeters ?? 0) / 111000),
          );

    // Encode severity in the key so _buildClusterWidget can tint the cluster bubble
    final markerKey = ValueKey('severity:${beacon.severity.value}:${post.id}');

    return Marker(
      key: markerKey,
      point: markerPosition,
      width: 56,
      height: 56,
      child: GestureDetector(
        onTap: () => _onMarkerTap(post),
        child: _SeverityMarker(
          color: severityColor,
          icon: typeIcon,
          isRecent: isRecent,
        ),
      ),
    );
  }

  Marker _createUserLocationMarker() {
    return Marker(
      point: _userLocation!,
      width: 40,
      height: 40,
      child: _PulsingLocationIndicator(),
    );
  }
}

// ─── Severity-colored Marker with ripple ring for recent ─────────────
class _SeverityMarker extends StatefulWidget {
  final Color color;
  final IconData icon;
  final bool isRecent;

  const _SeverityMarker({
    required this.color,
    required this.icon,
    required this.isRecent,
  });

  @override
  State<_SeverityMarker> createState() => _SeverityMarkerState();
}

class _SeverityMarkerState extends State<_SeverityMarker>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _ripple2Controller;
  late Animation<double> _rippleAnim;
  late Animation<double> _ripple2Anim;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _ripple2Controller = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    if (widget.isRecent) {
      _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
      );
      _ripple2Anim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ripple2Controller, curve: Curves.easeOut),
      );
      _rippleController.repeat();
      // Offset the second ring by half the duration
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _ripple2Controller.repeat();
      });
    } else {
      _rippleAnim = const AlwaysStoppedAnimation(0.0);
      _ripple2Anim = const AlwaysStoppedAnimation(0.0);
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _ripple2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: AnimatedBuilder(
        animation: Listenable.merge([_rippleAnim, _ripple2Anim]),
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Ripple ring 1
              if (widget.isRecent)
                Transform.scale(
                  scale: 0.7 + _rippleAnim.value * 1.1,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(
                          alpha: (0.55 * (1.0 - _rippleAnim.value)).clamp(0.0, 1.0)),
                    ),
                  ),
                ),
              // Ripple ring 2 (offset)
              if (widget.isRecent)
                Transform.scale(
                  scale: 0.7 + _ripple2Anim.value * 1.1,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(
                          alpha: (0.45 * (1.0 - _ripple2Anim.value)).clamp(0.0, 1.0)),
                    ),
                  ),
                ),
              // Main pin
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: widget.isRecent ? 0.5 : 0.3),
                      blurRadius: widget.isRecent ? 10 : 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: SojornColors.basicWhite, size: 22),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Pulsing user location dot ─────────────
class _PulsingLocationIndicator extends StatefulWidget {
  @override
  State<_PulsingLocationIndicator> createState() => _PulsingLocationIndicatorState();
}

class _PulsingLocationIndicatorState extends State<_PulsingLocationIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: false);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3).withValues(alpha: 0.3 * (1 - _animation.value)),
                border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.5 * (1 - _animation.value)), width: 2),
              ),
            ),
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3),
                border: Border.all(color: SojornColors.basicWhite, width: 3),
                boxShadow: [BoxShadow(color: const Color(0x4D000000), blurRadius: 4, spreadRadius: 1)],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Create Group inline form ─────────────────────────────────────────
class _CreateGroupInline extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateGroupInline({required this.onCreated});

  @override
  ConsumerState<_CreateGroupInline> createState() => _CreateGroupInlineState();
}

class _CreateGroupInlineState extends ConsumerState<_CreateGroupInline> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _privacy = false;
  group_models.GroupCategory _category = group_models.GroupCategory.general;
  bool _submitting = false;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.createGroup(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _category,
        isPrivate: _privacy,
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: SojornColors.basicBlack.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Create Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Group name',
                filled: true,
                fillColor: SojornColors.basicBlack.withValues(alpha: 0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: _descCtrl, maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                filled: true,
                fillColor: SojornColors.basicBlack.withValues(alpha: 0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Text('Visibility:', style: TextStyle(fontSize: 13, color: SojornColors.basicBlack.withValues(alpha: 0.6))),
            const SizedBox(width: 12),
            ChoiceChip(label: const Text('Public'), selected: !_privacy,
              onSelected: (_) => setState(() => _privacy = false),
              selectedColor: AppTheme.brightNavy.withValues(alpha: 0.15)),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Private'), selected: _privacy,
              onSelected: (_) => setState(() => _privacy = true),
              selectedColor: AppTheme.brightNavy.withValues(alpha: 0.15)),
          ]),
          const SizedBox(height: 14),
          Text('Category:', style: TextStyle(fontSize: 13, color: SojornColors.basicBlack.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: group_models.GroupCategory.values.map((cat) => ChoiceChip(
              label: Text(cat.displayName),
              selected: _category == cat,
              onSelected: (_) => setState(() => _category = cat),
              selectedColor: AppTheme.navyBlue,
              labelStyle: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: _category == cat ? Colors.white : Colors.black87,
              ),
              backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
              side: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navyBlue, foregroundColor: SojornColors.basicWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                  : const Text('Create Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Create Capsule inline form ───────────────────────────────────────
class _CreateCapsuleInline extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateCapsuleInline({required this.onCreated});

  @override
  State<_CreateCapsuleInline> createState() => _CreateCapsuleInlineState();
}

class _CreateCapsuleInlineState extends State<_CreateCapsuleInline> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;
  String? _statusMsg;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _submitting = true; _statusMsg = 'Generating encryption keys…'; });
    try {
      final capsuleKey = await CapsuleSecurityService.generateCapsuleKey();
      final publicKeyB64 = await CapsuleSecurityService.getUserPublicKeyB64();
      setState(() => _statusMsg = 'Encrypting group key…');
      final encryptedGroupKey = await CapsuleSecurityService.encryptCapsuleKeyForUser(
        capsuleKey: capsuleKey, recipientPublicKeyB64: publicKeyB64);
      setState(() => _statusMsg = 'Creating capsule…');
      final result = await ApiService.instance.createCapsule(
        name: _nameCtrl.text.trim(), description: _descCtrl.text.trim(),
        publicKey: publicKeyB64, encryptedGroupKey: encryptedGroupKey);
      final capsuleId = (result['capsule'] as Map<String, dynamic>?)?['id']?.toString();
      if (capsuleId != null) {
        await CapsuleSecurityService.cacheCapsuleKey(capsuleId, capsuleKey);
      }
      widget.onCreated();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
    if (mounted) setState(() { _submitting = false; _statusMsg = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.lock, color: Color(0xFF4CAF50), size: 20),
            const SizedBox(width: 8),
            Text('Create Private Capsule',
              style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('End-to-end encrypted. The server never sees your content.',
            style: TextStyle(fontSize: 12, color: SojornColors.textDisabled)),
          const SizedBox(height: 20),
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(color: SojornColors.postContent),
              decoration: InputDecoration(
                labelText: 'Capsule name',
                labelStyle: TextStyle(color: SojornColors.textDisabled),
                filled: true, fillColor: AppTheme.scaffoldBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: _descCtrl, maxLines: 2,
              style: TextStyle(color: SojornColors.postContent),
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: SojornColors.textDisabled),
                filled: true, fillColor: AppTheme.scaffoldBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              Icon(Icons.shield, size: 14, color: const Color(0xFF4CAF50).withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(child: Text('Keys are generated on your device. Only invited members can decrypt content.',
                style: TextStyle(fontSize: 11, color: SojornColors.postContentLight))),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50), foregroundColor: SojornColors.basicWhite,
                disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite)),
                      const SizedBox(width: 10),
                      Text(_statusMsg ?? 'Creating…', style: const TextStyle(fontSize: 13)),
                    ])
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.lock, size: 16),
                      SizedBox(width: 8),
                      Text('Generate Keys & Create', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── DMS Sign detail sheet ────────────────────────────────────────────
class _SignDetailSheet extends StatelessWidget {
  final Beacon sign;
  const _SignDetailSheet({required this.sign});

  static const _amber = Color(0xFFFFAB00);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad + 16, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.signpost, color: _amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Road Sign',
                      style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('MN DOT Electronic Sign',
                      style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: AppTheme.navyBlue.withValues(alpha: 0.35), size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.navyBlue.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          if (sign.imageUrl != null && sign.imageUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                '${ApiConfig.baseUrl}/api/v1/image-proxy?url=${Uri.encodeComponent(sign.imageUrl!)}',
                fit: BoxFit.contain,
                height: 140,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Text(sign.body,
              style: TextStyle(color: SojornColors.postContent, fontSize: 14)),
          ),
          const SizedBox(height: 8),
          Text(sign.getTimeAgo(),
            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── RWIS Weather station detail sheet ───────────────────────────────
class _WeatherDetailSheet extends StatelessWidget {
  final Beacon wx;
  const _WeatherDetailSheet({required this.wx});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final severityColor = wx.severity.color;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad + 16, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.cloud, color: severityColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weather Station',
                      style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('MN DOT RWIS Sensor',
                      style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: severityColor.withValues(alpha: 0.35)),
                ),
                child: Text(wx.severity.label.toUpperCase(),
                  style: TextStyle(color: severityColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: AppTheme.navyBlue.withValues(alpha: 0.35), size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.navyBlue.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Text(wx.body,
              style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 8),
          Text(wx.getTimeAgo(),
            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Beacon crowd-verification vote buttons
//
// Inspired by Ushahidi's incident verification UI. Turns every beacon from a
// passive one-way broadcast into a crowdsourced ground-truth signal.
//
// Three actions:
//   ✓ Confirm  — "I see this too"   → POST /beacons/:id/vouch
//   ✗ Not there — "Gone / wrong"    → POST /beacons/:id/report
//   + Context  — Add more detail    → opens a text sheet that appends a comment
//
// Vote state is optimistic — UI updates instantly, server sync happens async.
// ─────────────────────────────────────────────────────────────────────────────
class _BeaconVoteRow extends StatefulWidget {
  final Post post;
  final Beacon beacon;
  final dynamic apiService; // ApiService — avoid circular import by using dynamic

  const _BeaconVoteRow({
    required this.post,
    required this.beacon,
    required this.apiService,
  });

  @override
  State<_BeaconVoteRow> createState() => _BeaconVoteRowState();
}

class _BeaconVoteRowState extends State<_BeaconVoteRow> {
  late String? _myVote;         // 'vouch', 'report', or null
  late int _vouchCount;
  late int _reportCount;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _myVote = widget.beacon.userVote;
    _vouchCount = widget.beacon.vouchCount ?? 0;
    _reportCount = widget.beacon.reportCount ?? 0;
  }

  Future<void> _cast(String vote) async {
    if (_busy) return;
    final wasSameVote = _myVote == vote;

    // Optimistic update
    setState(() {
      _busy = true;
      if (wasSameVote) {
        // Toggle off
        if (vote == 'vouch') _vouchCount = (_vouchCount - 1).clamp(0, 9999);
        if (vote == 'report') _reportCount = (_reportCount - 1).clamp(0, 9999);
        _myVote = null;
      } else {
        // Switch or new vote
        if (_myVote == 'vouch') _vouchCount = (_vouchCount - 1).clamp(0, 9999);
        if (_myVote == 'report') _reportCount = (_reportCount - 1).clamp(0, 9999);
        if (vote == 'vouch') _vouchCount++;
        if (vote == 'report') _reportCount++;
        _myVote = vote;
      }
    });

    try {
      if (wasSameVote) {
        await widget.apiService.removeBeaconVote(widget.post.id);
      } else if (vote == 'vouch') {
        await widget.apiService.vouchBeacon(widget.post.id);
      } else {
        await widget.apiService.reportBeacon(widget.post.id);
      }
    } catch (_) {
      // Revert on failure
      if (mounted) {
        setState(() {
          _myVote = widget.beacon.userVote;
          _vouchCount = widget.beacon.vouchCount ?? 0;
          _reportCount = widget.beacon.reportCount ?? 0;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addContext() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add context', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue)),
              const SizedBox(height: 4),
              Text('Help neighbors understand this alert better.', style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.55))),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 280,
                decoration: const InputDecoration(hintText: 'What else should people know?'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    try {
                      // Post a reply chain on the beacon post with the context
                      await widget.apiService.createPost(body: text, chainParentId: widget.post.id, visibility: 'public');
                    } catch (_) {}
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.brightNavy),
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVouched   = _myVote == 'vouch';
    final isReported  = _myVote == 'report';

    return Row(
      children: [
        // Confirm button
        _VoteChip(
          label: _vouchCount > 0 ? 'Confirmed ($_vouchCount)' : 'Confirm',
          icon: Icons.check_circle_outline,
          activeIcon: Icons.check_circle,
          isActive: isVouched,
          activeColor: const Color(0xFF43A047),
          onTap: () => _cast('vouch'),
        ),
        const SizedBox(width: 6),
        // Not there button
        _VoteChip(
          label: 'Not there',
          icon: Icons.cancel_outlined,
          activeIcon: Icons.cancel,
          isActive: isReported,
          activeColor: SojornColors.destructive,
          onTap: () => _cast('report'),
        ),
        const SizedBox(width: 6),
        // Add context button
        _VoteChip(
          label: 'Add context',
          icon: Icons.add_comment_outlined,
          activeIcon: Icons.add_comment,
          isActive: false,
          activeColor: AppTheme.egyptianBlue,
          onTap: _addContext,
        ),
      ],
    );
  }
}

class _VoteChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _VoteChip({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.12) : AppTheme.scaffoldBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor.withValues(alpha: 0.5) : AppTheme.navyBlue.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 12,
              color: isActive ? activeColor : AppTheme.navyText.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : AppTheme.navyText.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

