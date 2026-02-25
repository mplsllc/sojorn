// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.


import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/board_entry.dart';
import '../../models/group.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';
import '../../widgets/composer/composer_bar.dart';
import '../beacon/board_entry_detail_screen.dart';
import '../beacon/create_board_post_sheet.dart';
import '../clusters/group_chat_tab.dart';
import '../clusters/group_events_tab.dart';

/// Standalone desktop screen for the Neighborhood hub.
///
/// Desktop: hero banner + tab bar + two-column (tab content | sidebar).
/// Mobile: hero banner + pinned tab bar + swipeable tab content.
class NeighborhoodScreen extends StatefulWidget {
  const NeighborhoodScreen({super.key});

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

class _NeighborhoodScreenState extends State<NeighborhoodScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _neighborhood;
  List<BoardEntry> _boardEntries = [];
  bool _isLoading = true;
  bool _isLoadingBoard = false;
  bool _isNeighborhoodAdmin = false;
  String _boardSort = 'new';
  double _lat = 44.9778;
  double _lng = -93.2650;

  // Inline composer topic selection (separate from filter)
  BoardTopic _composeTopic = BoardTopic.community;

  // Precomputed sidebar stats
  Map<BoardTopic, int> _topicCounts = {};

  // Members preview for sidebar (first 8)
  List<Map<String, dynamic>> _sidebarMembers = [];

  // Tab controller
  late TabController _tabController;
  int _currentTab = 0;

  // Forum state
  BoardTopic? _forumActiveTopic;
  List<BoardEntry> _forumEntries = [];
  bool _isLoadingForum = false;

  // Members tab state
  List<Map<String, dynamic>> _allMembers = [];
  bool _isLoadingMembers = false;
  String _memberFilter = 'all';
  String? _currentUserId;
  String? _myMemberRole;

  // Role resolution
  String _resolvedRole = 'visitor'; // exile|admin|moderator|resident|visitor

  // FAB animation
  late AnimationController _fabAnimController;
  late Animation<double> _fabAnimation;

  // Topic descriptions for forum directory
  static const _topicDescriptions = {
    BoardTopic.community: 'General neighborhood discussion',
    BoardTopic.question: 'Ask your neighbors anything',
    BoardTopic.event: 'Plans, meetups, and happenings',
    BoardTopic.lostPet: 'Lost & found pets in the area',
    BoardTopic.resource: 'Shared resources and mutual aid',
    BoardTopic.recommendation: 'Trusted local picks and referrals',
    BoardTopic.warning: 'Alerts and safety conversations',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _currentUserId = AuthService.instance.currentUser?.id;

    _fabAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.easeInOut,
    );

    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() => _currentTab = _tabController.index);
      // Animate FAB: show on Feed (0), hide on others
      if (_tabController.index == 0) {
        _fabAnimController.forward();
      } else {
        _fabAnimController.reverse();
      }
      // Lazy-load members tab
      if (_tabController.index == 4 && _allMembers.isEmpty && !_isLoadingMembers) {
        _loadMembers();
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROLE RESOLUTION
  // ══════════════════════════════════════════════════════════════════════════

  void _resolveRole() {
    final role = _neighborhood?['role'] as String?;
    final exileStatus = _neighborhood?['exile_status'] as String?;

    if (exileStatus == 'active') {
      _resolvedRole = 'exile';
    } else if (role == 'admin' || role == 'owner') {
      _resolvedRole = 'admin';
    } else if (role == 'moderator') {
      _resolvedRole = 'moderator';
    } else if (role == 'member') {
      _resolvedRole = 'resident';
    } else {
      _resolvedRole = 'visitor';
    }
  }

  bool get _canPost => _resolvedRole != 'exile';
  bool get _canCreateForumThread =>
      _resolvedRole == 'resident' ||
      _resolvedRole == 'moderator' ||
      _resolvedRole == 'admin';
  bool get _isAdmin =>
      _resolvedRole == 'admin' || _resolvedRole == 'moderator';
  bool get _isVisitor => _resolvedRole == 'visitor';

  // ══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ══════════════════════════════════════════════════════════════════════════

  void _recomputeStats() {
    _topicCounts = {};
    for (final e in _boardEntries) {
      _topicCounts[e.topic] = (_topicCounts[e.topic] ?? 0) + 1;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final hood = await ApiService.instance.getMyNeighborhood();
      final isOnboarded = hood?['onboarded'] == true;
      final hoodData = hood?['neighborhood'] as Map<String, dynamic>?;
      final hoodName = hoodData?['name'] as String?;

      if (!isOnboarded || hoodName == null || hoodName.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          await _showSetupPicker();
          return;
        }
        return;
      }

      final hoodLat = (hoodData?['lat'] as num?)?.toDouble();
      final hoodLng = (hoodData?['lng'] as num?)?.toDouble();
      if (hoodLat != null && hoodLng != null) {
        _lat = hoodLat;
        _lng = hoodLng;
      }

      if (mounted) {
        setState(() => _neighborhood = hood);
        _resolveRole();
      }
      await _fetchBoardEntries(_lat, _lng);

      // Load member previews for sidebar
      final groupId = hoodData?['group_id'] as String?;
      if (groupId != null) {
        try {
          final members =
              await ApiService.instance.fetchGroupMembers(groupId);
          if (mounted) {
            setState(() => _sidebarMembers = members.take(8).toList());
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NEIGHBORHOOD] Load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    _tryRefineWithGps();
  }

  Future<void> _showSetupPicker() async {
    if (!mounted) return;
    final result =
        await NeighborhoodPickerSheet.show(context, isChangeMode: false);
    if (result != null && mounted) {
      _loadData();
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _tryRefineWithGps() async {
    if (kIsWeb) return;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final dist = Geolocator.distanceBetween(
          _lat, _lng, pos.latitude, pos.longitude);
      if (dist > 500 && mounted) {
        _lat = pos.latitude;
        _lng = pos.longitude;
        await _fetchBoardEntries(_lat, _lng);
      }
    } catch (_) {}
  }

  Future<void> _fetchBoardEntries(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _isLoadingBoard = true);
    try {
      final data = await ApiService.instance.fetchBoardEntries(
        lat: lat,
        long: lng,
        radius: 8000,
        sort: _boardSort,
      );
      final entries = (data['entries'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map((e) => BoardEntry.fromJson(e))
              .toList() ??
          [];
      final isAdmin = data['is_neighborhood_admin'] == true;
      if (mounted) {
        setState(() {
          _boardEntries = entries;
          _isNeighborhoodAdmin = isAdmin;
          _recomputeStats();
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NEIGHBORHOOD] Board load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBoard = false);
    }
  }

  Future<void> _reloadBoard() => _fetchBoardEntries(_lat, _lng);

  Future<void> _loadMembers() async {
    final groupId = _getGroupId();
    if (groupId == null) return;
    setState(() => _isLoadingMembers = true);
    try {
      _allMembers = await ApiService.instance.fetchGroupMembers(groupId);
      // Find my role
      for (final m in _allMembers) {
        if (m['user_id']?.toString() == _currentUserId) {
          _myMemberRole = m['role'] as String?;
          break;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NEIGHBORHOOD] Members load failed: $e');
    }
    if (mounted) setState(() => _isLoadingMembers = false);
  }

  Future<void> _loadForumEntries(BoardTopic topic) async {
    setState(() => _isLoadingForum = true);
    try {
      final data = await ApiService.instance.fetchBoardEntries(
        lat: _lat,
        long: _lng,
        radius: 8000,
        topic: topic.value,
        sort: 'new',
      );
      final entries = (data['entries'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map((e) => BoardEntry.fromJson(e))
              .toList() ??
          [];
      if (mounted) setState(() => _forumEntries = entries);
    } catch (e) {
      if (kDebugMode) debugPrint('[NEIGHBORHOOD] Forum load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingForum = false);
    }
  }

  String? _getGroupId() {
    final hoodData =
        _neighborhood?['neighborhood'] as Map<String, dynamic>?;
    return hoodData?['group_id'] as String?;
  }

  GroupRole? _getMappedRole() {
    // In neighborhoods, residents can create events (broader than groups)
    if (_resolvedRole == 'admin' || _resolvedRole == 'moderator' || _resolvedRole == 'resident') {
      return GroupRole.admin;
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_neighborhood == null) {
      return const Scaffold(body: Center(child: Text('No neighborhood')));
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (SojornBreakpoints.isDesktop(constraints.maxWidth)) {
        return _buildDesktopLayout(constraints.maxWidth);
      }
      return _buildMobileLayout();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout(double totalWidth) {
    final hood = _neighborhood;
    final hoodData = hood?['neighborhood'] as Map<String, dynamic>?;
    final name = hoodData?['name'] as String? ?? 'Commons';
    final city = hoodData?['city'] as String? ?? '';
    final memberCount = hood?['member_count'] as int? ?? 0;
    final activeNow = hood?['active_now'] as int? ?? 0;
    final showSidebar = _currentTab != 1; // Hide sidebar on Chat tab

    final tabBar = TabBar(
      controller: _tabController,
      indicatorColor: AppTheme.brightNavy,
      labelColor: AppTheme.navyText,
      unselectedLabelColor: SojornColors.textDisabled,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(icon: Icon(Icons.dynamic_feed, size: 18), text: 'Feed'),
        Tab(icon: Icon(Icons.chat_bubble, size: 18), text: 'Chat'),
        Tab(icon: Icon(Icons.forum, size: 18), text: 'Forum'),
        Tab(icon: Icon(Icons.event, size: 18), text: 'Events'),
        Tab(icon: Icon(Icons.people, size: 18), text: 'Members'),
      ],
    );

    return Container(
      color: AppTheme.scaffoldBg,
      child: Column(
        children: [
          _buildHeroBanner(name, city, memberCount, activeNow),
          Container(
            color: AppTheme.cardSurface,
            child: tabBar,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFeedTab(),
                      _buildChatTab(),
                      _buildForumTab(),
                      _buildEventsTab(),
                      _buildMembersTab(),
                    ],
                  ),
                ),
                if (showSidebar)
                  SizedBox(
                    width: (totalWidth * 0.24).clamp(240.0, 300.0),
                    child: _buildRightSidebar(activeNow, memberCount),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout() {
    final hoodData =
        _neighborhood?['neighborhood'] as Map<String, dynamic>?;
    final name = hoodData?['name'] as String? ?? 'Commons';
    final city = hoodData?['city'] as String? ?? '';
    final memberCount = _neighborhood?['member_count'] as int? ?? 0;
    final activeNow = _neighborhood?['active_now'] as int? ?? 0;

    final tabBar = TabBar(
      controller: _tabController,
      indicatorColor: AppTheme.brightNavy,
      labelColor: AppTheme.navyText,
      unselectedLabelColor: SojornColors.textDisabled,
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(icon: Icon(Icons.dynamic_feed, size: 16), text: 'Feed'),
        Tab(icon: Icon(Icons.chat_bubble, size: 16), text: 'Chat'),
        Tab(icon: Icon(Icons.forum, size: 16), text: 'Forum'),
        Tab(icon: Icon(Icons.event, size: 16), text: 'Events'),
        Tab(icon: Icon(Icons.people, size: 16), text: 'Members'),
      ],
    );

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: _buildHeroBanner(name, city, memberCount, activeNow,
                compact: true),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(tabBar),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildFeedTab(),
            _buildChatTab(),
            _buildForumTab(),
            _buildEventsTab(),
            _buildMembersTab(),
          ],
        ),
      ),
      floatingActionButton: _canPost && !_isVisitor
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton(
                onPressed: _openCreatePost,
                backgroundColor: AppTheme.brightNavy,
                child: const Icon(Icons.edit, color: Colors.white),
              ),
            )
          : null,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HERO BANNER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildHeroBanner(String name, String city, int memberCount,
      int activeNow,
      {bool compact = false}) {
    final bannerUrl = (_neighborhood?['neighborhood']
        as Map<String, dynamic>?)?['banner_url'] as String?;
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;
    final height = compact ? 160.0 : 220.0;

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            if (hasBanner)
              Image.network(bannerUrl, fit: BoxFit.cover)
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.brightNavy,
                      AppTheme.royalPurple.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            // Dark overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5)
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            // Info overlay
            Positioned(
              bottom: 20,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_city,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (city.isNotEmpty)
                              Text(city,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white
                                          .withValues(alpha: 0.8))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.people,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 5),
                      Text('$memberCount members',
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text('$activeNow online',
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _resolvedRole == 'admin'
                              ? 'Admin'
                              : _resolvedRole == 'moderator'
                                  ? 'Moderator'
                                  : _resolvedRole == 'visitor'
                                      ? 'Visitor'
                                      : 'Resident',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Visitor hint
                  if (_isVisitor) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "You're visiting — join to participate fully",
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ),
                  ],
                  // Exile banner
                  if (_resolvedRole == 'exile') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "You've been exiled from this neighborhood",
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.95)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Admin: Edit Banner
            if (_isAdmin)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    // TODO: admin banner upload
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.9)),
                        const SizedBox(width: 5),
                        Text('Edit Banner',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white
                                    .withValues(alpha: 0.9))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FEED TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFeedTab() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: SojornBreakpoints.maxContentWidth + 32), // 640 + padding
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Exile banner
          if (_resolvedRole == 'exile')
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SojornColors.destructive.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(SojornRadii.md),
                border: Border.all(
                    color: SojornColors.destructive.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, size: 16, color: SojornColors.destructive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have been exiled from this neighborhood. You can browse but not post.',
                      style: TextStyle(
                          fontSize: 12, color: SojornColors.destructive),
                    ),
                  ),
                ],
              ),
            ),
          // Inline composer — available to visitor+ (not exile)
          if (_canPost) _buildInlineComposer(),
          // Board header (sort + chips)
          _buildBoardHeader(),
          // Board entries
          _buildBoardEntries(),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildInlineComposer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border:
            Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic selector chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: BoardTopic.values.map((t) {
                final isSelected = t == _composeTopic;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon,
                            size: 12,
                            color: isSelected
                                ? Colors.white
                                : SojornColors.textDisabled),
                        const SizedBox(width: 4),
                        Text(t.displayName),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _composeTopic = t),
                    selectedColor: t.color,
                    backgroundColor: AppTheme.cardSurface,
                    labelStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? Colors.white
                          : SojornColors.postContentLight,
                    ),
                    side: BorderSide(
                      color: isSelected ? t.color : AppTheme.navyText.withValues(alpha: 0.15),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          ComposerBar(
            config: const ComposerConfig(
              allowImages: true,
              hintText: 'Share with your neighborhood\u2026',
            ),
            onSend: _onBoardComposerSend,
          ),
          // Visitor badge hint
          if (_isVisitor)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Posts will be tagged as "Visiting"',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.brightNavy.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onBoardComposerSend(String text, String? imageUrl) async {
    final data = await ApiService.instance.createBoardEntry(
      body: text,
      imageUrl: imageUrl,
      topic: _composeTopic.value,
      lat: _lat,
      long: _lng,
    );
    if (mounted) {
      final entry =
          BoardEntry.fromJson(data['entry'] as Map<String, dynamic>);
      setState(() {
        _boardEntries.insert(0, entry);
        _recomputeStats();
      });
      context.showSuccess('Posted to board!');
    }
  }

  Widget _buildBoardHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _boardSort,
                  isDense: true,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.navyText),
                  items: const [
                    DropdownMenuItem(
                        value: 'new', child: Text('New')),
                    DropdownMenuItem(
                        value: 'top', child: Text('Top')),
                    DropdownMenuItem(
                        value: 'hot', child: Text('Hot')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _boardSort = val);
                      _reloadBoard();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Divider(
            height: 1,
            color: AppTheme.navyText.withValues(alpha: 0.08)),
      ],
    );
  }

  Widget _buildBoardEntries() {
    if (_isLoadingBoard && _boardEntries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_boardEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined,
                  size: 48,
                  color: AppTheme.navyText.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text('No posts yet',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          AppTheme.navyText.withValues(alpha: 0.4))),
              const SizedBox(height: 4),
              Text('Be the first to post in your neighborhood',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.navyText
                          .withValues(alpha: 0.35))),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        children: _boardEntries
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildBoardCard(entry),
                ))
            .toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT TAB (placeholder)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChatTab() {
    final groupId = _getGroupId();
    if (groupId == null) {
      return Center(
        child: Text('No group linked',
            style: TextStyle(color: SojornColors.textDisabled)),
      );
    }
    return GroupChatTab(
      groupId: groupId,
      currentUserId: _currentUserId,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORUM TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildForumTab() {
    if (_forumActiveTopic == null) {
      return _buildForumDirectory();
    }
    return _buildForumThreadList();
  }

  Widget _buildForumDirectory() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: BoardTopic.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final topic = BoardTopic.values[i];
        final count = _topicCounts[topic] ?? 0;
        final desc = _topicDescriptions[topic] ?? '';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _forumActiveTopic = topic);
            _loadForumEntries(topic);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: topic.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(topic.icon,
                      size: 22, color: topic.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.displayName,
                        style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(
                          color: SojornColors.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: topic.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 18, color: SojornColors.textDisabled),
              ],
            ),
          ),
        );
      },
    );
  }

  String _threadTitle(BoardEntry e) {
    final body = e.body;
    if (body.startsWith('## ')) return body.substring(3).split('\n').first;
    return body.length > 80 ? '${body.substring(0, 80)}\u2026' : body;
  }

  Widget _buildForumThreadList() {
    final topic = _forumActiveTopic!;

    // Sort pinned first
    final pinned = _forumEntries.where((e) => e.isPinned).toList();
    final unpinned = _forumEntries.where((e) => !e.isPinned).toList();
    final sorted = [...pinned, ...unpinned];

    return Column(
      children: [
        // Header: back + topic + new thread
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: AppTheme.cardSurface,
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() {
                  _forumActiveTopic = null;
                  _forumEntries = [];
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back,
                          size: 15,
                          color: SojornColors.textDisabled),
                      const SizedBox(width: 6),
                      Text('Categories',
                          style: TextStyle(
                            color: SojornColors.textDisabled,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: topic.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(topic.icon, size: 14, color: topic.color),
                    const SizedBox(width: 4),
                    Text(
                      topic.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: topic.color,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_canCreateForumThread)
                TextButton.icon(
                  onPressed: () => _showForumComposer(topic),
                  icon: Icon(Icons.add,
                      size: 16, color: AppTheme.brightNavy),
                  label: Text('New Thread',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.brightNavy,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        // Thread list
        Expanded(
          child: _isLoadingForum
              ? const Center(child: CircularProgressIndicator())
              : sorted.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum,
                              size: 48,
                              color: AppTheme.navyBlue
                                  .withValues(alpha: 0.15)),
                          const SizedBox(height: 12),
                          Text('No threads yet',
                              style: TextStyle(
                                  color:
                                      SojornColors.postContentLight,
                                  fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                              'Start a thread to get the conversation going',
                              style: TextStyle(
                                  color: SojornColors.textDisabled,
                                  fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadForumEntries(topic),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            12, 8, 12, 80),
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) => Divider(
                            color: AppTheme.navyBlue
                                .withValues(alpha: 0.06),
                            height: 1),
                        itemBuilder: (_, i) {
                          final entry = sorted[i];
                          final title = _threadTitle(entry);
                          final authorName =
                              entry.authorDisplayName.isNotEmpty
                                  ? entry.authorDisplayName
                                  : entry.authorHandle;
                          return ListTile(
                            onTap: () => _openBoardEntry(entry),
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                            title: Row(
                              children: [
                                if (entry.isPinned) ...[
                                  Icon(Icons.push_pin,
                                      size: 14,
                                      color:
                                          AppTheme.brightNavy),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(title,
                                      style: TextStyle(
                                          color:
                                              AppTheme.navyBlue,
                                          fontWeight:
                                              FontWeight.w600,
                                          fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow
                                          .ellipsis),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding:
                                  const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Text(authorName,
                                      style: TextStyle(
                                          color: AppTheme
                                              .brightNavy,
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.w500)),
                                  const SizedBox(width: 8),
                                  Icon(
                                      Icons
                                          .chat_bubble_outline,
                                      size: 12,
                                      color: SojornColors
                                          .textDisabled),
                                  const SizedBox(width: 3),
                                  Text(
                                      '${entry.replyCount}',
                                      style: TextStyle(
                                          color: SojornColors
                                              .textDisabled,
                                          fontSize: 11)),
                                  const SizedBox(width: 8),
                                  Text(entry.getTimeAgo(),
                                      style: TextStyle(
                                          color: SojornColors
                                              .textDisabled,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                            trailing: Icon(
                                Icons.chevron_right,
                                size: 18,
                                color:
                                    SojornColors.textDisabled),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  void _showForumComposer(BoardTopic topic) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.navyBlue
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text('New Thread',
                style: TextStyle(
                    color: AppTheme.navyBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // Locked topic chip
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: topic.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(topic.icon, size: 14, color: topic.color),
                  const SizedBox(width: 4),
                  Text(
                    'Posting in ${topic.displayName}',
                    style: TextStyle(
                      color: topic.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: TextStyle(
                  color: SojornColors.postContent, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Thread title',
                hintStyle:
                    TextStyle(color: SojornColors.textDisabled),
                filled: true,
                fillColor: AppTheme.scaffoldBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              style: TextStyle(
                  color: SojornColors.postContent, fontSize: 14),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'What do you want to discuss?',
                hintStyle:
                    TextStyle(color: SojornColors.textDisabled),
                filled: true,
                fillColor: AppTheme.scaffoldBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(ctx);
                  // Use ## prefix interim until backend title column
                  final body = bodyCtrl.text.trim();
                  final fullBody = '## $title\n$body';
                  try {
                    final data =
                        await ApiService.instance.createBoardEntry(
                      body: fullBody,
                      topic: topic.value,
                      lat: _lat,
                      long: _lng,
                    );
                    if (mounted) {
                      final entry = BoardEntry.fromJson(
                          data['entry'] as Map<String, dynamic>);
                      setState(() {
                        _forumEntries.insert(0, entry);
                        _boardEntries.insert(0, entry);
                        _recomputeStats();
                      });
                      context.showSuccess('Thread created!');
                    }
                  } catch (e) {
                    if (mounted) {
                      context.showError('Failed to create thread');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Create Thread',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EVENTS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEventsTab() {
    final groupId = _getGroupId();
    if (groupId == null) {
      return Center(
        child: Text('No group linked',
            style: TextStyle(color: SojornColors.textDisabled)),
      );
    }
    return GroupEventsTab(
      groupId: groupId,
      userRole: _getMappedRole(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MEMBERS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMembersTab() {
    if (_isLoadingMembers && _allMembers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filters = [
      'all', 'admin', 'moderator', 'contributor', 'member', 'visitor',
    ];
    final filterLabels = {
      'all': 'All',
      'admin': 'Admin',
      'moderator': 'Moderator',
      'contributor': 'Contributor',
      'member': 'Resident',
      'visitor': 'Visitor',
    };
    final emptyMessages = {
      'all': 'No members yet',
      'admin': 'No admins',
      'moderator': 'No moderators',
      'contributor': 'No contributors yet',
      'member': 'No residents yet',
      'visitor': 'No visitors yet',
    };

    final filtered = _memberFilter == 'all'
        ? _allMembers
        : _allMembers
            .where((m) => m['role'] == _memberFilter)
            .toList();

    return Column(
      children: [
        // Filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: filters.map((f) {
              final isSelected = _memberFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(filterLabels[f] ?? f,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500)),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => _memberFilter = f),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),
        // Member list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(emptyMessages[_memberFilter] ?? 'No members found',
                      style: TextStyle(
                          color: SojornColors.textDisabled)))
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final m = filtered[i];
                      final handle =
                          m['handle'] as String? ?? '';
                      final displayName =
                          m['display_name'] as String? ?? handle;
                      final avatarUrl =
                          m['avatar_url'] as String? ?? '';
                      final role =
                          m['role'] as String? ?? 'member';
                      final isMe = m['user_id']?.toString() ==
                          _currentUserId;
                      final canManage = _myMemberRole == 'owner' ||
                          _myMemberRole == 'admin';

                      return ListTile(
                        onLongPress: canManage && !isMe
                            ? () => _showMemberActions(m)
                            : null,
                        onTap: canManage && !isMe
                            ? () => _showMemberActions(m)
                            : null,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                        leading: SojornAvatar(
                          displayName: displayName.isNotEmpty
                              ? displayName
                              : handle,
                          avatarUrl: avatarUrl.isNotEmpty
                              ? avatarUrl
                              : null,
                          size: 40,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName
                                    : handle,
                                style: TextStyle(
                                    color: AppTheme.navyBlue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Text('(you)',
                                  style: TextStyle(
                                      color: SojornColors
                                          .textDisabled,
                                      fontSize: 11)),
                            ],
                          ],
                        ),
                        subtitle: Text('@$handle',
                            style: TextStyle(
                                color:
                                    SojornColors.textDisabled,
                                fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _roleColor(role)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: Text(
                            _roleName(role),
                            style: TextStyle(
                                color: _roleColor(role),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'owner':
        return const Color(0xFFFFA726);
      case 'admin':
        return AppTheme.brightNavy;
      case 'moderator':
        return const Color(0xFF4CAF50);
      default:
        return SojornColors.textDisabled;
    }
  }

  String _roleName(String role) {
    switch (role) {
      case 'owner':
        return 'OWNER';
      case 'admin':
        return 'ADMIN';
      case 'moderator':
        return 'MOD';
      case 'member':
        return 'RESIDENT';
      default:
        return role.toUpperCase();
    }
  }

  void _showMemberActions(Map<String, dynamic> member) {
    final memberId = member['user_id']?.toString() ?? '';
    final memberRole = member['role'] as String? ?? 'member';
    final handle = member['handle'] as String? ?? '';

    if (memberId == _currentUserId) return;
    if (memberRole == 'owner') return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.navyBlue
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text('@$handle',
                  style: TextStyle(
                      color: AppTheme.navyBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (_myMemberRole == 'owner') ...[
                if (memberRole != 'admin')
                  _buildActionTile(
                      Icons.arrow_upward, 'Promote to Admin',
                      AppTheme.brightNavy, () async {
                    Navigator.pop(ctx);
                    final groupId = _getGroupId();
                    if (groupId == null) return;
                    await ApiService.instance.updateMemberRole(
                        groupId, memberId,
                        role: 'admin');
                    _loadMembers();
                  }),
                if (memberRole == 'admin')
                  _buildActionTile(
                      Icons.arrow_downward, 'Demote to Member',
                      AppTheme.brightNavy, () async {
                    Navigator.pop(ctx);
                    final groupId = _getGroupId();
                    if (groupId == null) return;
                    await ApiService.instance.updateMemberRole(
                        groupId, memberId,
                        role: 'member');
                    _loadMembers();
                  }),
                const SizedBox(height: 4),
              ],
              _buildActionTile(
                  Icons.person_remove,
                  'Remove from Neighborhood',
                  SojornColors.destructive, () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Remove Member'),
                    content: Text(
                        'Remove @$handle from this neighborhood?'),
                    actions: [
                      TextButton(
                          onPressed: () =>
                              Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(c, true),
                        child: Text('Remove',
                            style: TextStyle(
                                color:
                                    SojornColors.destructive)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    final groupId = _getGroupId();
                    if (groupId == null) return;
                    await ApiService.instance
                        .removeGroupMember(groupId, memberId);
                    _loadMembers();
                  } catch (e) {
                    if (mounted) context.showError('Failed: $e');
                  }
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RIGHT SIDEBAR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildRightSidebar(int activeNow, int memberCount) {
    final hoodData =
        _neighborhood?['neighborhood'] as Map<String, dynamic>?;
    final description =
        hoodData?['description'] as String? ?? '';
    final city = hoodData?['city'] as String? ?? '';
    final state = hoodData?['state'] as String? ?? '';
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');

    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7));
    final recentPosts = _boardEntries
        .where((e) => e.createdAt.isAfter(sevenDaysAgo))
        .length;
    final activeThreads = _boardEntries
        .where(
            (e) => e.replyCount > 0 && e.createdAt.isAfter(sevenDaysAgo))
        .length;
    final pinnedEntries =
        _boardEntries.where((e) => e.isPinned).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // About card
          _buildSidebarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navyText)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.navyText
                              .withValues(alpha: 0.65),
                          height: 1.4),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                if (location.isNotEmpty)
                  _buildInfoRow(Icons.location_on, location),
                _buildInfoRow(Icons.people, '$memberCount members'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Online Now card
          _buildSidebarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Online Now',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.navyText)),
                    const Spacer(),
                    Text('$activeNow',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brightNavy)),
                  ],
                ),
                if (_sidebarMembers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sidebarMembers.take(5).map((m) {
                      final displayName = m['display_name']
                              as String? ??
                          m['handle'] as String? ??
                          '';
                      final avatarUrl =
                          m['avatar_url'] as String? ?? '';
                      return SojornAvatar(
                        displayName: displayName,
                        avatarUrl: avatarUrl.isNotEmpty
                            ? avatarUrl
                            : null,
                        size: 36,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _tabController.animateTo(4),
                    child: Text('See all members',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brightNavy)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // This Week card
          _buildSidebarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This Week',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navyText)),
                const SizedBox(height: 8),
                _buildStatRow(
                    Icons.article_outlined, 'New posts', '$recentPosts'),
                const SizedBox(height: 5),
                _buildStatRow(Icons.forum_outlined, 'Active threads',
                    '$activeThreads'),
              ],
            ),
          ),

          // Pinned posts
          if (pinnedEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSidebarCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.push_pin,
                          size: 13, color: AppTheme.brightNavy),
                      const SizedBox(width: 4),
                      Text('Pinned',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.navyText)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...pinnedEntries.take(3).map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          onTap: () => _openBoardEntry(entry),
                          child: Text(
                            entry.body.length > 60
                                ? '${entry.body.substring(0, 60)}\u2026'
                                : entry.body,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.navyText
                                  .withValues(alpha: 0.65),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebarCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(
            color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 13,
              color: AppTheme.navyText.withValues(alpha: 0.45)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11,
                    color:
                        AppTheme.navyText.withValues(alpha: 0.65))),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
      IconData icon, String label, String value) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: AppTheme.navyText.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.navyText
                          .withValues(alpha: 0.65)))),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navyText)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOARD CARD + ACTIONS (shared)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBoardCard(BoardEntry entry) {
    final topicColor = entry.topic.color;
    final authorName = entry.authorDisplayName.isNotEmpty
        ? entry.authorDisplayName
        : entry.authorHandle;
    return GestureDetector(
      onTap: () => _openBoardEntry(entry),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: entry.isPinned
              ? AppTheme.brightNavy.withValues(alpha: 0.03)
              : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(
            color: entry.isPinned
                ? AppTheme.brightNavy.withValues(alpha: 0.24)
                : AppTheme.navyBlue.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: topicColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(entry.topic.icon,
                            size: 11, color: topicColor),
                        const SizedBox(width: 4),
                        Text(entry.topic.displayName,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: topicColor)),
                      ]),
                ),
                if (entry.tag != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.tag!.color
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.tag!.icon,
                              size: 10,
                              color: entry.tag!.color),
                          const SizedBox(width: 3),
                          Text(entry.tag!.displayName,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: entry.tag!.color)),
                        ]),
                  ),
                ],
                if (entry.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin,
                      size: 11, color: AppTheme.brightNavy),
                ],
                const Spacer(),
                Text(entry.getTimeAgo(),
                    style: TextStyle(
                        color: SojornColors.textDisabled,
                        fontSize: 10)),
                if (_isNeighborhoodAdmin) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 14,
                        color: SojornColors.textDisabled),
                    iconSize: 14,
                    padding: EdgeInsets.zero,
                    onSelected: (action) =>
                        _onAdminAction(action, entry),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'pin',
                          child: Text('Pin post',
                              style: TextStyle(fontSize: 13))),
                      const PopupMenuItem(
                          value: 'tag',
                          child: Text('Set tag',
                              style: TextStyle(fontSize: 13))),
                      const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove post',
                              style: TextStyle(fontSize: 13))),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SojornAvatar(
                  displayName: authorName,
                  avatarUrl: entry.authorAvatarUrl.isNotEmpty
                      ? entry.authorAvatarUrl
                      : null,
                  size: 36,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(authorName,
                      style: TextStyle(
                          color: SojornColors.postContent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(entry.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: SojornColors.postContentLight,
                    fontSize: 15,
                    height: 1.45)),
            if (entry.imageUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(entry.imageUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  entry.hasVoted
                      ? Icons.arrow_upward
                      : Icons.arrow_upward_outlined,
                  size: 13,
                  color: entry.hasVoted
                      ? AppTheme.brightNavy
                      : SojornColors.textDisabled,
                ),
                const SizedBox(width: 4),
                Text('${entry.upvotes}',
                    style: TextStyle(
                        color: entry.hasVoted
                            ? AppTheme.brightNavy
                            : SojornColors.textDisabled,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline,
                    size: 12,
                    color: SojornColors.textDisabled),
                const SizedBox(width: 4),
                Text('${entry.replyCount}',
                    style: TextStyle(
                        color: SojornColors.textDisabled,
                        fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openBoardEntry(BoardEntry entry) async {
    final updated = await Navigator.of(context).push<BoardEntry>(
        MaterialPageRoute(
            builder: (_) =>
                BoardEntryDetailScreen(entry: entry)));
    if (updated != null && mounted) {
      final idx =
          _boardEntries.indexWhere((e) => e.id == updated.id);
      if (idx >= 0) {
        setState(() {
          _boardEntries[idx] = updated;
          _recomputeStats();
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN ACTIONS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _onAdminAction(String action, BoardEntry entry) async {
    try {
      if (action == 'pin') {
        await ApiService.instance.callGoApi(
          '/board/entries/${entry.id}/pin',
          method: 'POST',
        );
        if (mounted) {
          setState(() {
            final idx =
                _boardEntries.indexWhere((e) => e.id == entry.id);
            if (idx >= 0) {
              _boardEntries[idx] = BoardEntry(
                id: entry.id,
                body: entry.body,
                topic: entry.topic,
                authorHandle: entry.authorHandle,
                authorDisplayName: entry.authorDisplayName,
                authorAvatarUrl: entry.authorAvatarUrl,
                upvotes: entry.upvotes,
                replyCount: entry.replyCount,
                hasVoted: entry.hasVoted,
                isPinned: true,
                imageUrl: entry.imageUrl,
                createdAt: entry.createdAt,
                lat: entry.lat,
                long: entry.long,
              );
            }
          });
        }
      } else if (action == 'tag') {
        _showTagPicker(entry);
        return;
      } else if (action == 'remove') {
        await ApiService.instance.callGoApi(
          '/board/entries/${entry.id}',
          method: 'DELETE',
        );
        if (mounted) {
          setState(() {
            _boardEntries
                .removeWhere((e) => e.id == entry.id);
            _recomputeStats();
          });
        }
      }
    } catch (e) {
      if (mounted) context.showError('Action failed: $e');
    }
  }

  void _showTagPicker(BoardEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set Tag',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
        children: [
          SimpleDialogOption(
            onPressed: () => _applyTag(ctx, entry, ''),
            child: Row(children: [
              Icon(Icons.close,
                  size: 18,
                  color: AppTheme.navyText
                      .withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              const Text('None',
                  style: TextStyle(fontSize: 14)),
            ]),
          ),
          for (final tag in BoardTag.values)
            SimpleDialogOption(
              onPressed: () =>
                  _applyTag(ctx, entry, tag.value),
              child: Row(children: [
                Icon(tag.icon, size: 18, color: tag.color),
                const SizedBox(width: 10),
                Text(tag.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: entry.tag == tag
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color:
                          entry.tag == tag ? tag.color : null,
                    )),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _applyTag(
      BuildContext ctx, BoardEntry entry, String tagValue) async {
    Navigator.of(ctx).pop();
    try {
      await ApiService.instance
          .updateBoardEntryTag(entry.id, tagValue);
      if (mounted) {
        setState(() {
          final idx = _boardEntries
              .indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            _boardEntries[idx] = tagValue.isEmpty
                ? entry.copyWith(clearTag: true)
                : entry.copyWith(
                    tag: BoardTag.fromString(tagValue));
          }
        });
      }
    } catch (e) {
      if (mounted) context.showError('Failed to set tag');
    }
  }

  void _openCreatePost() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CreateBoardPostSheet(
        centerLat: _lat,
        centerLong: _lng,
        onEntryCreated: (entry) {
          setState(() {
            _boardEntries.insert(0, entry);
            _recomputeStats();
          });
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Tab Bar Delegate for pinned mobile tab bar
// ══════════════════════════════════════════════════════════════════════════

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppTheme.cardSurface, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
