import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
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
import 'create_beacon_sheet.dart';
import 'create_board_post_sheet.dart';
import 'board_entry_detail_screen.dart';
import '../clusters/group_screen.dart';
import '../clusters/group_chat_tab.dart';
import '../clusters/group_forum_tab.dart';
import '../clusters/group_members_tab.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';

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
  late final TabController _tabController;

  List<Post> _beacons = [];
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
  bool _isLoadingClusters = false;
  Map<String, String> _encryptedKeys = {};
  GroupCategory? _selectedGroupCategory;

  // Neighborhood detection state
  Map<String, dynamic>? _neighborhood;
  bool _isDetectingNeighborhood = false;
  bool _neighborhoodDetected = false;
  bool _homeNeighborhoodChecked = false;

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _activeTab = _tabOrder[_tabController.index]);
        if (_tabController.index == 1 && _boardEntries.isEmpty) _loadBoardEntries();
      }
    });
    _mapCenter = widget.initialMapCenter ?? const LatLng(37.7749, -122.4194);
    _suppressAutoCenterOnUser = widget.initialMapCenter != null;
    if (widget.initialMapCenter != null) {
      _loadBeacons(center: widget.initialMapCenter);
    }
    _checkLocationPermission();
    _loadClusters();
    _checkHomeNeighborhood();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;
    if (mounted) {
      setState(() => _locationPermissionGranted = status.isGranted);
      if (status.isGranted) {
        await _getCurrentLocation(forceCenter: !_suppressAutoCenterOnUser);
        await _loadBeacons();
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
    setState(() => _isLoadingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
          if (forceCenter || !_suppressAutoCenterOnUser) {
            _mapController.move(_userLocation!, _currentZoom);
            _suppressAutoCenterOnUser = false;
          }
        });
        // Fetch weather for current location
        _fetchWeather(position.latitude, position.longitude);
        // Detect neighborhood
        if (!_neighborhoodDetected) _detectNeighborhood(position.latitude, position.longitude);
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
    if (_isDetectingNeighborhood) return;
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
          if (name.isNotEmpty) {
            setState(() => _locationName = city.isNotEmpty ? '$name, $city' : name);
          }
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
  Future<void> _checkHomeNeighborhood() async {
    try {
      final mine = await ApiService.instance.getMyNeighborhood();
      if (mine != null && mounted) {
        final onboarded = mine['onboarded'] == true;
        final hasHood = mine['neighborhood'] != null;

        setState(() {
          _homeNeighborhoodChecked = true;
          if (hasHood) {
            _neighborhood = mine;
            _neighborhoodDetected = true;
          }
        });

        // If user hasn't completed onboarding, the picker will be shown
        // once GPS detection finishes (or immediately if GPS was already done)
        if (!onboarded && _neighborhoodDetected) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) _showNeighborhoodPicker();
          });
        }
      }
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
    }
  }

  Future<void> _loadBeacons({LatLng? center}) async {
    final target = center ?? _userLocation ?? _mapCenter;
    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final beacons = await apiService.fetchNearbyBeacons(
        lat: target.latitude,
        long: target.longitude,
        radius: 16000,
      );
      if (mounted) {
        setState(() {
          _beacons = beacons.where((p) => p.isBeaconPost).toList();
          _beaconModels = _beacons.map((p) => p.toBeacon()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClusters() async {
    setState(() => _isLoadingClusters = true);
    try {
      final groups = await ApiService.instance.fetchMyGroups();
      final allClusters = groups.map((g) => Cluster.fromJson(g)).toList();
      if (mounted) {
        setState(() {
          _clusters = allClusters;
          _encryptedKeys = {
            for (final g in groups)
              if ((g['encrypted_group_key'] as String?)?.isNotEmpty == true)
                g['id'] as String: g['encrypted_group_key'] as String,
          };
          _isLoadingClusters = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Beacon] Clusters load error: $e');
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
    if (hasGesture) _loadBeacons(center: _mapCenter);
  }

  void _onMarkerTap(Post post) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => BeaconDetailScreen(beaconPost: post),
    ));
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
          setState(() => _beacons.add(post));
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
      }
    } catch (e) {
      if (kDebugMode) print('[Board] Load error: $e');
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
    if (_neighborhood == null) return 'Neighborhood';
    final direct = _neighborhood!['name'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = _neighborhood!['neighborhood'] as Map<String, dynamic>?;
    final nestedName = nested?['name'] as String?;
    return (nestedName != null && nestedName.isNotEmpty) ? nestedName : 'Neighborhood';
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

    return Column(
      children: [
        // Top tab bar
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
              Tab(text: 'Board', icon: Icon(Icons.forum_outlined, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(text: 'Groups', icon: Icon(Icons.groups_outlined, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(text: 'Search', icon: Icon(Icons.search, size: SojornNav.beaconTabIconSize), iconMargin: EdgeInsets.only(bottom: 2)),
            ],
          ),
        ),
        // Content
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
  }

  // ─── Map tab (map + overlay + draggable sheet) ────────────────────────
  Widget _buildMapTab() {
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
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(child: _buildDragHandle()),
                  SliverToBoxAdapter(
                    child: ActiveAlertsTicker(alerts: _beaconModels, onAlertTap: _onBeaconModelTap),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: AppTheme.navyBlue.withValues(alpha: 0.1))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('ALL INCIDENTS', style: TextStyle(
                              color: AppTheme.navyBlue.withValues(alpha: 0.35),
                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                            )),
                          ),
                          Expanded(child: Divider(color: AppTheme.navyBlue.withValues(alpha: 0.1))),
                        ],
                      ),
                    ),
                  ),
                  if (_beacons.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Column(children: [
                          Icon(Icons.shield, color: AppTheme.brightNavy.withValues(alpha: 0.3), size: 48),
                          const SizedBox(height: 12),
                          Text('All clear in your area',
                            style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.5), fontSize: 14)),
                        ])),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildIncidentCard(_beacons[index]),
                        childCount: _beacons.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            );
          },
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
          // Weather chip (far left)
          if (_weather != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SojornColors.basicWhite.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: SojornColors.basicBlack.withValues(alpha: 0.1), blurRadius: 6)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_weatherIcon(_weather!.weatherCode), size: 16, color: AppTheme.navyBlue),
                  const SizedBox(width: 4),
                  Text('${_weather!.temperature.round()}°',
                    style: TextStyle(color: AppTheme.navyBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const Spacer(),
          // My location button
          _mapIconButton(Icons.my_location,
            onTap: _isLoadingLocation ? null : () => _getCurrentLocation(forceCenter: true)),
          const SizedBox(width: 8),
          // Refresh button
          _mapIconButton(Icons.refresh, onTap: () => _loadBeacons()),
        ],
      ),
    );
  }

  Widget _mapIconButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: SojornColors.basicWhite.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: SojornColors.basicBlack.withValues(alpha: 0.1), blurRadius: 6)],
        ),
        child: Icon(icon, size: 18, color: AppTheme.navyBlue.withValues(alpha: 0.7)),
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
                      onPressed: _showNeighborhoodPicker,
                      icon: Icon(Icons.tune, size: 18, color: SojornColors.textDisabled),
                      tooltip: 'Neighborhood settings',
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
                        child: _buildHubSegment(
                          label: 'Feed',
                          icon: Icons.rss_feed,
                          selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.feed,
                          onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.feed),
                        ),
                      ),
                      Expanded(
                        child: _buildHubSegment(
                          label: 'Chat',
                          icon: Icons.chat_bubble_outline,
                          badgeCount: _chatActivityCount,
                          selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.chat,
                          onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.chat),
                        ),
                      ),
                      Expanded(
                        child: _buildHubSegment(
                          label: 'Forum',
                          icon: Icons.forum_outlined,
                          badgeCount: _forumActivityCount,
                          selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.forum,
                          onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.forum),
                        ),
                      ),
                      Expanded(
                        child: _buildHubSegment(
                          label: 'Members',
                          icon: Icons.groups_2_outlined,
                          selected: _activeNeighborhoodHubTab == NeighborhoodHubTab.members,
                          onTap: () => setState(() => _activeNeighborhoodHubTab = NeighborhoodHubTab.members),
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
        final updated = await Navigator.of(context).push<BoardEntry>(
          MaterialPageRoute(builder: (_) => BoardEntryDetailScreen(entry: entry)),
        );
        if (updated != null && mounted) {
          setState(() {
            final idx = _boardEntries.indexWhere((e) => e.id == updated.id);
            if (idx >= 0) _boardEntries[idx] = updated;
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
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BoardEntryDetailScreen(entry: entry),
          ));
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
        subtitle: Text('${g['member_count'] ?? 0} members · ${g['type'] ?? ''}',
          style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
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
                      _buildGroupCategoryChip(null, 'All', Icons.grid_view, AppTheme.brightNavy),
                      const SizedBox(width: 6),
                      ...GroupCategory.values.map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildGroupCategoryChip(cat, cat.displayName, cat.icon, cat.color),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingClusters
                ? const Center(child: CircularProgressIndicator())
                : _clusters.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.group_add, color: AppTheme.navyBlue.withValues(alpha: 0.2), size: 48),
                            const SizedBox(height: 12),
                            Text('No groups yet', style: TextStyle(
                              color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Create or join a group to get started',
                              style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _showCreateGroupSheet,
                                  icon: const Icon(Icons.location_on, size: 16),
                                  label: const Text('New Group'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.brightNavy,
                                    side: BorderSide(color: AppTheme.brightNavy.withValues(alpha: 0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: _showCreateCapsuleSheet,
                                  icon: const Icon(Icons.lock, size: 16),
                                  label: const Text('New Capsule'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF4CAF50),
                                    side: BorderSide(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadClusters,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          children: [
                            if (neighborhoods.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                                child: Text('NEIGHBORHOODS', style: TextStyle(
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
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCategoryChip(GroupCategory? category, String label, IconData icon, Color color) {
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
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isCapsule ? capsuleGreen.withValues(alpha: 0.1) : AppTheme.brightNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCapsule ? Icons.lock : Icons.location_on,
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
    return GestureDetector(
      onTap: () {
        final currentSize = _sheetController.size;
        if (currentSize < 0.3) {
          _sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        } else {
          _sheetController.animateTo(0.15, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.radar, color: AppTheme.brightNavy.withValues(alpha: 0.6), size: 16),
                const SizedBox(width: 6),
                Text(
                  'RADAR',
                  style: TextStyle(
                    color: AppTheme.navyBlue.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_beaconModels.where((b) => b.beaconType.isGeoAlert).length} alerts',
                  style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.4), fontSize: 11),
                ),
                Icon(Icons.keyboard_arrow_up, color: AppTheme.navyBlue.withValues(alpha: 0.3), size: 18),
              ],
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

    return GestureDetector(
      onTap: () => _onMarkerTap(post),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRecent ? severityColor.withValues(alpha: 0.5) : AppTheme.navyBlue.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(beacon.beaconType.icon, color: severityColor, size: 22),
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
                      if (isRecent)
                        Container(
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
                  Text(beacon.body, maxLines: 1, overflow: TextOverflow.ellipsis,
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
                      Icon(Icons.visibility, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('${beacon.verificationCount}', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                    ],
                  ),
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
        MarkerLayer(
          markers: [
            // Only geo-alert beacons on the map (not discussions)
            ..._beacons
                .where((p) => p.beaconType?.isGeoAlert ?? false)
                .map((beacon) => _createMarker(beacon)),
            if (_locationPermissionGranted && _userLocation != null)
              _createUserLocationMarker(),
          ],
        ),
      ],
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

  Marker _createMarker(Post post) {
    final beacon = post.toBeacon();
    final severityColor = beacon.pinColor;
    final typeIcon = beacon.beaconType.icon;
    final isRecent = beacon.isRecent;

    final fallbackBase = _userLocation ?? _mapCenter;
    final markerPosition = (post.latitude != null && post.longitude != null)
        ? LatLng(post.latitude!, post.longitude!)
        : LatLng(
            fallbackBase.latitude + ((post.distanceMeters ?? 0) / 111000),
            fallbackBase.longitude + ((post.distanceMeters ?? 0) / 111000),
          );

    return Marker(
      point: markerPosition,
      width: 48,
      height: 48,
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

// ─── Severity-colored Marker with pulse for recent ─────────────
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    if (widget.isRecent) {
      _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
      _controller.repeat(reverse: true);
    } else {
      _pulseAnimation = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: widget.isRecent ? 0.6 : 0.3),
                  blurRadius: widget.isRecent ? 12 : 6,
                  spreadRadius: widget.isRecent ? 3 : 0,
                ),
              ],
            ),
            child: Icon(widget.icon, color: SojornColors.basicWhite, size: 26),
          ),
        );
      },
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
