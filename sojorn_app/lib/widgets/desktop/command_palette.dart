// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/api_service.dart';
import '../../models/search_results.dart';

// ---------------------------------------------------------------------------
// Internal result model
// ---------------------------------------------------------------------------

enum _ResultType { navigation, person, post }

class _SearchResult {
  final _ResultType type;
  final String label;
  final String? subtitle;
  final IconData icon;
  final int? branchIndex;
  final String? route;
  final String? userId;
  final String? postId;

  const _SearchResult({
    required this.type,
    required this.label,
    required this.icon,
    this.subtitle,
    this.branchIndex,
    this.route,
    this.userId,
    this.postId,
  });
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class CommandPaletteOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final void Function(int branchIndex)? onNavigateBranch;
  final void Function(String route)? onNavigateRoute;

  const CommandPaletteOverlay({
    super.key,
    required this.onDismiss,
    this.onNavigateBranch,
    this.onNavigateRoute,
  });

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();

  Timer? _debounce;
  int _selectedIndex = 0;
  bool _loading = false;

  List<SearchUser> _apiUsers = [];
  List<SearchPost> _apiPosts = [];

  // ── Static navigation items ──────────────────────────────────────────────

  static const List<_SearchResult> _navItems = [
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Home',
      icon: Icons.home,
      branchIndex: 0,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Quips',
      icon: Icons.video_collection,
      branchIndex: 1,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Beacons',
      icon: Icons.sensors,
      branchIndex: 2,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Discover',
      icon: Icons.explore,
      branchIndex: 4,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Profile',
      icon: Icons.person,
      branchIndex: 3,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Messages',
      icon: Icons.mail,
      branchIndex: 5,
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Settings',
      icon: Icons.settings,
      route: '/settings',
    ),
    _SearchResult(
      type: _ResultType.navigation,
      label: 'Groups',
      icon: Icons.group,
      route: '/groups',
    ),
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    // Autofocus the search field after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  // ── Query / API ──────────────────────────────────────────────────────────

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();

    // Reset selection when query changes.
    setState(() => _selectedIndex = 0);

    if (query.isEmpty) {
      setState(() {
        _apiUsers = [];
        _apiPosts = [];
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      try {
        final results = await ApiService.instance.search(query);
        if (!mounted) return;
        setState(() {
          _apiUsers = results.users;
          _apiPosts = results.posts;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    });
  }

  // ── Build flat result list ───────────────────────────────────────────────

  List<_SearchResult> _buildResults() {
    final query = _controller.text.trim().toLowerCase();
    final results = <_SearchResult>[];

    // Navigation – always present, filtered by query.
    final filteredNav = query.isEmpty
        ? _navItems
        : _navItems
            .where((r) => r.label.toLowerCase().contains(query))
            .toList();
    results.addAll(filteredNav);

    // People
    for (final u in _apiUsers) {
      results.add(_SearchResult(
        type: _ResultType.person,
        label: u.displayName,
        subtitle: '@${u.username}',
        icon: Icons.person_outline,
        userId: u.id,
        route: '/profile/${u.id}',
      ));
    }

    // Posts
    for (final p in _apiPosts) {
      final body =
          p.body.length > 50 ? '${p.body.substring(0, 50)}...' : p.body;
      results.add(_SearchResult(
        type: _ResultType.post,
        label: body,
        subtitle: '@${p.authorHandle}',
        icon: Icons.article_outlined,
        postId: p.id,
        route: '/post/${p.id}',
      ));
    }

    return results;
  }

  // ── Keyboard handling ────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final results = _buildResults();

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, results.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, results.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (results.isNotEmpty && _selectedIndex < results.length) {
        _activateResult(results[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateResult(_SearchResult result) {
    if (result.branchIndex != null && widget.onNavigateBranch != null) {
      widget.onNavigateBranch!(result.branchIndex!);
      widget.onDismiss();
      return;
    }
    if (result.route != null && widget.onNavigateRoute != null) {
      widget.onNavigateRoute!(result.route!);
      widget.onDismiss();
      return;
    }
    // Fallback: just close.
    widget.onDismiss();
  }

  // ── Section header helper ────────────────────────────────────────────────

  String? _sectionHeaderFor(
      int index, List<_SearchResult> results, _ResultType type) {
    if (results[index].type != type) return null;
    if (index == 0) {
      return _headerLabel(type);
    }
    if (results[index - 1].type != type) {
      return _headerLabel(type);
    }
    return null;
  }

  static String _headerLabel(_ResultType type) {
    switch (type) {
      case _ResultType.navigation:
        return 'Navigation';
      case _ResultType.person:
        return 'People';
      case _ResultType.post:
        return 'Posts';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final results = _buildResults();

    // Clamp selected index.
    if (results.isNotEmpty && _selectedIndex >= results.length) {
      _selectedIndex = results.length - 1;
    }

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Material(
        color: SojornColors.overlayScrim,
        child: Focus(
          focusNode: _keyboardFocus,
          onKeyEvent: _handleKeyEvent,
          child: Center(
            child: GestureDetector(
              // Prevent taps inside the palette from dismissing.
              onTap: () {},
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius:
                        BorderRadius.circular(SojornRadii.modal),
                    boxShadow: [
                      BoxShadow(
                        color: SojornColors.overlayDark.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(SojornRadii.modal),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSearchField(),
                        const Divider(height: 1, thickness: 1),
                        Flexible(child: _buildResultsList(results)),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Search field ─────────────────────────────────────────────────────────

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _controller,
        focusNode: _searchFocus,
        style: GoogleFonts.inter(
          fontSize: 15,
          color: AppTheme.navyBlue,
        ),
        decoration: InputDecoration(
          hintText: 'Search or jump to...',
          hintStyle: GoogleFonts.inter(
            fontSize: 15,
            color: AppTheme.navyText.withValues(alpha: 0.45),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: AppTheme.brightNavy,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ── Results list ─────────────────────────────────────────────────────────

  Widget _buildResultsList(List<_SearchResult> results) {
    if (_loading && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.royalPurple,
            ),
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No results',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.navyText.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];

        // Determine if we need a section header above this item.
        String? header;
        for (final type in _ResultType.values) {
          header = _sectionHeaderFor(index, results, type);
          if (header != null) break;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null)
              Padding(
                padding:
                    const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 4),
                child: Text(
                  header,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyText.withValues(alpha: 0.45),
                  ),
                ),
              ),
            _buildResultRow(result, index),
          ],
        );
      },
    );
  }

  Widget _buildResultRow(_SearchResult result, int index) {
    final isSelected = index == _selectedIndex;

    return GestureDetector(
      onTap: () => _activateResult(result),
      child: MouseRegion(
        onEnter: (_) => setState(() => _selectedIndex = index),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.royalPurple.withValues(alpha: 0.08)
                : SojornColors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                result.icon,
                size: 18,
                color: AppTheme.brightNavy,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: result.subtitle != null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.navyBlue,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            result.subtitle!,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.navyText.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      )
                    : Text(
                        result.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.navyBlue,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer with keyboard hint ────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerRight,
      child: Text(
        '\u2318K',
        style: GoogleFonts.inter(
          fontSize: 11,
          color: AppTheme.navyText.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
