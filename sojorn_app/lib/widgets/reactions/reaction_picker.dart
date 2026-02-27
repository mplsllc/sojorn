// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/reactions_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

class ReactionPicker extends ConsumerStatefulWidget {
  final Function(String) onReactionSelected;
  final VoidCallback? onClosed;
  final List<String>? reactions;
  final Map<String, int>? reactionCounts;
  final Set<String>? myReactions;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
    this.onClosed,
    this.reactions,
    this.reactionCounts,
    this.myReactions,
  });

  @override
  ConsumerState<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends ConsumerState<ReactionPicker>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<String> _filteredReactions = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _ensureTabController(ReactionPackage package) {
    final neededLength = package.tabOrder.length;
    if (_tabController != null && _tabController!.length == neededLength) {
      return;
    }
    _tabController?.dispose();
    _tabController = TabController(length: neededLength, vsync: this);
    _tabController!.addListener(() {
      if (mounted) {
        setState(() {
          _currentTabIndex = _tabController!.index;
          _clearSearch();
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _filteredReactions = [];
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredReactions = [];
      });
    } else {
      setState(() {
        _isSearching = true;
        _filteredReactions = _filterReactions(query);
      });
    }
  }

  List<String> _filterReactions(String query) {
    final reactions = _filterCurrentTab();
    return reactions.where((reaction) {
      if (reaction.startsWith('assets/reactions/') ||
          reaction.startsWith('https://')) {
        final fileName = reaction.split('/').last.toLowerCase();
        return fileName.contains(query);
      }
      return reaction.toLowerCase().contains(query);
    }).toList();
  }

  List<String> _filterCurrentTab() {
    final package = ref.read(reactionPackageProvider).value;
    if (package == null) return [];
    final tabOrder = package.tabOrder;
    if (_currentTabIndex >= tabOrder.length) return [];
    return package.reactionSets[tabOrder[_currentTabIndex]] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final packageAsync = ref.watch(reactionPackageProvider);

    return packageAsync.when(
      loading: () => _buildLoadingDialog(),
      error: (_, __) => _buildLoadingDialog(),
      data: (package) {
        _ensureTabController(package);
        if (_tabController == null) return _buildLoadingDialog();
        return _buildPicker(package);
      },
    );
  }

  Widget _buildLoadingDialog() {
    return _SheetShell(
      child: const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildPicker(ReactionPackage package) {
    final tabOrder = package.tabOrder;
    final reactionSets = package.reactionSets;

    final reactionCounts = widget.reactionCounts ?? {};
    final myReactions = widget.myReactions ?? {};

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
            child: Row(
              children: [
                Text(
                  _isSearching ? 'Search Reactions' : 'Add Reaction',
                  style: GoogleFonts.inter(
                    color: AppTheme.navyBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onClosed?.call();
                  },
                  icon: Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

            // Search bar
            Container(
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.navyBlue.withValues(alpha: 0.1),
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(
                  color: AppTheme.navyBlue,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search reactions...',
                  hintStyle: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tabs
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController!,
                onTap: (index) {
                  setState(() {
                    _currentTabIndex = index;
                    _isSearching = false;
                    _searchController.clear();
                    _filteredReactions = [];
                  });
                },
                indicator: BoxDecoration(
                  color: AppTheme.brightNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: AppTheme.textSecondary,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: tabOrder
                    .map((name) => Tab(text: name.toUpperCase()))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),

            // No results message
            if (_isSearching && _filteredReactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No reactions found for "${_searchController.text}"',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Reaction grid
            SizedBox(
              height: 420,
              child: TabBarView(
                controller: _tabController!,
                children: tabOrder.map((tabName) {
                  final tabReactions = reactionSets[tabName] ?? [];
                  final isEmoji = tabName == 'emoji';
                  final credit = package.folderCredits[tabName];

                  return Column(
                    children: [
                      Expanded(
                        child: _buildReactionGrid(
                          _isSearching ? _filteredReactions : tabReactions,
                          reactionCounts,
                          myReactions,
                          !isEmoji,
                        ),
                      ),
                      if (credit != null && credit.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(color: AppTheme.textDisabled),
                              const SizedBox(height: 8),
                              Text(
                                'Credits:',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _buildCreditDisplay(credit),
                            ],
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ));
  }

  Widget _buildCreditDisplay(String credit) {
    return MarkdownBody(
      data: credit,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.inter(fontSize: 10, color: AppTheme.textPrimary),
        h1: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary),
        h2: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary),
        listBullet:
            GoogleFonts.inter(fontSize: 10, color: AppTheme.textPrimary),
        strong: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary),
        em: GoogleFonts.inter(
            fontSize: 10,
            fontStyle: FontStyle.italic,
            color: AppTheme.textPrimary),
        a: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.brightNavy,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.brightNavy.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _buildReactionGrid(
    List<String> reactions,
    Map<String, int> reactionCounts,
    Set<String> myReactions,
    bool useImages,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: reactions.length,
      itemBuilder: (context, index) {
        final reaction = reactions[index];
        final count = reactionCounts[reaction] ?? 0;
        final isSelected = myReactions.contains(reaction);

        return Material(
          color: SojornColors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              // CDN URLs and emoji are passed as-is; local assets get 'asset:' prefix
              final result =
                  reaction.startsWith('assets/') ? 'asset:$reaction' : reaction;
              widget.onReactionSelected(result);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.brightNavy.withValues(alpha: 0.2)
                    : AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
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
                        : _buildEmojiReaction(reaction),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: GoogleFonts.inter(
                            color: SojornColors.basicWhite,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmojiReaction(String emoji) {
    return Text(emoji, style: const TextStyle(fontSize: 24));
  }

  Widget _buildImageReaction(String reaction) {
    // CDN URL
    if (reaction.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: reaction,
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox(width: 32, height: 32),
        errorWidget: (_, __, ___) => Icon(
          Icons.image_not_supported,
          size: 24,
          color: AppTheme.textSecondary,
        ),
      );
    }

    // Local asset (with or without 'asset:' prefix)
    final imagePath = reaction.startsWith('asset:')
        ? reaction.replaceFirst('asset:', '')
        : reaction;

    if (imagePath.endsWith('.svg')) {
      return SvgPicture.asset(
        imagePath,
        width: 32,
        height: 32,
        placeholderBuilder: (context) => Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.textSecondary,
          ),
        ),
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.image_not_supported,
          size: 24,
          color: AppTheme.textSecondary,
        ),
      );
    }

    return Image.asset(
      imagePath,
      width: 32,
      height: 32,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.image_not_supported,
        size: 24,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

// Bottom-sheet shell: rounded top corners + drag handle + keyboard padding
class _SheetShell extends StatelessWidget {
  final Widget child;
  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SojornRadii.modal),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
