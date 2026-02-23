// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/board_entry.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';
import '../../widgets/composer/composer_bar.dart';
import '../beacon/board_entry_detail_screen.dart';
import '../beacon/create_board_post_sheet.dart';
import 'neighborhood_events_screen.dart';
import 'neighborhood_members_screen.dart';
import 'neighborhood_resources_screen.dart';

/// Standalone desktop screen for the Neighborhood hub.
///
/// Desktop: hero banner + quick-links + two-column (board | sidebar).
/// Mobile: hero banner + chips + board feed.
class NeighborhoodScreen extends StatefulWidget {
  const NeighborhoodScreen({super.key});

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

class _NeighborhoodScreenState extends State<NeighborhoodScreen> {
  Map<String, dynamic>? _neighborhood;
  List<BoardEntry> _boardEntries = [];
  bool _isLoading = true;
  bool _isLoadingBoard = false;
  bool _isNeighborhoodAdmin = false;
  BoardTopic? _selectedTopic;
  BoardTag? _selectedTag;
  String _boardSort = 'new';
  String _boardSearch = '';
  final _boardSearchController = TextEditingController();
  Timer? _searchDebounce;
  double _lat = 44.9778;
  double _lng = -93.2650;

  // Inline composer topic selection (separate from filter)
  BoardTopic _composeTopic = BoardTopic.community;

  // Precomputed sidebar stats — updated only when _boardEntries changes.
  int _maxUpvotes = 0;
  Map<BoardTopic, int> _topicCounts = {};

  // Members preview for sidebar (first 8)
  List<Map<String, dynamic>> _sidebarMembers = [];

  // Desktop chip scroll
  final _chipScrollCtrl = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _chipScrollCtrl.addListener(_onChipScroll);
    _loadData();
  }

  @override
  void dispose() {
    _chipScrollCtrl.removeListener(_onChipScroll);
    _chipScrollCtrl.dispose();
    _boardSearchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onChipScroll() {
    final pos = _chipScrollCtrl.position;
    setState(() {
      _canScrollLeft = pos.pixels > 4;
      _canScrollRight = pos.pixels < pos.maxScrollExtent - 4;
    });
  }

  void _recomputeStats() {
    if (_boardEntries.isEmpty) {
      _maxUpvotes = 0;
      _topicCounts = {};
      return;
    }
    _maxUpvotes = _boardEntries.map((e) => e.upvotes).reduce((a, b) => a > b ? a : b);
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

      if (mounted) setState(() => _neighborhood = hood);
      await _fetchBoardEntries(_lat, _lng);

      // Load member previews for sidebar
      final groupId = hoodData?['group_id'] as String?;
      if (groupId != null) {
        try {
          final members = await ApiService.instance.fetchGroupMembers(groupId);
          if (mounted) setState(() => _sidebarMembers = members.take(8).toList());
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
    final result = await NeighborhoodPickerSheet.show(context, isChangeMode: false);
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

      final dist = Geolocator.distanceBetween(_lat, _lng, pos.latitude, pos.longitude);
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
        topic: _selectedTopic?.value,
        sort: _boardSort,
        search: _boardSearch.isNotEmpty ? _boardSearch : null,
        tag: _selectedTag?.value,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    final name = hoodData?['name'] as String? ?? 'Neighborhood';
    final city = hoodData?['city'] as String? ?? '';
    final memberCount = hood?['member_count'] as int? ?? 0;
    final role = hood?['role'] as String? ?? 'resident';
    final isAdmin = role == 'admin' || role == 'moderator';
    final activeNow = hood?['active_now'] as int? ?? 0;
    final rightW = (totalWidth * 0.24).clamp(240.0, 300.0);

    return Container(
      color: AppTheme.scaffoldBg,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Main scrollable column ──
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hero banner
                        _buildHeroBanner(name, city, memberCount, role, isAdmin),
                        // Quick-link grid
                        _buildQuickLinks(),
                        // Inline composer
                        _buildInlineComposer(),
                        // Topic chips + sort
                        _buildBoardHeader(name),
                        // Board entries
                        _buildBoardEntries(),
                      ],
                    ),
                  ),
                ),
                // ── Right sidebar ──
                SizedBox(
                  width: rightW,
                  child: _buildRightSidebar(activeNow, memberCount, isAdmin, role),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Banner ──────────────────────────────────────────────────────────

  Widget _buildHeroBanner(String name, String city, int memberCount, String role, bool isAdmin) {
    final bannerUrl = (_neighborhood?['neighborhood'] as Map<String, dynamic>?)?['banner_url'] as String?;
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: SizedBox(
        height: 200,
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
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
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
                        child: const Icon(Icons.location_city, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (city.isNotEmpty)
                              Text(city,
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.people, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 5),
                      Text('$memberCount members',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isAdmin ? role[0].toUpperCase() + role.substring(1) : 'Resident',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Admin: Edit Banner
            if (isAdmin)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    // TODO: admin banner upload
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white.withValues(alpha: 0.9)),
                        const SizedBox(width: 5),
                        Text('Edit Banner',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
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

  // ── Quick-link grid ──────────────────────────────────────────────────────

  Widget _buildQuickLinks() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _buildQuickLinkCard(Icons.event, 'Events', AppTheme.brightNavy, () {
            final hood = _neighborhood?['neighborhood'] as Map<String, dynamic>?;
            final groupId = hood?['group_id'] as String?;
            final name = hood?['name'] as String? ?? 'Neighborhood';
            if (groupId == null) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NeighborhoodEventsScreen(
                groupId: groupId,
                neighborhoodName: name,
                userRole: _neighborhood?['role'] as String?,
              ),
            ));
          }),
          const SizedBox(width: 10),
          _buildQuickLinkCard(Icons.forum, 'Board', AppTheme.royalPurple, () {
            // Already on board — scroll could be added
          }),
          const SizedBox(width: 10),
          _buildQuickLinkCard(Icons.volunteer_activism, 'Resources', const Color(0xFF26A69A), () {
            final hood = _neighborhood?['neighborhood'] as Map<String, dynamic>?;
            final name = hood?['name'] as String? ?? 'Neighborhood';
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NeighborhoodResourcesScreen(
                neighborhoodName: name,
                lat: _lat,
                lng: _lng,
              ),
            ));
          }),
          const SizedBox(width: 10),
          _buildQuickLinkCard(Icons.people, 'Members', const Color(0xFF4CAF50), () {
            final hood = _neighborhood?['neighborhood'] as Map<String, dynamic>?;
            final groupId = hood?['group_id'] as String?;
            final name = hood?['name'] as String? ?? 'Neighborhood';
            if (groupId == null) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NeighborhoodMembersScreen(
                groupId: groupId,
                neighborhoodName: name,
                userRole: _neighborhood?['role'] as String?,
              ),
            ));
          }),
        ],
      ),
    );
  }

  Widget _buildQuickLinkCard(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SojornRadii.card),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // ── Inline Composer ──────────────────────────────────────────────────────

  Widget _buildInlineComposer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic selector chips (horizontal)
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
                        Icon(t.icon, size: 12, color: isSelected ? t.color : SojornColors.textDisabled),
                        const SizedBox(width: 4),
                        Text(t.displayName),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _composeTopic = t),
                    labelStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? t.color : SojornColors.postContentLight,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          // Composer bar
          ComposerBar(
            config: const ComposerConfig(
              allowImages: true,
              hintText: 'Share with your neighborhood\u2026',
            ),
            onSend: _onBoardComposerSend,
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
      final entry = BoardEntry.fromJson(data['entry'] as Map<String, dynamic>);
      setState(() {
        _boardEntries.insert(0, entry);
        _recomputeStats();
      });
      context.showSuccess('Posted to board!');
    }
  }

  // ── Board Header (sort + chips) ──────────────────────────────────────────

  void _onBoardSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _boardSearch = value.trim());
      _reloadBoard();
    });
  }

  Widget _buildBoardHeader(String name) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Icon(Icons.forum, color: AppTheme.brightNavy, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$name Board',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _boardSort,
                  isDense: true,
                  style: TextStyle(fontSize: 11, color: AppTheme.navyText),
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('New')),
                    DropdownMenuItem(value: 'top', child: Text('Top')),
                    DropdownMenuItem(value: 'hot', child: Text('Hot')),
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
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _boardSearchController,
              onChanged: _onBoardSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search posts...',
                hintStyle: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.35)),
                prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
                suffixIcon: _boardSearch.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _boardSearchController.clear();
                          setState(() => _boardSearch = '');
                          _reloadBoard();
                        },
                        child: Icon(Icons.close, size: 16, color: AppTheme.navyText.withValues(alpha: 0.4)),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: AppTheme.navyBlue.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SojornRadii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildTopicChipsScrollable(),
        // Tag filter chips
        _buildTagChips(),
        Divider(height: 1, color: AppTheme.navyText.withValues(alpha: 0.08)),
      ],
    );
  }

  Widget _buildTagChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildTagChip(null, 'All'),
          for (final tag in BoardTag.values) _buildTagChip(tag, tag.displayName),
        ],
      ),
    );
  }

  Widget _buildTagChip(BoardTag? tag, String label) {
    final isSelected = _selectedTag == tag;
    final chipColor = tag?.color ?? AppTheme.navyText;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTag = tag);
          _reloadBoard();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? chipColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(SojornRadii.full),
            border: Border.all(
              color: isSelected ? chipColor : AppTheme.navyText.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tag != null) ...[
                Icon(tag.icon, size: 12, color: isSelected ? chipColor : AppTheme.navyText.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? chipColor : AppTheme.navyText.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Board entries (non-scrollable list for SingleChildScrollView) ────────

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
              Icon(Icons.forum_outlined, size: 48, color: AppTheme.navyText.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text('No posts yet',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.navyText.withValues(alpha: 0.4))),
              const SizedBox(height: 4),
              Text('Be the first to post in your neighborhood',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.35))),
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

  // ── Right Sidebar ────────────────────────────────────────────────────────

  Widget _buildRightSidebar(int activeNow, int memberCount, bool isAdmin, String role) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active now
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(SojornRadii.card),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Active Now',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.navyText)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('$activeNow online \u00b7 $memberCount members',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.55))),
              ],
            ),
          ),
          // Members preview
          if (_sidebarMembers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(SojornRadii.card),
                border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people, size: 14, color: AppTheme.navyText.withValues(alpha: 0.6)),
                      const SizedBox(width: 6),
                      Text('Members',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.navyText)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          final hood = _neighborhood?['neighborhood'] as Map<String, dynamic>?;
                          final groupId = hood?['group_id'] as String?;
                          final name = hood?['name'] as String? ?? 'Neighborhood';
                          if (groupId == null) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => NeighborhoodMembersScreen(
                              groupId: groupId,
                              neighborhoodName: name,
                              userRole: _neighborhood?['role'] as String?,
                            ),
                          ));
                        },
                        child: Text('See all',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.brightNavy)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sidebarMembers.map((m) {
                      final displayName = m['display_name'] as String? ?? m['handle'] as String? ?? '';
                      final avatarUrl = m['avatar_url'] as String? ?? '';
                      return SojornAvatar(
                        displayName: displayName,
                        avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                        size: 36,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Board stats
          Text('Board',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navyText.withValues(alpha: 0.6))),
          const SizedBox(height: 6),
          _buildStatRow(Icons.article_outlined, 'Posts', '${_boardEntries.length}'),
          const SizedBox(height: 5),
          _buildStatRow(Icons.thumb_up_outlined, 'Top upvotes', '$_maxUpvotes'),
          if (_topicCounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Topics',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navyText.withValues(alpha: 0.6))),
            const SizedBox(height: 6),
            ..._topicCounts.entries.map((kv) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Icon(kv.key.icon, size: 12, color: kv.key.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(kv.key.displayName,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.navyText.withValues(alpha: 0.65))),
                      ),
                      Text('${kv.value}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kv.key.color)),
                    ],
                  ),
                )),
          ],
          // Admin section
          if (isAdmin) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(SojornRadii.card),
                border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.royalPurple)),
                  const SizedBox(height: 6),
                  _buildAdminAction(Icons.settings_outlined, 'Settings'),
                  _buildAdminAction(Icons.group_outlined, 'Members'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.navyText.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.65)))),
          Text(value,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
        ],
      ),
    );
  }

  Widget _buildAdminAction(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              Icon(icon, size: 13, color: AppTheme.royalPurple.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.royalPurple.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicChipsScrollable() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final chips = ListView(
      controller: _chipScrollCtrl,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _buildTopicChip(null, 'All'),
        ...BoardTopic.values.map((t) => _buildTopicChip(t, t.displayName)),
      ],
    );

    if (!isDesktop) {
      return SizedBox(height: 40, child: chips);
    }

    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          chips,
          if (_canScrollLeft)
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: _buildScrollArrow(
                Icons.chevron_left,
                () => _chipScrollCtrl.animateTo(
                  (_chipScrollCtrl.offset - 120).clamp(0, double.infinity),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                ),
              ),
            ),
          if (_canScrollRight)
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: _buildScrollArrow(
                Icons.chevron_right,
                () => _chipScrollCtrl.animateTo(
                  _chipScrollCtrl.offset + 120,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.scaffoldBg,
              AppTheme.scaffoldBg.withValues(alpha: 0),
            ],
            begin: icon == Icons.chevron_left ? Alignment.centerLeft : Alignment.centerRight,
            end: icon == Icons.chevron_left ? Alignment.centerRight : Alignment.centerLeft,
          ),
        ),
        child: Icon(icon, size: 18, color: AppTheme.navyText.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _buildTopicChip(BoardTopic? topic, String label) {
    final isSelected = _selectedTopic == topic;
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 5, bottom: 5, left: 2),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedTopic = topic);
          _reloadBoard();
        },
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildBoardCard(BoardEntry entry) {
    final topicColor = entry.topic.color;
    final authorName =
        entry.authorDisplayName.isNotEmpty ? entry.authorDisplayName : entry.authorHandle;
    return GestureDetector(
      onTap: () async {
        final updated = await Navigator.of(context)
            .push<BoardEntry>(MaterialPageRoute(builder: (_) => BoardEntryDetailScreen(entry: entry)));
        if (updated != null && mounted) {
          final idx = _boardEntries.indexWhere((e) => e.id == updated.id);
          if (idx >= 0) {
            setState(() {
              _boardEntries[idx] = updated;
              _recomputeStats();
            });
          }
        }
      },
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: topicColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry.topic.icon, size: 11, color: topicColor),
                    const SizedBox(width: 4),
                    Text(entry.topic.displayName,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600, color: topicColor)),
                  ]),
                ),
                if (entry.tag != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.tag!.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(entry.tag!.icon, size: 10, color: entry.tag!.color),
                      const SizedBox(width: 3),
                      Text(entry.tag!.displayName,
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w700, color: entry.tag!.color)),
                    ]),
                  ),
                ],
                if (entry.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin, size: 11, color: AppTheme.brightNavy),
                ],
                const Spacer(),
                Text(entry.getTimeAgo(),
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                if (_isNeighborhoodAdmin) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 14, color: SojornColors.textDisabled),
                    iconSize: 14,
                    padding: EdgeInsets.zero,
                    onSelected: (action) => _onAdminAction(action, entry),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'pin',
                          child: Text('Pin post', style: TextStyle(fontSize: 13))),
                      const PopupMenuItem(
                          value: 'tag',
                          child: Text('Set tag', style: TextStyle(fontSize: 13))),
                      const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove post', style: TextStyle(fontSize: 13))),
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
                  avatarUrl:
                      entry.authorAvatarUrl.isNotEmpty ? entry.authorAvatarUrl : null,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(authorName,
                      style: TextStyle(
                          color: SojornColors.postContent,
                          fontSize: 12,
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
                    color: SojornColors.postContentLight, fontSize: 13, height: 1.4)),
            if (entry.imageUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(entry.imageUrl!,
                    height: 120, width: double.infinity, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  entry.hasVoted ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                  size: 13,
                  color: entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled,
                ),
                const SizedBox(width: 4),
                Text('${entry.upvotes}',
                    style: TextStyle(
                        color:
                            entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline, size: 12, color: SojornColors.textDisabled),
                const SizedBox(width: 4),
                Text('${entry.replyCount}',
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout() {
    final hoodData = _neighborhood?['neighborhood'] as Map<String, dynamic>?;
    final name = hoodData?['name'] as String? ?? 'Neighborhood';
    final city = hoodData?['city'] as String? ?? '';
    final memberCount = _neighborhood?['member_count'] as int? ?? 0;
    final role = _neighborhood?['role'] as String? ?? 'resident';
    final isAdmin = role == 'admin' || role == 'moderator';

    return Scaffold(
      body: Column(
        children: [
          // Mini hero banner for mobile
          _buildHeroBanner(name, city, memberCount, role, isAdmin),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _boardSearchController,
                onChanged: _onBoardSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search posts...',
                  hintStyle: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.35)),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
                  suffixIcon: _boardSearch.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _boardSearchController.clear();
                            setState(() => _boardSearch = '');
                            _reloadBoard();
                          },
                          child: Icon(Icons.close, size: 16, color: AppTheme.navyText.withValues(alpha: 0.4)),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  filled: true,
                  fillColor: AppTheme.navyBlue.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SojornRadii.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          // Topic chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _buildTopicChip(null, 'All'),
                ...BoardTopic.values.map((t) => _buildTopicChip(t, t.displayName)),
              ],
            ),
          ),
          // Tag chips
          _buildTagChips(),
          const Divider(height: 1),
          Expanded(child: _buildBoardList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _neighborhood != null ? _openCreatePost : null,
        backgroundColor: AppTheme.brightNavy,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildBoardList() {
    if (_isLoadingBoard && _boardEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_boardEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: AppTheme.navyText.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text('No posts yet',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyText.withValues(alpha: 0.4))),
            const SizedBox(height: 4),
            Text('Be the first to post in your neighborhood',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.35))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reloadBoard,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        itemCount: _boardEntries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _buildBoardCard(_boardEntries[i]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS
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
            final idx = _boardEntries.indexWhere((e) => e.id == entry.id);
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
            _boardEntries.removeWhere((e) => e.id == entry.id);
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
        title: const Text('Set Tag', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        children: [
          // "None" option to clear tag
          SimpleDialogOption(
            onPressed: () => _applyTag(ctx, entry, ''),
            child: Row(children: [
              Icon(Icons.close, size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              const Text('None', style: TextStyle(fontSize: 14)),
            ]),
          ),
          for (final tag in BoardTag.values)
            SimpleDialogOption(
              onPressed: () => _applyTag(ctx, entry, tag.value),
              child: Row(children: [
                Icon(tag.icon, size: 18, color: tag.color),
                const SizedBox(width: 10),
                Text(tag.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: entry.tag == tag ? FontWeight.w700 : FontWeight.w400,
                      color: entry.tag == tag ? tag.color : null,
                    )),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _applyTag(BuildContext ctx, BoardEntry entry, String tagValue) async {
    Navigator.of(ctx).pop();
    try {
      await ApiService.instance.updateBoardEntryTag(entry.id, tagValue);
      if (mounted) {
        setState(() {
          final idx = _boardEntries.indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            _boardEntries[idx] = tagValue.isEmpty
                ? entry.copyWith(clearTag: true)
                : entry.copyWith(tag: BoardTag.fromString(tagValue));
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
