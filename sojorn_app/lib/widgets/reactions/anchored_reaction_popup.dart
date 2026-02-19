import 'dart:math' show min;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/reactions_provider.dart';
import '../../theme/app_theme.dart';

/// Quick-emoji pill that expands in-place to the full tabbed picker.
///
/// Anchored near [anchorPosition] and clamped to the viewport — never
/// escapes off-screen. Tapping "+" smoothly animates the pill into the
/// full picker without closing and re-opening the dialog.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   barrierColor: Colors.black12,
///   builder: (_) => AnchoredReactionPopup(
///     anchorPosition: tapPosition,
///     myReactions: _myReactions,
///     reactionCounts: _reactionCounts,
///     onReaction: _toggleReaction,
///   ),
/// );
/// ```
class AnchoredReactionPopup extends ConsumerStatefulWidget {
  final Offset anchorPosition;
  final Set<String> myReactions;
  final Map<String, int>? reactionCounts;
  final Function(String) onReaction;

  const AnchoredReactionPopup({
    super.key,
    required this.anchorPosition,
    required this.myReactions,
    this.reactionCounts,
    required this.onReaction,
  });

  @override
  ConsumerState<AnchoredReactionPopup> createState() =>
      _AnchoredReactionPopupState();
}

class _AnchoredReactionPopupState extends ConsumerState<AnchoredReactionPopup>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // Expanded picker state
  TabController? _tabController;
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<String> _filteredReactions = [];

  static const _quickEmojis = ['❤️', '👍', '😂', '😮', '😢', '😡', '🎉', '🔥'];
  static const _pillW = 320.0;
  static const _pillH = 52.0;
  static const _expandedW = 340.0;
  static const _expandedH = 500.0;
  static const _animDuration = Duration(milliseconds: 230);
  static const _animCurve = Curves.easeOutCubic;

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Tab controller ──────────────────────────────────────────────────

  void _ensureTabController(ReactionPackage package) {
    final len = package.tabOrder.length;
    if (_tabController != null && _tabController!.length == len) return;
    _tabController?.dispose();
    _tabController = TabController(length: len, vsync: this);
    _tabController!.addListener(() {
      if (mounted) {
        setState(() {
          _currentTabIndex = _tabController!.index;
          _searchController.clear();
          _isSearching = false;
          _filteredReactions = [];
        });
      }
    });
  }

  void _onSearch(ReactionPackage package) {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() { _isSearching = false; _filteredReactions = []; });
      return;
    }
    final tabName = package.tabOrder[_currentTabIndex];
    final reactions = package.reactionSets[tabName] ?? [];
    setState(() {
      _isSearching = true;
      _filteredReactions = reactions.where((r) {
        final name = r.split('/').last.replaceAll(RegExp(r'\..*'), '').toLowerCase();
        return name.contains(query) || r.toLowerCase().contains(query);
      }).toList();
    });
  }

  // ── Positioning ─────────────────────────────────────────────────────

  (double left, double top, double w, double h) _calcBounds(Size screen) {
    final tap = widget.anchorPosition;
    // Always clamp to available screen width so pill never overflows.
    final maxW = screen.width - 16.0;
    final w = min(_expanded ? _expandedW : _pillW, maxW);
    final h = _expanded
        ? min(_expandedH, screen.height * 0.70)
        : _pillH;

    // Horizontal: center on tap, clamped to margins.
    final left = (tap.dx - w / 2).clamp(8.0, screen.width - w - 8);

    // Vertical: prefer above tap (grows upward). Fall back to below, then center.
    final anchorBottom = tap.dy - 12;
    double top;
    if (anchorBottom - h >= 8) {
      top = anchorBottom - h;
    } else if (tap.dy + 12 + h <= screen.height - 8) {
      top = tap.dy + 12;
    } else {
      top = (screen.height - h) / 2;
    }
    top = top.clamp(8.0, screen.height - h - 8);
    return (left, top, w, h);
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final (left, top, w, h) = _calcBounds(screen);
    final radius = _expanded ? 20.0 : 30.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: _animDuration,
            curve: _animCurve,
            left: left,
            top: top,
            width: w,
            height: h,
            child: GestureDetector(
              onTap: () {}, // absorb taps so barrier doesn't dismiss
              child: AnimatedContainer(
                duration: _animDuration,
                curve: _animCurve,
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Material(
                    type: MaterialType.transparency,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeIn,
                      child: _expanded
                          ? _buildExpandedContent()
                          : _buildPill(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pill (compact) ───────────────────────────────────────────────────

  Widget _buildPill() {
    // Use LayoutBuilder so the pill measures its actual available width
    // and fits as many emojis as possible without overflowing.
    return LayoutBuilder(
      key: const ValueKey('pill'),
      builder: (ctx, constraints) {
        const outerH = 6.0;
        const outerW = 6.0;
        const emojiFs = 22.0;
        const emojiPad = 3.0;   // horizontal padding per side
        const emojiSlot = emojiFs + emojiPad * 2 + 4; // ~32px per emoji
        const addBtnW = 30.0;
        const gap = 4.0;

        final available = constraints.maxWidth - outerW * 2 - addBtnW - gap;
        final maxEmojis = (available / emojiSlot).floor().clamp(1, _quickEmojis.length);
        final emojis = _quickEmojis.take(maxEmojis).toList();

        return SizedBox(
          height: _pillH,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: outerW, vertical: outerH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...emojis.map((emoji) {
                  final isActive = widget.myReactions.contains(emoji);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                      widget.onReaction(emoji);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: emojiPad, vertical: emojiPad),
                      decoration: isActive
                          ? BoxDecoration(
                              color: AppTheme.brightNavy.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(emoji,
                          style: const TextStyle(fontSize: emojiFs)),
                    ),
                  );
                }),
                const SizedBox(width: gap),
                // "+" — expands picker in place
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _expanded = true);
                  },
                  child: Container(
                    width: addBtnW,
                    height: addBtnW,
                    decoration: BoxDecoration(
                      color: AppTheme.navyBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(addBtnW / 2),
                    ),
                    child: Icon(Icons.add, size: 16, color: AppTheme.navyBlue),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Expanded picker ──────────────────────────────────────────────────

  Widget _buildExpandedContent() {
    final packageAsync = ref.watch(reactionPackageProvider);
    return packageAsync.when(
      loading: () => const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      ),
      error: (_, __) => Center(
        key: const ValueKey('error'),
        child: Text('Failed to load', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
      ),
      data: (package) {
        _ensureTabController(package);
        if (_tabController == null) {
          return const Center(key: ValueKey('wait'), child: CircularProgressIndicator());
        }
        return _buildPicker(package);
      },
    );
  }

  Widget _buildPicker(ReactionPackage package) {
    final tabOrder = package.tabOrder;
    final reactionSets = package.reactionSets;
    final counts = widget.reactionCounts ?? {};

    return Column(
      key: const ValueKey('expanded'),
      children: [
        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
          child: Row(
            children: [
              Text(
                _isSearching ? 'Search Reactions' : 'Add Reaction',
                style: GoogleFonts.inter(
                  color: AppTheme.navyBlue, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Back to pill
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _expanded = false;
                  _searchController.clear();
                  _isSearching = false;
                  _filteredReactions = [];
                }),
                icon: Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary, size: 20),
                tooltip: 'Collapse',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: AppTheme.textSecondary, size: 18),
              ),
            ],
          ),
        ),

        // ── Search ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _onSearch(package),
              style: GoogleFonts.inter(color: AppTheme.navyBlue, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search reactions...',
                hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                suffixIcon: _isSearching
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.clear, color: AppTheme.textSecondary, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch(package);
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                isDense: true,
              ),
            ),
          ),
        ),

        // ── Tab bar ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController!,
              indicator: BoxDecoration(
                color: AppTheme.brightNavy,
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: tabOrder.map((n) => Tab(text: n.toUpperCase())).toList(),
            ),
          ),
        ),

        // ── Grid ──────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController!,
            children: tabOrder.map((tabName) {
              final reactions = _isSearching
                  ? _filteredReactions
                  : (reactionSets[tabName] ?? []);
              final isEmoji = tabName == 'emoji';
              return _buildGrid(reactions, counts, !isEmoji);
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildGrid(List<String> reactions, Map<String, int> counts, bool useImages) {
    if (reactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isSearching ? 'No reactions found' : 'No reactions',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: reactions.length,
      itemBuilder: (ctx, i) {
        final reaction = reactions[i];
        final count = counts[reaction] ?? 0;
        final isSelected = widget.myReactions.contains(reaction);
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop();
            final result = reaction.startsWith('assets/') ? 'asset:$reaction' : reaction;
            widget.onReaction(result);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.brightNavy.withValues(alpha: 0.2)
                  : AppTheme.navyBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppTheme.brightNavy
                    : AppTheme.navyBlue.withValues(alpha: 0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: useImages
                      ? _buildImageReaction(reaction)
                      : Text(reaction, style: const TextStyle(fontSize: 22)),
                ),
                if (count > 0)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 7, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageReaction(String reaction) {
    if (reaction.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: reaction,
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox(width: 28, height: 28),
        errorWidget: (_, __, ___) =>
            Icon(Icons.image_not_supported, size: 20, color: AppTheme.textSecondary),
      );
    }
    final path = reaction.startsWith('asset:')
        ? reaction.replaceFirst('asset:', '')
        : reaction;
    if (path.endsWith('.svg')) {
      return SvgPicture.asset(
        path,
        width: 28,
        height: 28,
        placeholderBuilder: (_) => const SizedBox(width: 28, height: 28),
      );
    }
    return Image.asset(
      path,
      width: 28,
      height: 28,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.image_not_supported, size: 20, color: AppTheme.textSecondary),
    );
  }
}

/// Helper — call this anywhere instead of building the dialog manually.
void showAnchoredReactionPicker({
  required BuildContext context,
  required Offset tapPosition,
  required Set<String> myReactions,
  Map<String, int>? reactionCounts,
  required Function(String) onReaction,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black12,
    builder: (_) => AnchoredReactionPopup(
      anchorPosition: tapPosition,
      myReactions: myReactions,
      reactionCounts: reactionCounts,
      onReaction: onReaction,
    ),
  );
}
